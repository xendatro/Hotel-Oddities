import argparse
import subprocess
from pathlib import Path

from common import CLIPS, OUT, ensure, ffmpeg, probe


def main():
    parser = argparse.ArgumentParser(description="Tile evenly spaced frames of a clip into one image.")
    parser.add_argument("clip")
    parser.add_argument("--count", type=int, default=12)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--width", type=int, default=480)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    path = Path(args.clip)
    if not path.exists():
        path = CLIPS / f"{args.clip}.mkv"
    info = probe(path)
    duration = float(info["format"]["duration"])
    rows = (args.count + args.columns - 1) // args.columns
    step = duration / args.count
    out = args.out or str(ensure(OUT / "sheets") / f"{path.stem}.png")
    subprocess.run(
        [ffmpeg(), "-hide_banner", "-loglevel", "error", "-i", str(path),
         "-vf", f"select='isnan(prev_selected_t)+gte(t-prev_selected_t\,{step:.4f})',scale={args.width}:-1,"
                f"drawtext=text='%{{pts\:hms}}':x=8:y=8:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.5,"
                f"tile={args.columns}x{rows}",
         "-fps_mode", "passthrough", "-frames:v", "1", "-update", "1", "-y", out],
        check=True,
    )
    print(out)


if __name__ == "__main__":
    main()
