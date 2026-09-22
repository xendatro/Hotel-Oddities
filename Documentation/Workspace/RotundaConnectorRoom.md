# Rotunda connector room

`Workspace.Maze15.Connectors.RotundaRoom_1` is the only rotunda in the place. It is a 40-segment cylinder with a shaft running up to Y 81.55 and down to Y -127.47 from the room itself, whose floor sits at Y -22.632.

## Naming

Each of the 40 segments owns one column of each family. The segment index is the trailing number.

| Family | Count | What it is |
| --- | --- | --- |
| `RU_band_<seg>` | 40 | Shaft and room wallpaper, one part per segment, Plaster, two Textures. 5.06 x 209.03 x 1.00 on the 28 full-width segments, running the whole height from Y -127.47 to 81.55; 5.06 x 93.00 x 1.00 on the 12 segments around the doorways, which keep a separate `RD_band_<seg>` below |
| `RU_ring0..6_<seg>` | 280 | Wood trim ring between wallpaper courses, 5.06 x 0.50 x 1.18 |
| `RU_crown<seg>` | 40 | Wood trim closing the top of the upper shaft, 5.06 x 1.00 x 1.18, spanning Y 81.554 to 82.554 |
| `RD_band_<seg>` | 12 | Lower shaft wallpaper on the doorway segments only, 5.06 x 104.71 x 1.00, same Plaster |
| `RD_ring0..8_<seg>` | 360 | Wood trim ring between lower wallpaper courses |
| `RW_base` / `RW_rail` / `RW_crown` | 34 each | Three of the room's own five wall layers at eye level |
| `RW_wain<seg>` | 34 | Wainscot. 1.024 deep on the 28 full-width segments so it covers the column behind it, 1.000 on the six doorway shoulders |
| `RW_wall<seg>` | 6 | The eye-level wallpaper, only on the half-width shoulders beside the doorways |

The `RW_*` families have 34 segments rather than 40 because the six hallway mouths take the rest. `RW_wall` is down to 6 because the 28 full-width ones merged upward into `RU_band_<seg>`; what is left are the 2.275-wide shoulders flanking each doorway, which are narrower than the band above them and so cannot merge.

## Why the bands are single columns

The bands were originally `RU_band0..7_<seg>` and `RD_band0..8_<seg>`, one part per course, 680 parts in all. Within a column every course shared X, Z, `Orientation.Y`, size, material and colour, and each 0.50-stud gap between courses is filled by a trim ring that is 1.18 deep against the band's 1.00 and the same 5.06 wide. A ring therefore encloses any band geometry inside its own slice, so one continuous column reads the same as the stack of courses. Merging them left 80 parts and took the model from 2055 to 1455 BaseParts and from 1509 to 309 Textures. Three further passes below brought it to 1359 BaseParts and 197 Textures.

A second pass took each full-width `RW_wall<seg>` into the `RU_band_<seg>` above it. Those two abut exactly at Y -11.442 with no gap at all and already matched in width, depth, rotation, material, colour and texture setup, so it is a plain extension rather than a hide-behind-the-trim case. That saved another 28 parts and 56 Textures.

A third pass joined `RD_band_<seg>` on as well, giving one 209.03-stud part per full-width segment. The 3.50-stud gap between them is filled by `RW_wain<seg>`, which was WoodPlanks at exactly 1.000 deep, the same as the band and in the same plane, so a through-column would have been coincident with it and z-fought rather than hidden. The wainscots on those 28 segments were widened to 1.024, giving 0.012 of cover per side, which is the `Wainscot.Across` value `HallwayCrush` already uses on the hallway walls for this same clash. Measured after the change, every one of the 28 has exactly 0.01200 of cover and zero lateral offset. The wainscot's visible face moved 0.012 into the room. That saved a further 28 parts and 56 Textures.

A fourth pass merged `RU_ring7_<seg>` into `RU_crown<seg>`. Those were two identical 0.50-tall wood rings abutting at Y 82.054 with a 0.0000 gap, matching in every property and carrying no children or tags, so the crown is now a single 1.00-tall ring. That saved the last 40 parts. `RU_ring` runs 0 to 6 from here.

Two limits remain. The other rings are visible trim at distinct heights, separated by wallpaper, and cannot be collapsed. And the six shoulder walls beside the doorways are only 2.275 wide against their band's 5.058, so those segments keep a separate `RW_wall` and `RD_band`.

The merged columns are 209 studs tall, so each sits in more streaming regions than the parts it replaced and loads whenever any of them is in range.

The wallpaper texture is 232876941 at `StudsPerTile` 4 x 4, which does not divide evenly into either column height. It did not divide evenly into a single course either, so the tiling now breaks mid-tile once at the top of each column instead of at every course.

Every band and every `RW_wall` carries the `Wallpaper` CollectionService tag and no attributes. No script in the repo reads that tag; `HallwayWallService` gathers walls by `HallwayWall`, so nothing here is registered for the hallway crush oddity and moving a part's centre out of that service's 24-stud height window changes nothing.

## Backup

`ServerStorage.Backups.RotundaRoom_1_PreBandMerge` is the model as it stood before the merge, handled the same way as `ServerStorage.POIBackups`: CollectionService tags are stripped and recorded in each instance's `BackupTags` attribute, and `BackupParent` names the original parent. Delete it once the merge has held.

## Nothing further

A sweep over all 1183 block parts for vertical neighbours matching on position, rotation, size, material, colour, transparency, reflectance, collision, shadow and full texture setup, keeping only pairs that abut or have their gap covered by a strictly deeper part, returns zero remaining chains. A separate check for parts wholly enclosed inside another part also returns zero. This class of saving is exhausted for this room.
