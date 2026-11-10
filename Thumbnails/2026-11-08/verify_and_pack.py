from pathlib import Path
import hashlib
import json
import sys
import zipfile
from PIL import Image

root = Path(__file__).resolve().parent
briefs = json.loads((root / "prompts.json").read_text(encoding="utf-8"))["entries"]
sources = {}
for source_file in sorted(root.glob("sources-*.json")):
    for item in json.loads(source_file.read_text(encoding="utf-8")):
        if item["id"] in sources:
            raise RuntimeError("Duplicate source " + item["id"])
        sources[item["id"]] = item
finals = sorted((root / "final").glob("*.png"))
if len(finals) != 50 or len(sources) != 50 or len(briefs) != 50:
    raise RuntimeError(f"Expected 50 finals, sources and briefs; got {len(finals)}, {len(sources)}, {len(briefs)}")
records = []
seen = set()
gallery_path = root / "gallery.html"
gallery = gallery_path.read_text(encoding="utf-8")
for brief in briefs:
    image_path = root / "final" / (brief["id"] + ".png")
    preview_path = root / "previews" / (brief["id"] + ".jpg")
    with Image.open(image_path) as image:
        dimensions = image.size
        mode = image.mode
        image.verify()
    if dimensions != (1920, 1080) or mode != "RGB":
        raise RuntimeError(f"Invalid export {image_path.name}: {dimensions}, {mode}")
    with Image.open(preview_path) as image:
        if image.size != (480, 270):
            raise RuntimeError("Invalid preview " + preview_path.name)
        image.verify()
    digest = hashlib.sha256(image_path.read_bytes()).hexdigest()
    if digest in seen:
        raise RuntimeError("Duplicate final " + image_path.name)
    seen.add(digest)
    if f'final/{image_path.name}' not in gallery or f'previews/{preview_path.name}' not in gallery:
        raise RuntimeError("Missing gallery link " + brief["id"])
    records.append({
        "id": brief["id"],
        "file": image_path.relative_to(root).as_posix(),
        "preview": preview_path.relative_to(root).as_posix(),
        "width": dimensions[0],
        "height": dimensions[1],
        "mode": mode,
        "bytes": image_path.stat().st_size,
        "sha256": digest,
        "hero": brief["hero"],
        "entity": brief["enemy"],
        "locationReference": brief["location"],
        "styleBrief": brief["style"],
        "requestedHeadline": brief["caption"],
        "containsText": ('data-text="true"><a href="final/' + image_path.name + '"') in gallery,
        "references": brief["refs"],
        "generatedOriginal": sources[brief["id"]]["source"],
        "visualReview": sources[brief["id"]]["review"]
    })
manifest = {
    "game": "Hotel Oddities",
    "date": "2026-11-08",
    "tool": "built-in image_gen",
    "referencePlaceId": 107541011814957,
    "count": 50,
    "export": "FFmpeg Lanczos resampling to 1920x1080 RGB; no content repainting or compositing",
    "review": "Every generated image inspected individually for subject readability, distinct composition, entity identity, coherent props and requested avatar corrections.",
    "images": records
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
archive_path = Path(sys.argv[1]).resolve()
if archive_path.exists():
    raise RuntimeError("Archive already exists: " + str(archive_path))
archive_path.parent.mkdir(parents=True, exist_ok=True)
include = finals + sorted((root / "previews").glob("*.jpg")) + sorted(root.glob("sources-*.json"))
include += [root / name for name in ["README.md", "gallery.html", "prompts.json", "manifest.json", "export.ps1", "verify_and_pack.py"]]
with zipfile.ZipFile(archive_path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
    for path in include:
        archive.write(path, "Hotel-Oddities-50-Thumbnails/" + path.relative_to(root).as_posix())
with zipfile.ZipFile(archive_path) as archive:
    invalid = archive.testzip()
    if invalid:
        raise RuntimeError("Corrupt zip member: " + invalid)
    pngs = [name for name in archive.namelist() if "/final/" in name and name.endswith(".png")]
    if len(pngs) != 50:
        raise RuntimeError("Wrong final count in zip")
print(json.dumps({"count": 50, "dimensions": "1920x1080", "uniqueHashes": len(seen), "archive": str(archive_path), "bytes": archive_path.stat().st_size, "sha256": hashlib.sha256(archive_path.read_bytes()).hexdigest()}))
