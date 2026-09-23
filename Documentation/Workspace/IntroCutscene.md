# Intro cutscene Studio assets

The intro cutscene (`ReplicatedStorage\Services\IntroCutsceneService.luau`, numbers in `ReplicatedStorage\Configs\IntroCutsceneConfig.luau`) binds four Studio-only asset groups by name. None of them exist on disk, so they persist only when the place is saved or published. Swap an effect by editing the instance in place and keeping its name; the code finds everything by name. Sounds have their own swap sheet, with the exact moment each cue plays and the traps in replacing a timed one: `Documentation\ReplicatedStorage\Sounds.md`. What the cutscene says about the hotel, and which parts of that were invented for it, is in `Documentation\Lore.md`.

## StarterGui.IntroCutsceneGui

ScreenGui: Enabled false (the code enables it), DisplayOrder 1001, IgnoreGuiInset true, ResetOnSpawn false, ZIndexBehavior Sibling, ScreenInsets None and ClipToDeviceSafeArea false, so the fade and letterbox also cover a notch. Every position is Scale-based; the pills use offset sizing like `StarterGui.Cursor.Interact`.

| Child | What it is |
| --- | --- |
| `Fade` | Full-screen Frame, pure black (0, 0, 0), transparency 1, ZIndex 1; the black the smash cut, the card and a skip sit on |
| `Vignette` | Full-screen CanvasGroup, GroupTransparency 1, ZIndex 2, with `Top`, `Bottom`, `Left`, `Right` Frames (0.34 of the screen on their axis) in black (0, 0, 0) and inward UIGradient transparency ramps (0:0, 0.35:0.55, 0.7:0.9, 1:1) |
| `Letterbox` | Full-screen Frame, ZIndex 3, with `Top` and `Bottom` bars in black (0, 0, 0), authored open at Size.Y.Scale 0.12; the code reads that as the target and collapses them to 0 before first showing the gui |
| `Caption` | TextLabel at (0.5, 0.94), 0.7 x 0.042 of the screen, SpecialElite, (238, 231, 214), TextScaled with a `ResponsiveTextSize` constraint 12-26, ZIndex 5; the typed welcome line |
| `Card` | Full-screen Frame, ZIndex 6, with `Title` (TextScaled 16-44), `Rule` (a 1 px white line with a `Taper` UIGradient that the code grows to 240 px) and `Subtitle` (TextScaled 12-22), all SpecialElite |
| `Skip` | CanvasGroup cloned from `StarterGui.Cursor.Interact`: `Scale` (UIScale), `Pill` (UICorner, UIStroke, `Key` with UICorner, UIStroke, `Scale`, a UIListLayout and `Label`, the `Action` label and a `Hold` fill in (158, 176, 208) at transparency 0.72) and a full-size `Hit` TextButton at ZIndex 10. Anchored (1, 0.5) at (1, -28, 0.94, 0), laid out for the key "Space" |

Keep TextWrapped on for every TextScaled label: turning TextWrapped off silently turns TextScaled off too.

## StarterGui.IntroCutscenePills

ScreenGui: Enabled false, DisplayOrder 1002, IgnoreGuiInset true, ResetOnSpawn false, ScreenInsets DeviceSafeInsets and ClipToDeviceSafeArea true, so the Replay pill shown during the elevator loading screen keeps clear of a notch. It holds `Replay`, the same structure as `Skip`, anchored (1, 1) at (0.9864, 0, 0.925, 0), laid out for the key "T" with room for "Intro queued". Both pills are authored Visible true, GroupTransparency 1 and UIScale 0.92; `KeyPill` sets a fully hidden pill Visible false so its `Hit` button cannot catch taps.

## ReplicatedStorage.Sounds.IntroCutscene

Twelve cues (`Drone`, `Heartbeat`, `Type`, `Notice`, `Dip`, `Whip`, `Flicker`, `LightOut`, `EyesOpen`, `Rush`, `Blackout`, `Toggle`), each an AudioEmitter holding an AudioPlayer named `Player` and a `Wire`, with no `RadioAllowed` tag. The full sheet, with each cue's asset, settings, bus, the exact second it plays and how to swap it, is `Documentation\ReplicatedStorage\Sounds.md`.

## ReplicatedStorage.Effects.IntroCutscene

Emitters stay Enabled false with Rate 0 in the templates; the code enables or emits them. Textures were copied from `Workspace.Vfx` ids; nothing reads `Workspace.Vfx` at run time.

| Template | What it is |
| --- | --- |
| `EyeGlow` | BillboardGui (Size 1.4 x 1.4 studs, LightInfluence 0, AlwaysOnTop false, Brightness 2, MaxDistance 1000) holding ImageLabel `Glow` with the soft round halo 6673021984 tinted red. The visible halo is about 45 % of the size, so size it at 2.5-3x the eye it surrounds (the Creep's eye is 1.2 studs, the Stalker's 0.15) |
| `Motes` | Attachment holding ParticleEmitter `Motes`: slow warm dust in the junction light, texture 6673021984, LightInfluence 0.8, LightEmission 0.4, long lifetimes, slight drag and random rotation |
| `DarkWisp` | Attachment holding ParticleEmitter `Wisp`: dark smoke flipbook 12865691168 (Grid8x8, OneShot), colour (8, 8, 10), transparency 0.55 easing to 0.35 at 12 % of its life then out to 1, size 1.2 to 3.5, rotation 0-360 and RotSpeed +-30, emitted with `:Emit` for the Stalker's dip puff and the Creep's breathing wisps |

The staged Creep's distortion is the shared `ReplicatedStorage.Effects.CreepDistortion`, the same one `CreepRenderService` uses.
