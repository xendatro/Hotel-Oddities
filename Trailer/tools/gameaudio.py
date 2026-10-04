import argparse
import os
import shutil
import subprocess
from pathlib import Path

import yaml

from common import AUDIO, ensure, ffprobe

CACHE = Path(os.path.expandvars(r"%LOCALAPPDATA%\Roblox\rbx-storage"))


def bodies():
    for folder, _, files in os.walk(CACHE):
        for name in files:
            path = Path(folder) / name
            try:
                data = path.read_bytes()
            except OSError:
                continue
            if not data.startswith(b"RBXH"):
                continue
            head = data[:8192]
            for magic, kind in ((b"OggS", "ogg"), (b"ID3", "mp3")):
                offset = head.find(magic)
                if offset >= 0:
                    yield name, kind, data[offset:]
                    break


def duration(path):
    result = subprocess.run(
        [ffprobe(), "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(result.stdout.strip())
    except ValueError:
        return -1.0


def main():
    parser = argparse.ArgumentParser(description="Copy the game's sounds out of Studio's asset cache by matching their lengths.")
    parser.add_argument("--tolerance", type=float, default=0.012)
    args = parser.parse_args()

    wanted = yaml.safe_load(open(AUDIO / "game_sounds.yaml", encoding="utf-8"))
    scratch = ensure(AUDIO / "cache")
    found = []
    for name, kind, body in bodies():
        path = scratch / f"{name}.{kind}"
        if not path.exists():
            path.write_bytes(body)
        found.append((duration(path), path))

    out = ensure(AUDIO / "game")
    missing = []
    for name, entry in wanted.items():
        length = float(entry["length"])
        best = min(found, key=lambda item: abs(item[0] - length), default=None)
        if not best or abs(best[0] - length) > args.tolerance:
            missing.append(name)
            continue
        target = out / f"{name}{best[1].suffix}"
        shutil.copyfile(best[1], target)
        print(f"{name:24s} {length:9.4f} <- {best[1].name} ({best[0]:.4f})")
    shutil.rmtree(scratch, ignore_errors=True)
    if missing:
        print("not in cache (play them once in Studio, then rerun):", ", ".join(missing))


if __name__ == "__main__":
    main()
