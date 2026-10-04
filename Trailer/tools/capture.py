import argparse
import subprocess
import sys
import time

from common import TAKES, ensure, ffmpeg, project


def main():
    parser = argparse.ArgumentParser(description="Record one take of a shot from the Studio monitor.")
    parser.add_argument("shot")
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--take", default=None)
    args = parser.parse_args()

    settings = project()["capture"]
    region = settings["region"]
    take = args.take or time.strftime("%Y%m%d-%H%M%S")
    folder = ensure(TAKES / args.shot)
    out = folder / f"{take}.mkv"

    source = (
        f"ddagrab=output_idx={settings['output_idx']}:framerate={settings['max_fps']}:draw_mouse=0:dup_frames=0"
        f":offset_x={region['x']}:offset_y={region['y']}:video_size={region['w']}x{region['h']}"
    )
    command = [
        ffmpeg(), "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", source, "-t", str(args.seconds),
        *settings["encoder"], "-fps_mode", "passthrough", "-y", str(out),
    ]
    started = time.time()
    result = subprocess.run(command)
    if result.returncode != 0:
        sys.exit(result.returncode)
    print(f"{out} ({time.time() - started:.1f}s)")


if __name__ == "__main__":
    main()
