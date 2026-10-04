import math

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from common import ROOT


def smooth(alpha):
    alpha = min(max(alpha, 0.0), 1.0)
    return alpha * alpha * (3 - 2 * alpha)


def opacity_at(time, start, end, fade_in, fade_out, flicker):
    if time < start or time >= end:
        return 0.0
    value = 1.0
    if fade_in > 0:
        value *= smooth((time - start) / fade_in)
    if fade_out > 0:
        value *= smooth((end - time) / fade_out)
    if flicker > 0 and time - start < flicker:
        phase = (time - start) / flicker
        step = math.floor(time * 30)
        noise = (math.sin(step * 12.9898) * 43758.5453) % 1.0
        value *= 1.0 if noise > 0.85 * (1 - phase) else 0.1
    return value


class TextItem:
    def __init__(self, data, edit, scale, backend=None):
        self.data = data
        self.backend = backend
        self.text = data["text"]
        self.start = edit.time(data["at"])
        self.end = edit.time(data["until"])
        self.kind = data.get("type", "fade")
        self.cps = float(data.get("cps", 18))
        self.caret = data.get("caret", self.kind == "typewriter")
        self.fade_in = float(data.get("fade_in", 0.0 if self.kind == "typewriter" else 0.4))
        self.fade_out = float(data.get("fade_out", 0.35))
        self.flicker = float(data.get("flicker", 0))
        self.color = np.asarray(data.get("color", (238, 231, 214)), np.float32) / 255
        self.glow_color = np.asarray(data.get("glow_color", data.get("color", (238, 231, 214))), np.float32) / 255
        self.glow = float(data.get("glow", 0.35))
        self.glow_radius = float(data.get("glow_radius", 10)) * scale
        self.size = int(round(float(data.get("size", 44)) * scale))
        self.tracking = float(data.get("tracking", 0.0)) * self.size
        self.pos = data.get("pos", (0.5, 0.85))
        self.rule = data.get("rule")
        self.scale = scale
        self.font = ImageFont.truetype(str(ROOT / data.get("font", "fonts/SpecialElite-Regular.ttf")), self.size)
        self.cache = {}
        self.layout()

    def layout(self):
        advances = []
        for char in self.text:
            advances.append(self.font.getlength(char) + self.tracking)
        width = sum(advances) - self.tracking
        ascent, descent = self.font.getmetrics()
        self.advances = advances
        self.text_width = width
        self.text_height = ascent + descent
        caret_width = self.font.getlength("_")
        pad = int(self.glow_radius * 3) + 4
        self.pad = pad
        self.box = (int(width + caret_width + self.tracking) + pad * 2, self.text_height + pad * 2)

    def visible_chars(self, time):
        if self.kind != "typewriter":
            return len(self.text)
        return max(0, min(len(self.text), int((time - self.start) * self.cps)))

    def char_times(self):
        if self.kind != "typewriter":
            return []
        times = []
        for index, char in enumerate(self.text):
            if char.strip():
                times.append(self.start + index / self.cps)
        return times

    def render(self, count, caret):
        key = (count, caret)
        cached = self.cache.get(key)
        if cached is not None:
            return cached
        width, height = self.box
        canvas = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(canvas)
        x = self.pad
        for index, char in enumerate(self.text[:count]):
            draw.text((x, self.pad), char, font=self.font, fill=255)
            x += self.advances[index]
        if caret:
            draw.text((x, self.pad), "_", font=self.font, fill=255)
        alpha = np.asarray(canvas, np.float32) / 255
        glow = cv2.GaussianBlur(alpha, (0, 0), max(self.glow_radius, 0.5)) * self.glow if self.glow > 0 else None
        if self.backend:
            alpha = self.backend.array(alpha)
            glow = self.backend.array(glow) if glow is not None else None
        self.cache[key] = (alpha, glow)
        return alpha, glow

    def opacity(self, time):
        return opacity_at(time, self.start, self.end, self.fade_in, self.fade_out, self.flicker)

    def draw(self, frame, time):
        alpha_value = self.opacity(time)
        if alpha_value <= 0:
            return frame
        count = self.visible_chars(time)
        typing = self.kind == "typewriter" and count < len(self.text)
        caret = bool(self.caret) and (typing or (int((time - self.start) / 0.45) % 2 == 0))
        if count == 0 and not caret:
            return frame
        alpha, glow = self.render(count, caret)
        height, width = frame.shape[:2]
        box_w, box_h = self.box
        cx = self.pos[0] * width
        cy = self.pos[1] * height
        left = int(round(cx - (self.text_width / 2) - self.pad))
        top = int(round(cy - self.text_height / 2 - self.pad))
        frame = composite(frame, alpha * alpha_value, self.device(self.color), left, top)
        if glow is not None:
            frame = add(frame, glow * alpha_value, self.device(self.glow_color), left, top)
        if self.rule:
            frame = self.draw_rule(frame, time, alpha_value, cx, cy)
        return frame

    def draw_rule(self, frame, time, alpha_value, cx, cy):
        rule = self.rule
        grow_at = self.start + float(rule.get("delay", 0.6))
        grow = smooth((time - grow_at) / float(rule.get("grow", 0.9)))
        if grow <= 0:
            return frame
        width = float(rule.get("width", 420)) * self.scale * grow
        thickness = max(1, int(round(float(rule.get("thickness", 2)) * self.scale)))
        offset = float(rule.get("offset", 0.75)) * self.size
        y = int(round(cy + offset))
        x0, x1 = int(round(cx - width / 2)), int(round(cx + width / 2))
        if x1 <= x0:
            return frame
        span = np.linspace(-1, 1, x1 - x0, dtype=np.float32)
        taper = (1 - np.abs(span) ** 3)
        strip = np.repeat(taper[None, :], thickness, axis=0) * alpha_value * float(rule.get("opacity", 0.8))
        return composite(frame, self.device(strip), self.device(self.color), x0, y)

    def device(self, value):
        return self.backend.array(value) if self.backend else value


