import argparse
import subprocess
import sys

import numpy as np

from common import CLIPS, IDLE, TAKES, background, ensure, ffmpeg, frame_times, probe, project

STRIP_W = 72
STRIP_H = 820


def latest_take(shot):
    takes = sorted((TAKES / shot).glob("*.mkv"), key=lambda path: path.stat().st_mtime)
    if not takes:
        sys.exit(f"no takes for {shot}")
    return takes[-1]


def read_frames(path, filters, width, height, channels):
    pix = {1: "gray", 3: "rgb24"}[channels]
    process = subprocess.Popen(
        [ffmpeg(), "-hide_banner", "-loglevel", "fatal", "-i", str(path), "-vf", filters,
         "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", pix, "-"],
        stdout=subprocess.PIPE, creationflags=IDLE,
    )
    size = width * height * channels
    while True:
        chunk = process.stdout.read(size)
        if len(chunk) < size:
            break
        yield np.frombuffer(chunk, np.uint8).reshape(height, width, channels) if channels > 1 else np.frombuffer(chunk, np.uint8).reshape(height, width)
    process.wait()


def cell_box(code, origin, index):
    ox, oy = origin
    x = ox + code["x"]
    y = oy + code["y"] + index * (code["h"] + code["gap"])
    return x, y


def cell_value(gray, code, origin, index):
    x, y = cell_box(code, origin, index)
    cx, cy = x + code["w"] // 2, y + code["h"] // 2
    patch = gray[cy - 4:cy + 5, cx - 6:cx + 7]
    return float(patch.mean()) if patch.size else 0.0


def edge(profile, start, step):
    index = start
    while 0 <= index + step < len(profile) and profile[index + step] > 127:
        index += step
    return index


def find_origin(gray, code):
    best, score = (0, 0), -1.0
    for oy in range(-6, 24):
        for ox in range(-6, 24):
            x, y = cell_box(code, (ox, oy), 0)
            if x < 0 or y < 0:
                continue
            inner = gray[y + 3:y + code["h"] - 3, x + 3:x + code["w"] - 3]
            if inner.size == 0:
                continue
            value = float(inner.min())
            if value > score:
                best, score = (ox, oy), value
    if score < 150:
        return best, score
    x, y = cell_box(code, best, 0)
    cx, cy = x + code["w"] // 2, y + code["h"] // 2
    left = edge(gray[cy, :].astype(int), cx, -1)
    top = edge(gray[:, cx].astype(int), cy, -1)
    return (left - code["x"], top - code["y"]), score


def decode(gray, code, origin):
    bits = code["bits"]
    id_bits = code.get("id_bits", 0)
    cells = [cell_value(gray, code, origin, index) > 127 for index in range(bits + id_bits + 3)]
    if not cells[0]:
        return None
    value = 0
    shot = 0
    ones = 0
    for bit in range(bits):
        if cells[2 + bit]:
            value |= 1 << bit
            ones += 1
    for bit in range(id_bits):
        if cells[2 + bits + bit]:
            shot |= 1 << bit
            ones += 1
    if (ones % 2 == 1) != cells[2 + bits + id_bits]:
        return None
    return cells[1], value / 1000.0, shot


def scan(path, code):
    frames = read_frames(path, f"crop={STRIP_W}:{STRIP_H}:0:0", STRIP_W, STRIP_H, 1)
    origin = None
    stamps = []
    for gray in frames:
        if origin is None:
            origin, score = find_origin(gray, code)
            if score < 150:
                origin = None
                stamps.append(None)
                continue
        stamps.append(decode(gray, code, origin))
    return origin, stamps


def plan(stamps, fps, shutter, start, end, shot_id=None):
    running = [(index, stamp[1]) for index, stamp in enumerate(stamps)
               if stamp and stamp[0] and (shot_id is None or stamp[2] == shot_id)]
    if not running:
        sys.exit("no running frames found; was the shot triggered while recording?")
    seen = set()
    unique = []
    for index, time in running:
        if time in seen:
            continue
        seen.add(time)
        unique.append((index, time))
    unique.sort(key=lambda item: item[1])
    times = np.array([time for _, time in unique])
    first, last = times[0], times[-1]
    start = max(start if start is not None else 0.0, first)
    end = min(end if end is not None else last, last)
    count = int(np.floor((end - start) * fps + 1e-6)) + 1
    selection = []
    window = shutter / fps
    for k in range(count):
        target = start + k / fps
        if window > 0:
            lo, hi = np.searchsorted(times, target - window / 2), np.searchsorted(times, target + window / 2, side="right")
            picks = [unique[j][0] for j in range(lo, hi)]
        else:
            picks = []
        if not picks:
            nearest = int(np.argmin(np.abs(times - target)))
            picks = [unique[nearest][0]]
        selection.append(picks)
    gaps = np.diff(times)
    return selection, {
        "frames": len(stamps), "running": len(running), "unique": len(unique),
        "span": [float(first), float(last)], "render_fps": float(1 / np.median(gaps)) if len(gaps) else 0,
        "worst_gap_ms": float(gaps.max() * 1000) if len(gaps) else 0, "output_frames": count, "start": float(start),
    }


