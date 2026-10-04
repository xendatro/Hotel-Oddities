import argparse
import math

import numpy as np
import soundfile as sf
from pedalboard import Compressor, Limiter, Pedalboard, Reverb
from scipy import signal

from common import AUDIO, OUT, background, ensure
from overlay import TextItem
from timeline import Edit

RATE = 48000


def load(path):
    data, rate = sf.read(str(path), always_2d=True, dtype="float32")
    if data.shape[1] == 1:
        data = np.repeat(data, 2, axis=1)
    data = data[:, :2]
    if rate != RATE:
        divisor = math.gcd(RATE, rate)
        data = signal.resample_poly(data, RATE // divisor, rate // divisor, axis=0).astype(np.float32)
    return data


def db(value):
    return 10 ** (float(value) / 20)


def variable_speed(audio, rates):
    positions = np.cumsum(rates) - rates[0]
    positions = positions[positions < len(audio) - 1]
    index = np.arange(len(audio))
    return np.stack([np.interp(positions, index, audio[:, channel]) for channel in range(2)], axis=1).astype(np.float32)


def filtered(audio, kind, cutoff, order=2):
    sos = signal.butter(order, cutoff, btype=kind, fs=RATE, output="sos")
    return signal.sosfilt(sos, audio, axis=0).astype(np.float32)


class Cue:
    def __init__(self, data, edit, cache):
        self.data = data
        self.at = edit.time(data["at"])
        self.bus = data.get("bus", "sfx")
        source = cache.get(data["file"])
        if source is None:
            source = load(AUDIO / data["file"])
            cache[data["file"]] = source
        start = int(float(data.get("start", 0)) * RATE)
        audio = source[start:]
        if data.get("loop"):
            needed = int(float(data["length"]) * RATE)
            repeats = needed // max(len(audio), 1) + 1
            audio = np.concatenate([audio] * repeats)
        if "length" in data:
            audio = audio[: int(float(data["length"]) * RATE)]
        if data.get("until") is not None:
            audio = audio[: max(int((edit.time(data["until"]) - self.at) * RATE), 0)]
        audio = audio.copy()
        if data.get("reverse"):
            audio = audio[::-1].copy()
        speed = float(data.get("speed", 1.0))
        stop = data.get("tape_stop")
        if speed != 1.0 or stop:
            rates = np.full(int(len(audio) / speed) + RATE, speed, np.float32)
            if stop:
                stop_at = int((edit.time(stop["at"]) - self.at) * RATE)
                length = int(float(stop.get("length", 0.6)) * RATE)
                if 0 <= stop_at < len(rates):
                    ramp = np.linspace(1, 0, length, dtype=np.float32) ** float(stop.get("curve", 1.6)) * speed
                    rates[stop_at:stop_at + length] = ramp[: len(rates[stop_at:stop_at + length])]
                    rates = rates[: stop_at + length]
            audio = variable_speed(audio, rates)
        if data.get("highpass"):
            audio = filtered(audio, "high", float(data["highpass"]))
        if data.get("lowpass"):
            audio = filtered(audio, "low", float(data["lowpass"]))
        fade_in = int(float(data.get("fade_in", 0.0)) * RATE)
        fade_out = int(float(data.get("fade_out", 0.02)) * RATE)
        if fade_in > 0 and len(audio):
            count = min(fade_in, len(audio))
            audio[:count] *= np.linspace(0, 1, count, dtype=np.float32)[:, None]
        if fade_out > 0 and len(audio):
            count = min(fade_out, len(audio))
            audio[-count:] *= np.linspace(1, 0, count, dtype=np.float32)[:, None]
        pan = float(data.get("pan", 0))
        if pan:
            audio = audio * np.array([min(1, 1 - pan), min(1, 1 + pan)], np.float32)
        audio = audio * db(data.get("gain", 0))
        if data.get("reverb"):
            wet = float(data["reverb"])
            tail = np.zeros((int(float(data.get("reverb_tail", 2.5)) * RATE), 2), np.float32)
            board = Pedalboard([Reverb(room_size=float(data.get("room", 0.85)), damping=0.5, wet_level=wet, dry_level=1 - wet * 0.5, width=1.0)])
            audio = board(np.concatenate([audio, tail]).T.copy(), RATE).T
        self.audio = audio


def repeated(data, edit):
    pattern = data.get("repeat")
    if not pattern:
        return [data]
    start = edit.time(data["at"])
    until = edit.time(pattern["until"])
    first, last = (float(value) for value in pattern["every"])
    gains = pattern.get("gain")
    cues = []
    when = start
    while when < until:
        progress = (when - start) / max(until - start, 1e-6)
        cue = dict(data)
        cue.pop("repeat")
        cue["at"] = when
        if gains:
            cue["gain"] = float(gains[0]) + (float(gains[1]) - float(gains[0])) * progress
        cues.append(cue)
        when += first + (last - first) * progress
    return cues


def typewriter_cues(edit, settings):
    if not settings:
        return []
    cues = []
    spread = float(settings.get("pitch_spread", 0.08))
    rng = np.random.default_rng(5)
    for data in edit.text:
        if data.get("type") != "typewriter" or data.get("ticks") is False:
            continue
        item = TextItem(data, edit, 1.0)
        for index, when in enumerate(item.char_times()):
            if index % int(settings.get("every", 1)):
                continue
            cue = dict(settings)
            cue["at"] = when
            cue["speed"] = 1 + rng.uniform(-spread, spread)
            cue["gain"] = float(settings.get("gain", -12)) + rng.uniform(-1.5, 1.5)
            cue["bus"] = "ui"
            cues.append(cue)
    return cues


def loudness(audio):
    def shelf(x):
        pre = signal.lfilter([1.53512485958697, -2.69169618940638, 1.19839281085285],
                             [1.0, -1.69065929318241, 0.73248077421585], x, axis=0)
        return signal.lfilter([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], pre, axis=0)

    weighted = shelf(audio)
    block, step = int(0.4 * RATE), int(0.1 * RATE)
    powers = []
    for start in range(0, len(weighted) - block, step):
        chunk = weighted[start:start + block]
        powers.append(np.mean(chunk ** 2, axis=0).sum())
    powers = np.array(powers)
    levels = -0.691 + 10 * np.log10(powers + 1e-12)
    gated = powers[levels > -70]
    if not len(gated):
        return -70.0
    relative = -0.691 + 10 * np.log10(gated.mean()) - 10
    final = powers[(levels > -70) & (levels > relative)]
    return -0.691 + 10 * np.log10(final.mean() + 1e-12)


def main():
    background()
    parser = argparse.ArgumentParser(description="Mix the trailer audio described in edit.yaml.")
    parser.add_argument("--no-normalize", action="store_true")
    args = parser.parse_args()

    edit = Edit()
    master_settings = edit.master
    length = int((edit.duration + 3) * RATE)
    buses = {}
    cache = {}
    entries = []
    for data in edit.audio:
        entries.extend(repeated(data, edit))
    entries += typewriter_cues(edit, edit.data.get("typewriter"))
    for data in entries:
        if data.get("mute"):
            continue
        cue = Cue(data, edit, cache)
        start = int(cue.at * RATE)
        bus = buses.setdefault(cue.bus, np.zeros((length, 2), np.float32))
        end = min(start + len(cue.audio), length)
        if end > start >= 0:
            bus[start:end] += cue.audio[: end - start]

    bus_gains = master_settings.get("buses", {})
    mix = np.zeros((length, 2), np.float32)
    stems = ensure(OUT / "audio")
    for name, bus in buses.items():
        bus = bus * db(bus_gains.get(name, 0))
        sf.write(stems / f"stem_{name}.wav", bus, RATE, subtype="FLOAT")
        mix += bus

    mix = mix[: int(edit.duration * RATE)]
    board = Pedalboard([Compressor(threshold_db=float(master_settings.get("compress_db", -14)), ratio=2.0, attack_ms=15, release_ms=180)])
    mix = board(mix.T.copy(), RATE).T
    if not args.no_normalize:
        target = float(master_settings.get("lufs", -14))
        current = loudness(mix)
        mix = mix * db(target - current)
        print(f"loudness {current:.1f} LUFS -> {target:.1f}")
    ceiling = float(master_settings.get("ceiling_db", -1.0))
    mix = Pedalboard([Limiter(threshold_db=ceiling, release_ms=80)])(mix.T.copy(), RATE).T
    mix = np.clip(mix, -db(ceiling), db(ceiling))
    fade = int(0.01 * RATE)
    mix[:fade] *= np.linspace(0, 1, fade)[:, None]
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    sf.write(stems / "master.wav", mix, RATE, subtype="PCM_24")
    print(f"wrote {stems / 'master.wav'} ({len(mix) / RATE:.2f}s, peak {20 * np.log10(np.abs(mix).max() + 1e-9):.1f} dBFS)")


if __name__ == "__main__":
    main()
