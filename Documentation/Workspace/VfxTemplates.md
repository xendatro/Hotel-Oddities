# World VFX templates

Studio-only instances under `ReplicatedStorage.Effects`, played by
`VfxService` (see `Documentation\ReplicatedStorage\Services.md`). They are not
on disk, so the place must be saved for changes to them to stick. Tune the look
here, on the instances; the scripts only decide where and when.

## Conventions

- Each template is one invisible, anchored `Part`. Its size is the default
  emission volume; callers that pass `Size` resize it.
- Emitters are `Box` shaped and emit along the part's **Front** face.
- Burst emitters are disabled with `Rate` 0 and carry `EmitCount` (particles
  per play), optionally `EmitPerStud` (extra per stud of the part's X size) and
  `EmitDelay` (seconds).
- Sustained emitters are left `Enabled`. `RatePerStud` overrides `Rate` from the
  part's X size. They run until the caller stops them, for the caller's
  `Duration`, or for the part's `Duration` attribute.
- A `PointLight` with `FlashTime` fades to nothing over that many seconds.
- A `MaxDistance` attribute on the part overrides the default 220-stud camera
  cull.
- Textures reused from the enemy despawn puff: dust flipbook `11627083142`
  (8x8 one-shot) and powder flecks `8030760338`. The spark streak `7216979807`
  is from Blue's Particle Effect kit in `Workspace.Vfx`.

## Templates

| Template | Played by | Aim | Emitters |
| --- | --- | --- | --- |
| `ChaosCrash` | `Chaos` at its route end | out of the wall | `Dust` 14, `Chunks` 26 falling flecks, `Haze` 6 lingering after 0.2 s |
| `VentDust` | `CeilingVentService` as a vent drops its dweller | down, sized to the vent door | sustained `Grit` and `Sift` for 0.9 s, `Puff` 5 |
| `DwellerLanding` | `CeilingDweller` on landing | up from the floor | `Ring` 10 low dust, `Grit` 10 |
| `PaintingBurst` | `PaintingDweller` on the pop | out of the canvas, sized to it | `ScrapsLight` 14 and `ScrapsDark` 14 fluttering scraps, `Dust` 8 |
| `LanternShatter` | `FixtureFall` (lantern) on floor impact | up from the floor | `Glass` 22, `Sparks` 9, `Puff` 3, `Flash` light fading over 0.18 s |
| `PaintingThud` | `FixtureFall` (painting) on floor impact | up from the floor | `Ring` 7, `Grit` 5 |
| `CrushDust` | `HallwayCrushVfxService`, one per wall side | down from under the ceiling, following the wall | sustained `Grit` 1.2 per stud, `Sift` 0.18 per stud |
| `CrushSeal` | `HallwayCrushVfxService` when the walls meet | out of each end of the sealed run | `Burst` 8, `Chips` 12 |
| `FlashlightDust` | `FlashlightService` for the local beam | 8 studs down the beam | sustained `Specks`, lit by the flashlight |
| `StalkerWisp` | `StalkerGlowService` when a peeking Stalker is caught | away from the camera, slightly up | `Wisp` 7 and `WispTrail` 3 after 0.14 s, copies of the intro's `DarkWisp` |

The Stalker's eye halo is not a template here: it reuses
`ReplicatedStorage.Effects.IntroCutscene.EyeGlow`.

The Creep has no despawn effect of its own. Its exit is the Glass-material
`CreepDistortion` sweeping from the Creep toward the viewer, and Glass hides
every particle behind it, so anything spawned at the Creep would not be seen.
