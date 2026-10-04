import argparse

import numpy as np
import soundfile as sf
from scipy import signal

from common import OUT
from timeline import Edit


def k_weight(audio, rate):
    if rate != 48000:
        raise SystemExit("meter expects 48 kHz audio")
    stage = signal.lfilter([1.53512485958697, -2.69169618940638, 1.19839281085285],
                           [1.0, -1.69065929318241, 0.73248077421585], audio, axis=0)
    return signal.lfilter([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], stage, axis=0)


def level(chunk):
    power = np.mean(chunk ** 2, axis=0).sum()
    return -0.691 + 10 * np.log10(power + 1e-12)


def main():
    parser = argparse.ArgumentParser(description="Loudness of the trailer mix per timeline section.")
    parser.add_argument("--file", default=str(OUT / "audio" / "master.wav"))
    args = parser.parse_args()

    audio, rate = sf.read(args.file, always_2d=True)
    weighted = k_weight(audio, rate)
    edit = Edit()
    print(f"{'section':10s} {'start':>6s} {'mean LUFS':>10s} {'loudest 400ms':>14s} {'peak dBFS':>10s}")
    for segment in edit.segments:
        start, end = int(segment.start * rate), int(segment.end * rate)
        chunk = weighted[start:end]
        if len(chunk) == 0:
            continue
        window = int(0.4 * rate)
        loudest = max(level(chunk[i:i + window]) for i in range(0, max(len(chunk) - window, 1), int(0.1 * rate)))
        peak = 20 * np.log10(np.abs(audio[start:end]).max() + 1e-12)
        print(f"{segment.id:10s} {segment.start:6.2f} {level(chunk):10.1f} {loudest:14.1f} {peak:10.1f}")


if __name__ == "__main__":
    main()