class Output:
    def __init__(self, out, selection, settings):
        output = settings["output"]
        self.out = out
        self.selection = selection
        self.size = (output["width"], output["height"])
        self.needed = {}
        for k, picks in enumerate(selection):
            for index in picks:
                self.needed.setdefault(index, []).append(k)
        self.first = min(self.needed)
        self.last = max(self.needed)
        self.pending = {}
        self.accum = {}
        self.written = 0
        self.encoder = None
        self.fps = output["fps"]

    def feed(self, index, frame):
        if index < self.first or index > self.last or self.done():
            return
        if self.encoder is None:
            width, height = self.size
            self.encoder = subprocess.Popen(
                [ffmpeg(), "-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                 "-s", f"{width}x{height}", "-r", str(self.fps), "-i", "-",
                 "-c:v", "libx264", "-preset", "fast", "-crf", "6", "-pix_fmt", "yuv444p", "-y", str(self.out)],
                stdin=subprocess.PIPE,
            )
        for k in self.needed.get(index, ()):
            total = self.accum.get(k)
            self.accum[k] = frame.astype(np.float32) if total is None else total + frame
            self.pending[k] = self.pending.get(k, 0) + 1
        while self.written in self.pending and self.pending[self.written] == len(self.selection[self.written]):
            image = self.accum.pop(self.written) / self.pending.pop(self.written)
            self.encoder.stdin.write(np.clip(image + 0.5, 0, 255).astype(np.uint8).tobytes())
            self.written += 1
        if self.done():
            self.close()

    def done(self):
        return self.written >= len(self.selection)

    def close(self):
        if self.encoder:
            self.encoder.stdin.close()
            self.encoder.wait()
            self.encoder = None


def render(path, origin, outputs, settings):
    crop = settings["viewport"]["crop"]
    output = settings["output"]
    width, height = output["width"], output["height"]
    x, y = origin[0] + crop["x"], origin[1] + crop["y"]
    filters = f"crop={crop['w']}:{crop['h']}:{x}:{y},scale={width}:{height}:flags=lanczos"
    last = max(item.last for item in outputs)
    for index, frame in enumerate(read_frames(path, filters, width, height, 3)):
        for item in outputs:
            item.feed(index, frame)
        if index >= last:
            break
    for item in outputs:
        item.close()


def main():
    background()
    parser = argparse.ArgumentParser(description="Trim, retime and crop a take to a 1080p60 clip on the shot clock.")
    parser.add_argument("shot")
    parser.add_argument("--take", default=None)
    parser.add_argument("--shutter", type=float, default=0.0)
    parser.add_argument("--start", type=float, default=None)
    parser.add_argument("--end", type=float, default=None)
    parser.add_argument("--out", default=None)
    parser.add_argument("--split", default=None, help="comma separated shot names; shot id N is the Nth name")
    args = parser.parse_args()

    settings = project()
    code = settings["timecode"]
    take = TAKES / args.shot / f"{args.take}.mkv" if args.take else latest_take(args.shot)
    origin, stamps = scan(take, code)
    if origin is None:
        sys.exit("timecode strip not found")

    jobs = []
    if args.split:
        for index, name in enumerate(args.split.split(","), start=1):
            jobs.append((name.strip(), index))
    else:
        jobs.append((args.shot, None))

    outputs = []
    reports = []
    for name, shot_id in jobs:
        selection, report = plan(stamps, settings["output"]["fps"], args.shutter, args.start, args.end, shot_id)
        out = args.out if (args.out and not args.split) else str(ensure(CLIPS) / f"{name}.mkv")
        outputs.append(Output(out, selection, settings))
        report.update({"shot": name, "take": take.name, "origin": origin, "out": out})
        reports.append(report)
    render(take, origin, outputs, settings)
    for item, report in zip(outputs, reports):
        report["written"] = item.written
        print("  ".join(f"{key}={value}" for key, value in report.items()))


if __name__ == "__main__":
    main()