def region(frame, mask, left, top):
    height, width = frame.shape[:2]
    mh, mw = mask.shape
    x0, y0 = max(left, 0), max(top, 0)
    x1, y1 = min(left + mw, width), min(top + mh, height)
    if x1 <= x0 or y1 <= y0:
        return None
    return (slice(y0, y1), slice(x0, x1)), mask[y0 - top:y1 - top, x0 - left:x1 - left]


def composite(frame, mask, color, left, top):
    found = region(frame, mask, left, top)
    if not found:
        return frame
    (rows, cols), cut = found
    a = cut[..., None]
    frame[rows, cols] = frame[rows, cols] * (1 - a) + color * a
    return frame


def add(frame, mask, color, left, top):
    found = region(frame, mask, left, top)
    if not found:
        return frame
    (rows, cols), cut = found
    frame[rows, cols] = frame[rows, cols] + color * cut[..., None]
    return frame


class ImageItem:
    def __init__(self, data, edit, scale, backend=None):
        self.backend = backend
        self.start = edit.time(data["at"])
        self.end = edit.time(data["until"])
        self.fade_in = float(data.get("fade_in", 0.6))
        self.fade_out = float(data.get("fade_out", 0.4))
        self.flicker = float(data.get("flicker", 0))
        self.pos = data.get("pos", (0.5, 0.5))
        self.width = float(data.get("width", 0.8))
        self.grow = data.get("grow", [1.0, 1.0])
        self.brightness = float(data.get("brightness", 1.0))
        rgba = cv2.cvtColor(cv2.imread(str(ROOT / data["file"]), cv2.IMREAD_UNCHANGED), cv2.COLOR_BGRA2RGBA)
        rgba = rgba.astype(np.float32) / 255
        rgba[..., :3] *= rgba[..., 3:4]
        self.source = rgba
        self.scale = scale

    def opacity(self, time):
        return opacity_at(time, self.start, self.end, self.fade_in, self.fade_out, self.flicker)

    def draw(self, frame, time):
        alpha_value = self.opacity(time)
        if alpha_value <= 0:
            return frame
        height, width = frame.shape[:2]
        progress = smooth((time - self.start) / max(self.end - self.start, 1e-3))
        grow = self.grow[0] + (self.grow[1] - self.grow[0]) * progress
        target_w = max(2, int(width * self.width * grow))
        target_h = max(2, int(target_w * self.source.shape[0] / self.source.shape[1]))
        image = cv2.resize(self.source, (target_w, target_h), interpolation=cv2.INTER_AREA)
        left = int(round(self.pos[0] * width - target_w / 2))
        top = int(round(self.pos[1] * height - target_h / 2))
        found = region(frame, image[..., 3], left, top)
        if not found:
            return frame
        (rows, cols), _ = found
        cut = image[rows.start - top:rows.stop - top, cols.start - left:cols.stop - left]
        if self.backend:
            cut = self.backend.array(cut)
        a = cut[..., 3:4] * alpha_value
        frame[rows, cols] = frame[rows, cols] * (1 - a) + cut[..., :3] * alpha_value * self.brightness
        return frame


class Overlays:
    def __init__(self, edit, scale=1.0, backend=None):
        self.items = []
        for data in edit.text:
            if data.get("type") == "image":
                self.items.append(ImageItem(data, edit, scale, backend))
            else:
                self.items.append(TextItem(data, edit, scale, backend))

    def draw(self, frame, time):
        for item in self.items:
            frame = item.draw(frame, time)
        return frame
