import argparse

import numpy as np
import soundfile as sf
from pedalboard import Compressor, Distortion, HighpassFilter, LowpassFilter, Pedalboard, Reverb
from scipy import signal

from common import AUDIO, ensure

RATE = 48000
rng = np.random.default_rng(7)


def timeline(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def stereo(mono, width=0.0, delay=0.0):
    left = mono
    right = mono
    if delay > 0:
        shift = int(delay * RATE)
        right = np.concatenate([np.zeros(shift), mono[:-shift]]) if shift else mono
    mid = (left + right) / 2
    side = (left - right) / 2 * (1 + width)
    return np.stack([mid + side, mid - side], axis=1)


def noise(seconds):
    return rng.standard_normal(int(seconds * RATE))


def pink(seconds):
    white = noise(seconds)
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, white) * 6


def env_exp(t, attack, decay):
    rise = np.clip(t / max(attack, 1e-4), 0, 1)
    return rise * np.exp(-np.maximum(t - attack, 0) / decay)


def sweep(t, start, end, curve="exp"):
    length = t[-1] if len(t) else 1
    alpha = t / length
    if curve == "exp":
        freq = start * (end / start) ** alpha
    else:
        freq = start + (end - start) * alpha
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    return np.sin(phase), freq


def saw(freq, t, detune=0.0):
    phase = (freq * (1 + detune) * t) % 1.0
    return 2 * phase - 1


