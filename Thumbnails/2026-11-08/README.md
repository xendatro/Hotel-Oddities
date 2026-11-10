# Hotel Oddities: 50 distinct thumbnails

Fifty new promotional illustrations, numbered 01–50, in `final/`. Every final is a 1920 × 1080 RGB PNG. Open `gallery.html` after extracting the zip to browse the set, filter by avatar or headline, and open an original at full size.

The art direction deliberately varies composition, medium, palette, scale, entity, and location. It includes cinematic 3D, cel shading, vintage painted posters, VHS footage, charcoal, woodcut, scratchboard, watercolor, oil paint, paper cutouts, risograph, clay miniatures, low-poly horror, pixel art, and surreal architecture. Some designs use a short headline; others rely entirely on the scene.

Cast rotates between hythe55, xendatro, and bacon-hair guests. Hythe55's prompts remove all crowns and shoulder cats and straighten, center, and reduce the yellow smile top hat to wearable proportions. These corrections also apply to his Mimic copy.

References are the separate cast and location screenshots retained under `../2026-10-24/references/`, photographed from Hotel Oddities (place 107541011814957). This batch uses the existing photographs; no Studio window, camera, gameplay state, or live player save was changed. The image model constructs new illustrative scenes from those references, so the results are promotional interpretations rather than gameplay screenshots.

`prompts.json` contains the complete prompt set and reference mapping. `sources-*.json` records each generated original and visual review. `export.ps1` resamples with FFmpeg/Lanczos to the exact final dimensions and creates 480 × 270 gallery previews; it does not repaint, recolor, or composite content. Generated originals remain in Codex's generated-images folder. `manifest.json` records final dimensions, SHA-256 hashes, cast, entity, style, reference mapping, and visual review.

The delivery archive contains the 50 final PNGs, gallery previews, gallery, prompts, manifest, and this README. It is sent to the user's D device using Tailscale Taildrop.
