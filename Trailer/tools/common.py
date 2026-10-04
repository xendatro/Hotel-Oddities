import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
TAKES = ROOT / "takes"
CLIPS = ROOT / "clips"
AUDIO = ROOT / "audio"
OUT = ROOT / "out"


def load_yaml(name):
    with open(ROOT / name, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def project():
    return load_yaml("project.yaml")


def tool(name):
    configured = project().get(name)
    if configured:
        path = Path(os.path.expandvars(configured))
        if path.exists():
            return str(path)
    return name


def ffmpeg():
    return tool("ffmpeg")


def ffprobe():
    return tool("ffprobe")


def probe(path):
    result = subprocess.run(
        [ffprobe(), "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,r_frame_rate,avg_frame_rate:format=duration", "-of", "json", str(path)],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def frame_times(path):
    result = subprocess.run(
        [ffprobe(), "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    )
    return [float(line.strip().strip(",")) for line in result.stdout.splitlines() if line.strip().strip(",")]


def ensure(path):
    Path(path).mkdir(parents=True, exist_ok=True)
    return Path(path)


IDLE = 0x00000040 if sys.platform == "win32" else 0


def background():
    if sys.platform == "win32":
        import ctypes
        ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), IDLE)
    else:
        os.nice(10)


_nvenc = None


def nvenc():
    global _nvenc
    if _nvenc is None:
        result = subprocess.run(
            [ffmpeg(), "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=black:s=256x256:d=0.1",
             "-c:v", "hevc_nvenc", "-f", "null", "-"],
            capture_output=True,
        )
        _nvenc = result.returncode == 0
    return _nvenc