def bandpass(x, low, high, order=2):
    sos = signal.butter(order, [low, high], btype="band", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, cutoff, order=2):
    sos = signal.butter(order, cutoff, btype="low", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, cutoff, order=2):
    sos = signal.butter(order, cutoff, btype="high", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def board(audio, *effects):
    return Pedalboard(list(effects))(audio.astype(np.float32).T.copy(), RATE).T


def normalize(audio, peak=0.89):
    top = np.max(np.abs(audio)) or 1
    return audio / top * peak


def tail(audio, seconds):
    return np.concatenate([audio, np.zeros((int(seconds * RATE), audio.shape[1]))])


def braam(seconds=5.0, root=43.65):
    t = timeline(seconds)
    voices = np.zeros_like(t)
    for ratio, gain in ((1, 1.0), (2, 0.55), (1.5, 0.35), (1.0 / 2, 0.6), (3, 0.18)):
        for detune in (-0.006, 0.0, 0.007):
            voices += saw(root * ratio, t, detune) * gain
    body = env_exp(t, 0.05, 1.6)
    swell = np.clip(t / 0.06, 0, 1)
    cutoff = 180 + 2600 * np.exp(-t / 0.35)
    filtered = np.zeros_like(voices)
    block = 512
    for start in range(0, len(t), block):
        stop = min(start + block, len(t))
        sos = signal.butter(2, cutoff[start], btype="low", fs=RATE, output="sos")
        filtered[start:stop] = signal.sosfilt(sos, voices[start:stop])
    sub, _ = sweep(t, root * 1.5, root * 0.75)
    out = filtered * body * swell + sub * env_exp(t, 0.02, 1.2) * 1.4
    out = stereo(out, width=0.4, delay=0.012)
    out = board(out, Distortion(drive_db=12), LowpassFilter(cutoff_frequency_hz=5200),
                Reverb(room_size=0.92, damping=0.55, wet_level=0.38, dry_level=0.8, width=1.0))
    return normalize(tail(out, 1.5))


def impact(seconds=4.0):
    t = timeline(seconds)
    sub, _ = sweep(t, 90, 26)
    sub *= env_exp(t, 0.004, 0.9) * 1.6
    crack = highpass(noise(seconds), 900) * env_exp(t, 0.0005, 0.045) * 0.9
    thump = lowpass(noise(seconds), 260) * env_exp(t, 0.001, 0.18) * 1.6
    metal = np.zeros_like(t)
    for partial, gain in ((211, 1), (387, 0.7), (562, 0.55), (911, 0.4), (1433, 0.3), (2171, 0.2)):
        metal += np.sin(2 * np.pi * partial * t + rng.uniform(0, 6.28)) * gain
    metal *= env_exp(t, 0.002, 0.55) * 0.35
    out = stereo(sub + crack + thump + metal, width=0.5, delay=0.009)
    out = board(out, Distortion(drive_db=9), Compressor(threshold_db=-12, ratio=4, attack_ms=2, release_ms=120),
                Reverb(room_size=0.95, damping=0.4, wet_level=0.42, dry_level=0.85, width=1.0))
    return normalize(tail(out, 1.0))


def sub_drop(seconds=2.6):
    t = timeline(seconds)
    tone, _ = sweep(t, 95, 24)
    out = tone * env_exp(t, 0.01, 1.1)
    out = stereo(out)
    out = board(out, Distortion(drive_db=6), LowpassFilter(cutoff_frequency_hz=400))
    return normalize(out, 0.95)


def whoosh(seconds=1.3, rise=0.75):
    t = timeline(seconds)
    raw = pink(seconds)
    centre = 300 * (12 ** np.sin(np.clip(t / seconds, 0, 1) * np.pi) )
    out = np.zeros_like(t)
    block = 256
    for start in range(0, len(t), block):
        stop = min(start + block, len(t))
        low = max(centre[start] * 0.6, 40)
        high = min(centre[start] * 1.6, RATE / 2 - 100)
        sos = signal.butter(2, [low, high], btype="band", fs=RATE, output="sos")
        out[start:stop] = signal.sosfilt(sos, raw[start:stop])
    shape = np.sin(np.clip(t / seconds, 0, 1) * np.pi) ** 2
    peak = np.exp(-((t - rise) ** 2) / 0.04)
    out *= shape * 0.6 + peak * 0.8
    pan = np.clip(t / seconds, 0, 1)
    stereo_out = np.stack([out * (1 - pan * 0.7), out * (0.3 + pan * 0.7)], axis=1)
    stereo_out = board(stereo_out, Reverb(room_size=0.6, wet_level=0.2, dry_level=0.9))
    return normalize(stereo_out, 0.8)


def riser(seconds=6.0):
    t = timeline(seconds)
    alpha = t / seconds
    tone = np.zeros_like(t)
    for octave in (0.5, 1, 2, 4):
        wave, _ = sweep(t, 110 * octave, 440 * octave)
        weight = np.exp(-((np.log2(octave) - 1 - alpha * 1.2) ** 2) / 1.2)
        tone += wave * weight
    air = highpass(pink(seconds), 2000) * alpha ** 2 * 0.5
    trem = 1 - 0.5 * (0.5 + 0.5 * np.sin(2 * np.pi * (2 + 14 * alpha ** 2) * t))
    out = (tone * 0.5 * trem + air) * alpha ** 2.5
    out = stereo(out, width=0.6, delay=0.007)
    out = board(out, Reverb(room_size=0.8, wet_level=0.35, dry_level=0.8))
    return normalize(out, 0.85)


def reverse_swell(seconds=2.4):
    hit = impact(seconds + 1.0)
    swell = hit[::-1]
    start = len(swell) - int(seconds * RATE)
    swell = swell[start:]
    fade = np.linspace(0, 1, len(swell)) ** 1.5
    return normalize(swell * fade[:, None], 0.85)


def strings_stab(seconds=3.0):
    t = timeline(seconds)
    out = np.zeros_like(t)
    for freq in (622.25, 659.26, 698.46, 932.33, 987.77, 1318.5):
        vibrato = 1 + 0.006 * np.sin(2 * np.pi * (5.5 + rng.uniform(-0.5, 0.5)) * t)
        phase = 2 * np.pi * np.cumsum(freq * vibrato) / RATE
        out += (2 * ((phase / (2 * np.pi)) % 1) - 1) * rng.uniform(0.6, 1.0)
    bow = highpass(noise(seconds), 3000) * 0.08
    out = (out * 0.25 + bow) * env_exp(t, 0.015, 1.1)
    out = stereo(out, width=0.8, delay=0.011)
    out = board(out, HighpassFilter(cutoff_frequency_hz=380), LowpassFilter(cutoff_frequency_hz=7000),
                Reverb(room_size=0.9, damping=0.5, wet_level=0.45, dry_level=0.7, width=1.0))
    return normalize(out, 0.8)


def tinnitus(seconds=4.0):
    t = timeline(seconds)
    out = np.sin(2 * np.pi * 5600 * t) * 0.3 + np.sin(2 * np.pi * 5640 * t) * 0.15
    out *= np.clip(t / 0.05, 0, 1) * np.exp(-t / 1.6)
    return normalize(stereo(out), 0.5)


def drone(seconds=32.0, root=36.71):
    t = timeline(seconds)
    voices = np.zeros_like(t)
    for ratio, gain in ((1, 1), (2, 0.5), (1.4983, 0.35), (2.3784, 0.18), (0.5, 0.7)):
        for detune in (-0.004, 0.003):
            voices += saw(root * ratio, t, detune) * gain
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t)
    out = np.zeros_like(t)
    block = 1024
    for start in range(0, len(t), block):
        stop = min(start + block, len(t))
        sos = signal.butter(2, 120 + 380 * lfo[start], btype="low", fs=RATE, output="sos")
        out[start:stop] = signal.sosfilt(sos, voices[start:stop])
    air = bandpass(pink(seconds), 1500, 6000) * 0.05 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t))
    out = out * 0.4 + air
    fade = np.clip(t / 3, 0, 1) * np.clip((seconds - t) / 3, 0, 1)
    out = stereo(out * fade, width=0.7, delay=0.015)
    out = board(out, Reverb(room_size=0.95, damping=0.6, wet_level=0.5, dry_level=0.6, width=1.0))
    return normalize(out, 0.7)


