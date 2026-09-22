# Rotunda connector room

`Workspace.Maze15.Connectors.RotundaRoom_1` is the only rotunda in the place. It is a 40-segment cylinder with a shaft running up to Y 81.55 and down to Y -127.47 from the room itself, whose floor sits at Y -22.632.

## Naming

Each of the 40 segments owns one column of each family. The segment index is the trailing number.

| Family | Count | What it is |
| --- | --- | --- |
| `RU_band_<seg>` | 40 | Upper shaft wallpaper, one part per segment, Plaster, two Textures. 5.06 x 100.82 x 1.00 on the 28 full-width segments, where it also covers the room's own eye-level wall; 5.06 x 93.00 x 1.00 on the 12 segments around the doorways |
| `RU_ring0..7_<seg>` | 320 | Wood trim ring between wallpaper courses, 5.06 x 0.50 x 1.18 |
| `RU_crown<seg>` | 40 | Wood trim ring closing the top of the upper shaft |
| `RD_band_<seg>` | 40 | Lower shaft wallpaper, 5.06 x 104.71 x 1.00, same Plaster |
| `RD_ring0..8_<seg>` | 360 | Wood trim ring between lower wallpaper courses |
| `RW_base` / `RW_wain` / `RW_rail` / `RW_crown` | 34 each | Four of the room's own five wall layers at eye level |
| `RW_wall<seg>` | 6 | The eye-level wallpaper, only on the half-width shoulders beside the doorways |

The `RW_*` families have 34 segments rather than 40 because the six hallway mouths take the rest. `RW_wall` is down to 6 because the 28 full-width ones merged upward into `RU_band_<seg>`; what is left are the 2.275-wide shoulders flanking each doorway, which are narrower than the band above them and so cannot merge.

## Why the bands are single columns

The bands were originally `RU_band0..7_<seg>` and `RD_band0..8_<seg>`, one part per course, 680 parts in all. Within a column every course shared X, Z, `Orientation.Y`, size, material and colour, and each 0.50-stud gap between courses is filled by a trim ring that is 1.18 deep against the band's 1.00 and the same 5.06 wide. A ring therefore encloses any band geometry inside its own slice, so one continuous column reads the same as the stack of courses. Merging them left 80 parts and took the model from 2055 to 1455 BaseParts and from 1509 to 309 Textures.

A second pass then took each full-width `RW_wall<seg>` into the `RU_band_<seg>` above it. Those two abut exactly at Y -11.442 with no gap at all, and they already matched in width, depth, rotation, material, colour and texture setup, so it is a plain extension rather than a hide-behind-the-trim case. That saved another 28 parts and 56 Textures.

Three limits on all of this. The rings are visible trim at distinct heights and cannot be collapsed the same way. The wall cannot also swallow the `RD_band_<seg>` below it, because the 3.50-stud `RW_wain<seg>` filling that gap is WoodPlanks at exactly 1.00 deep, the same depth as the band, so a through-column would sit coincident with the wainscot and z-fight rather than hide behind it. And the six shoulder walls beside the doorways are only 2.275 wide against their band's 5.058.

The wallpaper texture is 232876941 at `StudsPerTile` 4 x 4, which does not divide evenly into either column height. It did not divide evenly into a single course either, so the tiling now breaks mid-tile once at the top of each column instead of at every course.

Every band and every `RW_wall` carries the `Wallpaper` CollectionService tag and no attributes. No script in the repo reads that tag; `HallwayWallService` gathers walls by `HallwayWall`, so nothing here is registered for the hallway crush oddity and moving a part's centre out of that service's 24-stud height window changes nothing.

## Backup

`ServerStorage.Backups.RotundaRoom_1_PreBandMerge` is the model as it stood before the merge, handled the same way as `ServerStorage.POIBackups`: CollectionService tags are stripped and recorded in each instance's `BackupTags` attribute, and `BackupParent` names the original parent. Delete it once the merge has held.

## Still mergeable

`RU_ring7_<seg>` and `RU_crown<seg>` are two identical 0.50-tall wood rings abutting at Y 82.05, on all 40 segments. They match in every property, so they could become one 1.00-tall ring for another 40 parts. Left alone for now.
