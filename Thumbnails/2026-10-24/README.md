# Hotel Oddities thumbnails

Fifteen cinematic Roblox horror thumbnails, exported as 1920 x 1080 PNGs in `final/`.

The built-in image generation tool combines screenshots of the actual Hotel Oddities place (107541011814957) with separate, correctly assembled avatar and enemy references. The generated scenes use new action compositions, lighting, and expressions. They are promotional illustrations rather than unmodified gameplay captures.

`references/cast/` contains neutral, individually photographed avatar and enemy designs. `references/locations/` contains hotel scenery photographs. `references/` also retains five early staged compositions for provenance. `prompts.json` records the shared art direction and all fifteen scene briefs. `scenes.json` records the original Studio camera and cast staging experiments; the final briefs supersede those experimental poses. The model composed the action in the final images from separate references, following the owner's direction.

`staging.luau` is an edit-time photography helper, kept outside the synced game containers. It temporarily clones and assembles rigs, stores original lighting/UI/camera settings, and restores them with `_G.HotelThumbnails.restore()`. AnimationConstraints and RigidConstraints are converted to Motor6D/Weld joints on clones; joint solving works in both directions so hair and accessories follow their attachment parents. The running pose comes from the Roblox animation rather than manually inverted elbows. Nothing automatically executes in the game.

Source screenshots are retained at their native viewport size. The image model's finished outputs are resampled with Lanczos to the requested exact 1920 x 1080 export size. No content is painted or composited by the export step. Original generated outputs remain in the Codex generated-images directory.

All temporary Studio cast, backdrop, and photographic lights were removed, and original Lighting, StarterGui enabled states, and camera settings were restored after photography. The existing Studio window was already open and remains open. No live playtest or player save was used.

The deliverable set, dimensions, reference mapping, and visual review are recorded in `manifest.json`. Open `gallery.html` to compare the finished set.
