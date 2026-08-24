# ReplicatedFirst

### Preload.local.luau
LocalScript that runs before anything else. It parents its `LoadingGui` child into the player's PlayerGui, gathers every content-bearing asset in the game plus the icon and animation ids named by configs, warms them through `ContentProvider:PreloadAsync`, drives a progress bar and shimmer sweep while loading, then fades the overlay out and disables the GUI.
- API: no return value — this is a script, not a module.
- Requires: `Configs\EffectsHUDConfig` (icon ids) and `Configs\AnimationConfig` (animation ids), both loaded through `pcall` so a missing config does not block loading. Expects a `LoadingGui` ScreenGui child containing `Overlay` with `Loading.UIGradient`, `Assets` (TextLabel) and `Bar.Frame`.

Preloading scans the descendants of `ReplicatedStorage`, `workspace`, `StarterGui`, `SoundService` and `Lighting` for MeshPart, SpecialMesh, Decal, Texture, ImageLabel, ImageButton, Sound, Animation, ParticleEmitter, Beam, Trail, Shirt, Pants and SurfaceAppearance instances. It prints a `[Preload] warmed N assets in Xs` line when finished. This script is independent of the client Init bootstrap and does not require any Service.
