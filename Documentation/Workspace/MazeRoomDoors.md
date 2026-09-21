# Maze room door tags

The door services require `Doorway` and `RoomDoor` on a room doorway model, plus `DoorPart` on its moving leaf BasePart. In `Workspace.Maze15.Doors`, the leaf is `Plane.016` under the `Door` model.

`Doorway_524`, `Doorway_458` and `Doorway_885` belong to upside-down rooms. Their `Door.Plane.016` parts now have the `DoorPart` tag, matching the other room doors.
