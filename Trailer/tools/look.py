import hashlib
import json
from pathlib import Path

import cv2
import numpy as np

DEFAULTS = {
    "exposure": 0.0,
    "contrast": 1.0,
    "pivot": 0.42,
    "saturation": 1.0,
    "lift": 0.0,
    "gamma": 1.0,
    "shadows": [1.0, 1.0, 1.0],
    "highlights": [1.0, 1.0, 1.0],
    "bloom": 0.0,
    "bloom_threshold": 0.7,
    "bloom_tint": [1.0, 0.8, 0.6],
    "halation": 0.0,
    "vignette": 0.0,
    "vignette_power": 2.2,
    "aberration": 0.0,
    "grain": 0.0,
    "grain_size": 1.6,
    "letterbox": 0.0,
    "shoulder": 0.82,
}

LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)
CURVE_SIZE = 4096
CURVE_RANGE = 3.0


def merged(*layers):
    out = dict(DEFAULTS)
    for layer in layers:
        if layer:
            out.update(layer)
    return out


class Look:
    def __init__(self, width, height, backend, seed=3):
        self.width, self.height = width, height
        self.backend = backend
        xp = backend.xp
        ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
        cx, cy = (width - 1) / 2, (height - 1) / 2
        nx, ny = (xs - cx) / cx, (ys - cy) / cy
        self.radius = np.sqrt((nx * nx * (width / height) ** 2 + ny * ny) / ((width / height) ** 2 + 1)).astype(np.float32)
        self.cx, self.cy = cx, cy
        self.curve_cache = {}
        self.vignette_cache = {}
        rng = np.random.default_rng(seed)
        self.grain_bank = []
        for _ in range(24):
            small = rng.standard_normal((height // 2, width // 2)).astype(np.float32)
            self.grain_bank.append(backend.array(cv2.resize(small, (width, height), interpolation=cv2.INTER_CUBIC)))
        self.luma = backend.array(LUMA)
        self.xp = xp

    def _curve(self, p):
        key = (p["contrast"], p["pivot"], p["gamma"], p["lift"], p["shoulder"])
        cached = self.curve_cache.get(key)
        if cached is not None:
            return cached
        x = np.linspace(0, CURVE_RANGE, CURVE_SIZE, dtype=np.float64)
        pivot = p["pivot"]
        y = pivot * (x / pivot) ** p["contrast"] if p["contrast"] != 1 else x.copy()
        if p["gamma"] != 1:
            y = np.maximum(y, 0) ** (1 / p["gamma"])
        y = y * (1 - p["lift"]) + p["lift"]
        knee = p["shoulder"]
        if knee < 1:
            over = np.maximum(y - knee, 0)
            y = np.minimum(y, knee) + (1 - knee) * np.tanh(over / (1 - knee))
        curve = y.astype(np.float32)
        self.curve_cache[key] = curve
        return curve

    def color(self, x, p):
        if p["exposure"]:
            x = x * np.float32(2.0 ** p["exposure"])
        luma = x @ LUMA
        weight = np.clip(luma * np.float32(1 / 0.65), 0, 1)
        weight = (weight * weight * (3 - 2 * weight))[..., None]
        shadows = np.asarray(p["shadows"], np.float32)
        highlights = np.asarray(p["highlights"], np.float32)
        x = x * (shadows + (highlights - shadows) * weight)
        index = np.clip(x * np.float32((CURVE_SIZE - 1) / CURVE_RANGE), 0, CURVE_SIZE - 1).astype(np.int32)
        x = self._curve(p)[index]
        if p["saturation"] != 1:
            luma = (x @ LUMA)[..., None]
            x = luma + (x - luma) * np.float32(p["saturation"])
        return np.clip(x, 0, 1)

    def cube(self, p, folder, size=48):
        if p.get("lut"):
            return Path(p["lut"]).resolve()
        keys = ("exposure", "contrast", "pivot", "saturation", "lift", "gamma", "shadows", "highlights", "shoulder")
        digest = hashlib.sha1(json.dumps([p[key] for key in keys]).encode()).hexdigest()[:12]
        path = Path(folder) / f"grade_{digest}.cube"
        if path.exists():
            return path
        grid = np.linspace(0, 1, size, dtype=np.float32)
        b, g, r = np.meshgrid(grid, grid, grid, indexing="ij")
        samples = np.stack([r, g, b], axis=-1).reshape(-1, 3)
        graded = self.color(samples, p)
        lines = [f"LUT_3D_SIZE {size}"] + [f"{red:.6f} {green:.6f} {blue:.6f}" for red, green, blue in graded]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines) + "\n", encoding="ascii")
        return path

    def spatial(self, x, p):
        backend, xp = self.backend, self.xp
        if p["bloom"] > 0 or p["halation"] > 0:
            small = backend.shrink4(x)
            bright = xp.maximum(small - np.float32(p["bloom_threshold"]), 0)
            wide = backend.blur(bright, 9)
            tight = backend.blur(bright, 2.5)
            glow = (wide * 0.6 + tight * 0.4) * backend.array(np.asarray(p["bloom_tint"], np.float32) * np.float32(p["bloom"]))
            if p["halation"] > 0:
                glow[..., 0] += backend.blur(xp.ascontiguousarray(bright[..., 0]), 5) * np.float32(p["halation"])
            x = x + backend.grow(glow.astype(xp.float32), self.width, self.height)
        if p["aberration"] > 0:
            amount = p["aberration"] / self.width
            red = backend.scale_channel(xp.ascontiguousarray(x[..., 0]), 1 + amount)
            blue = backend.scale_channel(xp.ascontiguousarray(x[..., 2]), 1 - amount)
            x = xp.stack([red, x[..., 1], blue], axis=-1)
        if p["vignette"] > 0:
            x = x * self._vignette(p["vignette"], p["vignette_power"])
        return x

    def _vignette(self, amount, power):
        key = (amount, power)
        mask = self.vignette_cache.get(key)
        if mask is None:
            mask = self.backend.array((1 - amount * np.clip(self.radius, 0, 1.4) ** power)[..., None])
            self.vignette_cache[key] = mask
        return mask

    def grain(self, x, amount, frame_index):
        if amount <= 0:
            return x
        xp = self.xp
        noise = self.grain_bank[(frame_index * 7) % len(self.grain_bank)]
        luma = xp.clip(x @ self.luma, 0, 1)
        strength = luma * (1 - luma) * np.float32(4 * amount * 0.6) + np.float32(amount * 0.4) * xp.minimum(luma * 8, 1)
        x += (noise * strength)[..., None]
        return x

    def shake(self, x, dx, dy, angle, zoom):
        if dx == 0 and dy == 0 and angle == 0 and zoom == 1:
            return x
        return self.backend.transform(x, dx, dy, angle, zoom)

    def letterbox(self, x, amount):
        if amount <= 0:
            return x
        bar = int(self.height * amount / 2)
        x[:bar] = 0
        x[self.height - bar:] = 0
        return x
