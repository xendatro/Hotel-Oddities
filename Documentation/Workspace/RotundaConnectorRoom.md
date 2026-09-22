# Rotunda connector room

`Workspace.Maze15.Connectors.RotundaRoom_1` is the only rotunda in the place. It is a 40-segment cylinder with a shaft running up to Y 81.55 and down to Y -127.47 from the room itself, whose floor sits at Y -22.632.

## Naming

Each of the 40 segments owns one column of each family. The segment index is the trailing number.

| Family | Count | What it is |
| --- | --- | --- |
| `RU_band_<seg>` | 40 | Upper shaft wallpaper, one part per segment, 5.06 x 93.00 x 1.00, Plaster, two Textures |
| `RU_ring0..7_<seg>` | 320 | Wood trim ring between wallpaper courses, 5.06 x 0.50 x 1.18 |
| `RU_crown<seg>` | 40 | Wood trim ring closing the top of the upper shaft |
| `RD_band_<seg>` | 40 | Lower shaft wallpaper, 5.06 x 104.71 x 1.00, same Plaster |
| `RD_ring0..8_<seg>` | 360 | Wood trim ring between lower wallpaper courses |
| `RW_base` / `RW_wain` / `RW_rail` / `RW_wall` / `RW_crown` | 34 each | The room's own five wall layers at eye level |

The `RW_*` families have 34 segments rather than 40 because the hallway mouths take the other six.

## Why the bands are single columns

The bands were originally `RU_band0..7_<seg>` and `RD_band0..8_<seg>`, one part per course, 680 parts in all. Within a column every course shared X, Z, `Orientation.Y`, size, material and colour, and each 0.50-stud gap between courses is filled by a trim ring that is 1.18 deep against the band's 1.00 and the same 5.06 wide. A ring therefore encloses any band geometry inside its own slice, so one continuous column reads the same as the stack of courses. Merging them left 80 parts and took the model from 2055 to 1455 BaseParts and from 1509 to 309 Textures.

Two limits on that trick. The rings are visible trim at distinct heights and cannot be collapsed the same way. The five `RW_*` layers are different materials and colours, so they are five surfaces rather than a hidden stack.

The wallpaper texture is 232876941 at `StudsPerTile` 4 x 4, which does not divide evenly into either column height. It did not divide evenly into a single course either, so the tiling now breaks mid-tile once at the top of each column instead of at every course.

Every band carries the `Wallpaper` CollectionService tag. No script in the repo reads that tag; `HallwayWallService` gathers walls by `HallwayWall`.

## Backup

`ServerStorage.Backups.RotundaRoom_1_PreBandMerge` is the model as it stood before the merge, handled the same way as `ServerStorage.POIBackups`: CollectionService tags are stripped and recorded in each instance's `BackupTags` attribute, and `BackupParent` names the original parent. Delete it once the merge has held.