def pulse(seconds=1.2, freq=52):
    t = timeline(seconds)
    tone = np.sin(2 * np.pi * freq * t) * env_exp(t, 0.003, 0.22)
    click = lowpass(noise(seconds), 900) * env_exp(t, 0.0005, 0.02) * 0.6
    out = stereo(tone + click)
    out = board(out, Distortion(drive_db=8), LowpassFilter(cutoff_frequency_hz=900))
    return normalize(out, 0.9)


def glitch(seconds=0.5):
    t = timeline(seconds)
    out = np.zeros_like(t)
    position = 0
    while position < len(t):
        length = int(rng.uniform(0.01, 0.05) * RATE)
        freq = rng.choice([90, 180, 1200, 2400, 3700])
        segment = np.sign(np.sin(2 * np.pi * freq * t[:length])) * rng.uniform(0.2, 0.7)
        if rng.random() < 0.35:
            segment = noise(length / RATE) * 0.4
        out[position:position + length] = segment[: len(out[position:position + length])]
        position += length + int(rng.uniform(0, 0.02) * RATE)
    out = np.round(out * 6) / 6
    return normalize(stereo(out, width=0.3), 0.6)


def crackle(seconds=14.0):
    t = timeline(seconds)
    hiss = bandpass(noise(seconds), 2500, 9000) * 0.035
    rumble = lowpass(noise(seconds), 60) * 0.25
    clicks = np.zeros_like(t)
    count = int(seconds * 28)
    for position in rng.integers(0, len(t) - 400, count):
        width = int(rng.integers(8, 120))
        clicks[position:position + width] += rng.standard_normal(width) * np.exp(-np.arange(width) / (width / 4)) * rng.uniform(0.1, 0.9)
    clicks = highpass(clicks, 900) * 0.5
    wobble = 1 + 0.15 * np.sin(2 * np.pi * 0.55 * t)
    out = stereo((hiss + clicks) * wobble + rumble, width=0.2)
    return normalize(out, 0.6)


SOUNDS = {
    "crackle": crackle,
    "braam": braam,
    "impact": impact,
    "sub_drop": sub_drop,
    "whoosh": whoosh,
    "riser": riser,
    "reverse_swell": reverse_swell,
    "strings_stab": strings_stab,
    "tinnitus": tinnitus,
    "drone": drone,
    "pulse": pulse,
    "glitch": glitch,
}


def main():
    parser = argparse.ArgumentParser(description="Synthesize the trailer's sound design into audio/gen.")
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()
    out = ensure(AUDIO / "gen")
    for name in args.names or SOUNDS:
        audio = SOUNDS[name]()
        sf.write(out / f"{name}.wav", audio.astype(np.float32), RATE, subtype="FLOAT")
        print(f"{name}.wav {len(audio) / RATE:.2f}s")


if __name__ == "__main__":
    main()
