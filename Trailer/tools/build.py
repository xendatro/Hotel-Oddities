import os

for variable in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ.setdefault(variable, "1")

import argparse
import math
import multiprocessing
import subprocess
import time as clock
from pathlib import Path

import cv2
import numpy as np

from backend import Backend, HAS_GPU
from common import IDLE, OUT, background, ensure, ffmpeg, nvenc
from look import Look, merged
from overlay import Overlays, smooth
from timeline import Edit


class Reader:
    def __init__(self, segment, fps, size, preroll, cube, begin):
        self.fps = fps
        self.start = max(segment.source_time(max(segment.start - preroll, begin - 0.1)), 0.0)
        self.size = size
        width, height = size
        self.process = subprocess.Popen(
            [ffmpeg(), "-hide_banner", "-loglevel", "fatal", "-ss", f"{self.start:.4f}", "-i", str(segment.path),
             "-vf", f"scale={width}:{height}:flags=lanczos,format=rgb24,lut3d=file={cube.name}:interp=tetrahedral",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
            stdout=subprocess.PIPE, cwd=str(cube.parent), creationflags=IDLE,
        )
        self.index = -1
        self.frame = np.zeros((height, width, 3), np.uint8)

    def get(self, source_time):
        target = int(round((source_time - self.start) * self.fps))
        width, height = self.size
        while self.index < target:
            chunk = self.process.stdout.read(width * height * 3)
            if len(chunk) < width * height * 3:
                break
            self.frame = np.frombuffer(chunk, np.uint8).reshape(height, width, 3)
            self.index += 1
        return self.frame

    def close(self):
        try:
            self.process.stdout.close()
            self.process.kill()
        except OSError:
            pass


def envelope(local, duration, attack=0.02):
    if local < 0 or local > duration:
        return 0.0
    rise = min(local / attack, 1.0) if attack > 0 else 1.0
    return rise * math.exp(-4.0 * local / duration)


class Effects:
    def __init__(self, edit, scale):
        self.items = []
        for data in edit.effects:
            item = dict(data)
            item["start"] = edit.time(data["at"])
            self.items.append(item)
        self.scale = scale

    def apply(self, frame, time, look, frame_index):
        dx = dy = angle = 0.0
        zoom = 1.0
        flash = np.zeros(3, np.float32)
        glitch = 0.0
        for item in self.items:
            local = time - item["start"]
            duration = float(item.get("duration", 0.3))
            kind = item["type"]
            if kind == "shake":
                amount = envelope(local, duration) * float(item.get("strength", 8)) * self.scale
                if amount > 0:
                    freq = float(item.get("frequency", 22))
                    seed = item["start"] * 13.7
                    dx += amount * math.sin(local * freq * 6.283 + seed) * 0.8
                    dy += amount * math.sin(local * freq * 4.913 + seed * 1.7)
                    angle += amount * 0.02 * math.sin(local * freq * 3.7 + seed)
            elif kind == "zoom":
                hold = float(item.get("hold", 0))
                if 0 <= local <= duration + hold:
                    shape = smooth(local / max(float(item.get("attack", 0.08)), 1e-3))
                    if local > hold:
                        shape *= 1 - smooth((local - hold) / max(duration, 1e-3))
                    zoom *= 1 + float(item.get("amount", 0.06)) * shape
            elif kind == "flash":
                amount = envelope(local, duration, 0.005) * float(item.get("strength", 0.8))
                if amount > 0:
                    flash += np.asarray(item.get("color", (1, 1, 1)), np.float32) * amount
            elif kind == "glitch":
                if 0 <= local <= duration:
                    glitch = max(glitch, float(item.get("strength", 1.0)))
        if dx or dy or angle or zoom != 1:
            frame = look.shake(frame, dx, dy, angle, max(zoom, 1.0) + (0.012 if (dx or dy or angle) else 0))
        if glitch > 0:
            frame = self.glitch(frame, glitch, frame_index, look.xp)
        if flash.any():
            frame = frame + look.backend.array(flash)
        return frame

    def glitch(self, frame, strength, frame_index, xp):
        rng = np.random.default_rng(frame_index)
        out = frame.copy()
        shift = int(rng.integers(4, 18) * strength * self.scale)
        out[..., 0] = xp.roll(frame[..., 0], shift, axis=1)
        out[..., 2] = xp.roll(frame[..., 2], -shift, axis=1)
        height = frame.shape[0]
        for _ in range(int(rng.integers(2, 7))):
            y0 = int(rng.integers(0, height - 8))
            band = int(rng.integers(4, max(6, height // 14)))
            offset = int(rng.integers(-60, 60) * strength * self.scale)
            out[y0:y0 + band] = xp.roll(out[y0:y0 + band], offset, axis=1)
        return out


def segment_frame(segment, weight, time, readers, edit, look, size, frame_index):
    width, height = size
    if segment.clip:
        params = merged(edit.grade, segment.grade)
        reader = readers.get(segment.id)
        if reader is None:
            cube = look.cube(params, OUT / "luts")
            reader = Reader(segment, edit.fps, size, max(segment.dissolve, 0.5), cube, time)
            readers[segment.id] = reader
        graded = look.backend.array(reader.get(segment.source_time(time))) * np.float32(1 / 255)
        image = look.spatial(graded, params)
    else:
        image = look.xp.empty((height, width, 3), np.float32)
        image[:] = look.backend.array(np.asarray(segment.color, np.float32) / 255)
    fade = 1.0
    if segment.fade_in > 0:
        fade *= smooth((time - segment.start) / segment.fade_in)
    if segment.fade_out > 0:
        fade *= smooth((segment.end - time) / segment.fade_out)
    return image * (fade * weight)


def intermediate_codec():
    if nvenc():
        return ["-c:v", "hevc_nvenc", "-preset", "p4", "-rc", "constqp", "-qp", "6", "-pix_fmt", "yuv444p"]
    return ["-c:v", "libx264", "-preset", "veryfast", "-crf", "4", "-threads", "2", "-pix_fmt", "yuv444p"]


def frame_size(edit, scale):
    return (int(edit.size[0] * scale) // 2 * 2, int(edit.size[1] * scale) // 2 * 2)


def render_frames(args, frames, out, still=False):
    background()
    cv2.setNumThreads(1)
    edit = Edit()
    scale = args.scale
    size = frame_size(edit, scale)
    backend = Backend(gpu=not args.cpu)
    xp = backend.xp
    look = Look(*size, backend)
    effects = Effects(edit, scale)
    overlays = Overlays(edit, scale, backend)
    readers = {}
    master = merged(edit.grade)
    encoder = None
    if not still:
        encoder = subprocess.Popen(
            [ffmpeg(), "-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
             "-s", f"{size[0]}x{size[1]}", "-r", str(edit.fps), "-i", "-",
             *intermediate_codec(), "-y", str(out)],
            stdin=subprocess.PIPE, creationflags=IDLE,
        )
    dither = np.random.default_rng(11)
    dither_bank = [backend.array(dither.random((size[1], size[0], 1), np.float32) - np.float32(0.5)) for _ in range(4)]
    for frame_index in frames:
        time = frame_index / edit.fps
        image = None
        for segment, weight in edit.active(time):
            layer = segment_frame(segment, weight, time, readers, edit, look, size, frame_index)
            image = layer if image is None else image + layer
        if image is None:
            image = xp.zeros((size[1], size[0], 3), np.float32)
        for segment_id in list(readers):
            segment = edit.by_id[segment_id]
            if time > segment.end + max(segment.dissolve, 0.5):
                readers.pop(segment_id).close()
        image = effects.apply(image, time, look, frame_index)
        image = overlays.draw(image, time)
        image = look.grain(image, master["grain"], frame_index)
        image = look.letterbox(image, master["letterbox"])
        image *= np.float32(255)
        image += dither_bank[frame_index % len(dither_bank)]
        image = backend.host(xp.clip(image, 0, 255).astype(xp.uint8))
        if still:
            ensure(OUT / "stills")
            path = OUT / "stills" / f"{time:06.2f}.png"
            cv2.imwrite(str(path), cv2.cvtColor(image, cv2.COLOR_RGB2BGR))
        else:
            encoder.stdin.write(image.tobytes())
    for reader in readers.values():
        reader.close()
    if encoder:
        encoder.stdin.close()
        encoder.wait()


def render(edit, args):
    start = args.start or 0.0
    end = min(args.end or edit.duration, edit.duration)
    if args.still:
        frames = sorted({int(round(float(value) * edit.fps)) for value in args.still.split(",")})
        render_frames(args, frames, None, still=True)
        print(f"wrote {len(frames)} stills to {OUT / 'stills'}")
        return

    begun = clock.time()
    frames = list(range(int(round(start * edit.fps)), int(round(end * edit.fps))))
    jobs = max(1, min(args.jobs, len(frames) // 30 or 1))
    parts_dir = ensure(OUT / "parts")
    for old in parts_dir.glob("part_*.mkv"):
        old.unlink()
    chunks = [frames[index * len(frames) // jobs:(index + 1) * len(frames) // jobs] for index in range(jobs)]
    workers = []
    for index, chunk in enumerate(chunks):
        part = parts_dir / f"part_{index:02d}.mkv"
        worker = multiprocessing.Process(target=render_frames, args=(args, chunk, part))
        worker.start()
        workers.append((worker, part))
    for worker, _ in workers:
        worker.join()
        if worker.exitcode != 0:
            raise SystemExit(f"render worker failed with {worker.exitcode}")
    print(f"rendered {len(frames)} frames with {jobs} workers in {clock.time() - begun:.1f}s")

    listing = parts_dir / "parts.txt"
    listing.write_text("".join(f"file '{part.name}'\n" for _, part in workers), encoding="utf-8")
    out = args.out or (str(edit.output) if not args.preview else str(ensure(OUT) / "preview.mp4"))
    command = [ffmpeg(), "-hide_banner", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(listing)]
    audio = OUT / "audio" / "master.wav"
    if audio.exists() and not args.no_audio:
        command += ["-ss", f"{start:.4f}", "-i", str(audio), "-map", "0:v", "-map", "1:a",
                    "-c:a", "aac", "-b:a", "320k", "-shortest"]
    if (args.preview or args.draft) and nvenc():
        command += ["-c:v", "h264_nvenc", "-preset", "p6", "-tune", "hq", "-rc", "vbr", "-cq", "17", "-b:v", "0", "-profile:v", "high"]
    elif args.preview:
        command += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-threads", "4"]
    else:
        command += ["-c:v", "libx264", "-preset", "slow", "-crf", "13", "-tune", "film", "-x264-params", "aq-mode=3", "-threads", "8"]
    command += ["-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709",
                "-color_trc", "bt709", "-r", str(edit.fps), "-movflags", "+faststart", "-y", out]
    ensure(Path(out).parent)
    subprocess.run(command, check=True, creationflags=IDLE)
    print(f"wrote {out} in {clock.time() - begun:.1f}s")


def main():
    background()
    parser = argparse.ArgumentParser(description="Render the trailer described by edit.yaml.")
    parser.add_argument("--preview", action="store_true", help="half resolution, fast encode, out/preview.mp4")
    parser.add_argument("--scale", type=float, default=None)
    parser.add_argument("--start", type=float, default=None)
    parser.add_argument("--end", type=float, default=None)
    parser.add_argument("--still", default=None, help="comma separated seconds; writes PNGs to out/stills")
    parser.add_argument("--no-audio", action="store_true")
    parser.add_argument("--out", default=None)
    parser.add_argument("--jobs", type=int, default=None, help="parallel render workers; all run at idle priority")
    parser.add_argument("--cpu", action="store_true", help="composite on the CPU even when a CUDA GPU is available")
    parser.add_argument("--draft", action="store_true", help="full resolution, but a fast GPU encode for review")
    args = parser.parse_args()
    if args.jobs is None:
        args.jobs = 2 if (HAS_GPU and not args.cpu) else 4
    if args.scale is None:
        args.scale = 0.5 if args.preview else 1.0
    edit = Edit()
    print(f"timeline {edit.duration:.2f}s, {len(edit.segments)} segments, compositing on {'cpu' if args.cpu or not HAS_GPU else 'gpu'} with {args.jobs} workers")
    render(edit, args)


if __name__ == "__main__":
    main()
