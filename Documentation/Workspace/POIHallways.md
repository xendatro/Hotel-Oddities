# Baked oddity hallways

The `HallwayVoid` and hallway `Transparency` oddities no longer spawn. Each one was applied once, permanently, to a single hallway, and that hallway is now a point of interest. Both were built in Edit mode from the oddities' own geometry code, using the spans `HallwaysService.StraightSpans` and `HallwayVoid.Resolve` returned in a playtest. No script builds them at runtime.

## The Hole

The pit sits in the east-west hallway centred on (458.99, -22.632, -380.81), running along +X. The opening is 124.6 studs long and 15.23 studs wide, trimmed back from the junctions at both ends exactly as `HallwayVoid` trims. That hallway was picked because the opening covers a single floor slab and no connector room, and only two room doors (`Doorway_685` and `Doorway_707`, facing each other at the middle) open onto it.

- `Workspace.Maze15.Floors.Part` (155.06 long) was cut to its west remainder, and a new `Part_HolePiece` holds the east remainder. Both keep the `MazeFloor` tag.
- `Workspace.Maze15.Runners.CarpetRunner` was cut the same way. The new east piece is also named `CarpetRunner`.
- `Workspace.Maze15.HolePit` holds the shaft built with the `HallwayVoid` settings: four slate walls, the wooden `Plank`, twelve `VoidLayer_n` parts and `KillVolume`.
- `KillVolume` is invisible, has no collision, query or touch, and carries the `VoidPit` tag and `DeathCause = "HallwayVoid"`. `ServerStorage\Classes\VoidPit` kills any unprotected player whose root enters it. It starts 1.25 studs below the floor, matching the oddity's `KillDepth`.
- `Workspace.POIs.The Hole` is the discovery part: 124.6 x 50 x 15.73, the same height and Y as the other POI parts.

## Invisible Hallway

The north-south hallway centred on (-443.964, -22.632, -279.280) is 90.39 studs long with no doors and no rooms. Every part that `Transparency` would have claimed now has a permanent `Transparency` of 0.02 (`HallwayTransparency`). That is 65 parts in `Maze15.Floors`, `Runners`, `Ceiling`, `CeilingLights`, `Stations` and the wall trim folders. Long wall parts that sit mostly outside the hallway box are untouched, as with the oddity. Parts added to that hallway at runtime, like loot displays, are not faded. The oddity used to fade them through `DescendantAdded`.

- `Workspace.POIs.Invisible Hallway` is the discovery part: 15.73 x 50 x 90.39.

## Backups and reverting

`ServerStorage.POIBackups` has one folder per area.

- Each backed-up part is an untouched clone of the original. Its CollectionService tags are stripped so nothing in ServerStorage is picked up by tag, and they are stored in its `BackupTags` attribute, on descendants too. `BackupParent` records the original parent's full name.
- Each clone has an ObjectValue `Source` pointing at the live part it was taken from. The Hole's clones also have one `Piece` ObjectValue for each extra part the cut created.
- `AddedPOI` points at the new POI part. In The Hole's folder, `AddedStructure` points at `Maze15.HolePit`.

To revert The Hole:

1. For each part clone, copy its `CFrame` and `Size` back onto `Source.Value`, then destroy every `Piece.Value`.
2. Destroy `AddedStructure.Value` and `AddedPOI.Value`.
3. Remove `Enabled = false` from `Effects.HallwayVoid` in `MapOddityConfig`, and remove The Hole's entry from `RoomsIndexConfig`.

To revert the Invisible Hallway:

1. For each part clone, set `Source.Value.Transparency` to the clone's `Transparency`.
2. Destroy `AddedPOI.Value`.
3. Remove `Enabled = false` from `Effects.Transparency` in `MapOddityConfig`, and remove the Invisible Hallway entry from `RoomsIndexConfig`.

Delete the matching `POIBackups` folder once a revert is done. Both new `RoomsIndexConfig` entries have an empty `Image` until someone uploads photos of the rooms.
