# ReplicatedStorage / Tools

The five new inventory tool templates are stored in `ReplicatedStorage.Tools`. Each is a `Tool` with a single placeholder `Handle` part, the standard `Object` and `Tool` tags, and a tool-specific CollectionService tag used by `ToolService`.

### Big Head
Triggers the `HeadSize` player oddity on the holder.

### Big Character
Triggers the `Size` player oddity at a fixed `1.1` scale on the holder.

### Small Character
Triggers the `Size` player oddity at a fixed `0.9` scale on the holder.

### Transparency
Triggers the player `Transparency` oddity on the holder.

### Random Oddity
Triggers one of the four player-oddity item effects with equal probability.

## Colored computer chips
Blue Computer Chip, Red Computer Chip, Green Computer Chip, Yellow Computer Chip and Purple Computer Chip are Studio-authored clones of the existing Computer Chip template under ReplicatedStorage.Tools. Each retains the original chip mesh and grip, is tinted to its color, and carries Object, Tool and its exact tool-name tag. ComputerChipColor stores the color key. Templates cannot be dropped and have a color-specific tooltip.

These templates and the five ChipColorMarker nameplates are non-script instances authored through Studio MCP; script-folder sync does not serialize them. Matching computers are the five tagged models in Room_357, Room_419, Room_466, Room_599 and Room_998. The untagged Workspace.ComputerModel source template is unchanged. Config-driven behavior and the color mapping live in ComputerChipConfig; the existing computer icon is reused for the colored effects HUD countdown.
