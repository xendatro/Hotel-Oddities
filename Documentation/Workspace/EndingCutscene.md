# Ending cutscene Studio assets

The ending cutscene (`ReplicatedStorage\Services\EndingCutsceneService.luau`, numbers in `ReplicatedStorage\Configs\EndingCutsceneConfig.luau`) binds three Studio-only asset groups by name. None of them exist on disk, so they persist only when the place is saved or published. Swap or retune anything by editing the instance in place and keeping its name. The sound cues have their own sheet in `Documentation\ReplicatedStorage\Sounds.md`; the story is in `Documentation\Lore.md`.

## StarterGui.EndingCutsceneGui

A copy of `StarterGui.IntroCutsceneGui` with the card's `Rule` and `Subtitle` removed: ScreenGui, Enabled false (the code enables it), DisplayOrder 1001 (above `EndGui` at 60, so its black covers the win screen fading in underneath), IgnoreGuiInset true, ResetOnSpawn false, ScreenInsets None.

| Child | Use |
| --- | --- |
| `Fade` | Full-screen black for the opening blink, the final black and a skip |
| `Vignette` | Edge darkening, driven by the `Vignette` grade channel |
| `Letterbox` | `Top` and `Bottom` bars, authored open at 0.12 of the screen; the code collapses them and eases them in |
| `Caption` | Bottom line for `Thank you for staying with us, <DisplayName>.` |
| `Card.Title` | Centred line (moved to 0.5, 0.5) for `We'll keep your room ready.` |
| `Skip` | The hold-to-skip pill, driven by `KeyPill` (Space, gamepad A, or hold the pill) |

## ReplicatedStorage.Effects.EndingCutscene

### Stage

A Model whose `WorldPivot` was set to `Workspace.Maze15.ExitElevator`'s pivot when it was built. At run time it is cloned and pivoted onto the exit's pivot, so if the elevator moves the props move with it. Every part is anchored with collision, query, touch and shadow casting off.

| Part | What it is | Driven by |
| --- | --- | --- |
| `CabinLamp` | Warm neon disc on the cabin ceiling (`LampTrim` is its brass ring), with a shadowed PointLight (1.6, range 17) | `Lamp` grade channel: neon fades to `Stage.LampOff`, the light scales and switches off below 2%; its flickers are `Step` keys |
| `Dial` | Floor indicator over the doors, inside the cabin: brass `Plate`, cream `Face`, seven `Tick` marks, the `Hub` (its front face points into the cabin) and the red `Needle`, authored pointing straight up | `Needle` channel: 0 is the left tick and 1 the right (`Stage.NeedleSweep` = 60 to -60 degrees about the hub's face normal) |
| `ExitGlow` | Invisible point just outside the EXIT sign with a red PointLight (1.8, range 10), the light the Sisters stand in at the doors | `Glow` channel |
| `Daylight` | Neon white wall just outside the door opening, authored fully transparent, with a SurfaceLight (3.5, range 30, angle 110) on the face pointing into the cabin | `Daylight` channel sets its transparency; the light also scales with how far the doors are open |
| `CeilingDust` | Invisible strip under the ceiling just inside the doors holding copies of the `VentDust` emitters (`Grit`, `Sift`, `Puff`), emitting down, disabled, each with a `Burst` count (40, 12, 6) | `Bang` event: one burst |
| `DaylightMotes` | Invisible volume inside the doorway holding a copy of the intro's `Motes` emitter (rate 16, light emission 0.6, `Prewarm` 40), disabled | `MotesIn` and `MotesOut` events |

### Grade

`Color` (ColorCorrectionEffect), `Blur` (BlurEffect, size 0) and `Depth` (DepthOfFieldEffect, disabled, in-focus radius 12). The cutscene clones these into Lighting and destroys the clones on restore. The daylight bloom is not a template: the cutscene overrides the existing `Lighting.Bloom` toward `EndingCutsceneConfig.Bloom` and releases it after.

### Animations

`Idle` (507766388) and `Walk` (507777826), the default R15 idle and walk. The stand-in uses the player's own `Animate` pack when the character has one and falls back to these.

## Positions

Every position in `EndingCutsceneConfig` is door space, `Vector3(right, up, forward)`: the origin is the centre of the exit's `Threshold` part at floor height, forward points out of the cabin into the corridor, right is to the right when facing out. The cabin interior runs from about forward -12.4 (back wall) to 0 (doors), right -6.8 to 6.8, and up 0 to 8.47 (ceiling). The corridor in front of the exit runs straight out for about 146 studs, with lantern pairs about 22, 37, 52 and 67 studs out and the junction ceiling light at 6.7.

To retune a shot during a playtest, freeze the timeline with `ReplicatedStorage\Playtest\EndingShots` (see `PLAYTESTING.md`) and screenshot it.
