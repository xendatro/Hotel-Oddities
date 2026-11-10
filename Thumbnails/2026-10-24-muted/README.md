# Hotel Oddities: muted horror thumbnails

Fifteen additional promotional thumbnails, numbered 16–30, exported as 1920 x 1080 PNGs under `final/`.

This batch follows the request for less colorful, scarier artwork that remains clearly visible. The art direction uses faded taupe, bone, ash gray, subdued brown and dusty clothing colors, with readable faces, lifted shadow detail, restrained practical lighting and threatening proximity. It emphasizes anticipation and uncanny encounters.

The built-in image generation tool composes new scenes from the neutral avatar/enemy photographs and hotel location screenshots already captured from Hotel Oddities (place 107541011814957) for the first batch. References remain in `../2026-10-24/references/`; the first batch's finished thumbnails are not overwritten. New posing or Studio edits are unnecessary for this batch.

`prompts.json` records the shared art direction and fifteen individual briefs. `manifest.json` maps each output to its source references and generated original and records dimensions, hashes and visual review. `gallery.html` compares all fifteen; opening it locally allows the full PNG to be opened from each selected image. `previews/` contains small JPEGs for the gallery only.

Generated originals remain in Codex's generated-images directory. FFmpeg resamples the final exports with Lanczos to exact 1920 x 1080 dimensions; the export does not repaint, recolor or composite content. Every final image is reviewed for visibility, restrained color, attached accessories, plausible poses, continuous objects and clear thumbnail storytelling.
