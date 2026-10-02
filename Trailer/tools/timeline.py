import re

from common import CLIPS, ROOT, load_yaml

EXPRESSION = re.compile(r"^\s*([A-Za-z_][\w]*)(\.end)?((?:\s*[+-]\s*[\d.]+)*)\s*$")
TERM = re.compile(r"([+-])\s*([\d.]+)")


class Segment:
    def __init__(self, data, start):
        self.id = data.get("id") or data.get("clip") or f"black{start:.2f}"
        self.clip = data.get("clip")
        self.black = data.get("black")
        self.start = start
        if self.clip:
            self.source_in = float(data.get("in", 0))
            if "out" in data:
                self.duration = (float(data["out"]) - self.source_in) / float(data.get("speed", 1))
            else:
                self.duration = float(data["duration"])
        else:
            self.source_in = 0.0
            self.duration = float(self.black)
        self.end = start + self.duration
        self.speed = float(data.get("speed", 1))
        self.fade_in = float(data.get("fade_in", 0))
        self.fade_out = float(data.get("fade_out", 0))
        self.dissolve = float(data.get("dissolve", 0))
        self.grade = data.get("grade", {}) or {}
        self.color = tuple(data.get("color", (0, 0, 0)))

    @property
    def path(self):
        return CLIPS / f"{self.clip}.mkv"

    def source_time(self, time):
        return self.source_in + (time - self.start) * self.speed


class Edit:
    def __init__(self, name="edit.yaml"):
        self.data = load_yaml(name)
        self.fps = int(self.data.get("fps", 60))
        self.size = tuple(self.data.get("size", (1920, 1080)))
        self.output = ROOT / self.data.get("output", "out/trailer.mp4")
        self.grade = self.data.get("grade", {}) or {}
        self.segments = []
        cursor = 0.0
        for entry in self.data["timeline"]:
            segment = Segment(entry, cursor)
            self.segments.append(segment)
            cursor = segment.end
        self.duration = cursor
        self.by_id = {segment.id: segment for segment in self.segments}
        self.effects = self.data.get("effects", []) or []
        self.text = self.data.get("text", []) or []
        self.audio = self.data.get("audio", []) or []
        self.master = self.data.get("master", {}) or {}

    def time(self, value):
        if isinstance(value, (int, float)):
            return float(value)
        match = EXPRESSION.match(str(value))
        if not match:
            raise ValueError(f"bad time expression {value!r}")
        name, end, terms = match.groups()
        segment = self.by_id.get(name)
        if segment is None:
            raise ValueError(f"no timeline entry with id {name!r} (in {value!r})")
        result = segment.end if end else segment.start
        for sign, amount in TERM.findall(terms or ""):
            result += float(amount) if sign == "+" else -float(amount)
        return result

    def active(self, time):
        found = []
        for index, segment in enumerate(self.segments):
            if segment.start <= time < segment.end:
                found.append((segment, 1.0))
                following = self.segments[index + 1] if index + 1 < len(self.segments) else None
                if following and following.dissolve > 0 and time >= following.start - following.dissolve / 2:
                    mix = (time - (following.start - following.dissolve / 2)) / following.dissolve
                    found = [(segment, 1 - mix), (following, mix)]
                if segment.dissolve > 0 and time < segment.start + segment.dissolve / 2 and index > 0:
                    previous = self.segments[index - 1]
                    mix = (time - (segment.start - segment.dissolve / 2)) / segment.dissolve
                    found = [(previous, 1 - mix), (segment, mix)]
                break
        return found
