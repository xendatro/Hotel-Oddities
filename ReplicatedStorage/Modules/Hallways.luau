--- Reading the corridor a point stands in, off the parts tagged `MazeFloor`.
---
--- The same tag the corridor graph is built from, asked a much smaller question: not how the hotel
--- connects up, but which straight hallway this position is in and which way it runs. That is what
--- anything wanting to lay something *along* a corridor needs -- an effect sized to the width it
--- actually has, kept inside the length it actually has, instead of a guess that works until the
--- player and the thing line up wrongly and it turns up in the next hallway over.
---
--- Shared rather than server-side, because the callers are clients: the corridor an effect is drawn
--- down is a fact about the map, and the map is in `workspace` where every machine can read it.
---
--- A floor part is one straight hallway: `RightVector` runs along its length, `Size.X` is that
--- length and `Size.Z` the width across it. Height is not part of the answer -- floors are one stud
--- of walkable surface with no record of the ceiling over them -- so a caller that needs to span a
--- corridor top to bottom brings its own height.

local CollectionService = game:GetService("CollectionService")

local HALLWAY_TAG = "MazeFloor"
--- How far above its floor a position may be and still count as being in that hallway. Comfortably
--- taller than anything that walks the hotel, and far short of the next storey up.
local HEIGHT_WINDOW = 24
local BELOW_WINDOW = 4 -- and how far under it, for something standing on a rug or a step

export type Hallway = {
	Center: Vector3, -- of the floor part, at the middle of its thickness
	Axis: Vector3, -- unit and horizontal, along the length of the corridor
	Across: Vector3, -- unit and horizontal, square across it
	HalfLength: number,
	HalfWidth: number,
	FloorY: number, -- the walkable surface, which is what a caller stands things on
}

local Hallways = {}

local function toHallway(part: BasePart): Hallway
	local axis = Vector3.new(part.CFrame.RightVector.X, 0, part.CFrame.RightVector.Z).Unit
	return {
		Center = part.Position,
		Axis = axis,
		Across = Vector3.new(-axis.Z, 0, axis.X),
		HalfLength = part.Size.X / 2,
		HalfWidth = part.Size.Z / 2,
		FloorY = part.Position.Y + part.Size.Y / 2,
	}
end

--- Every hallway in the map, in no particular order: the whole corridor network as flat records, for
--- a caller whose question is about all of them rather than about one position.
function Hallways.All(): { Hallway }
	local hallways = {}
	for _, instance in CollectionService:GetTagged(HALLWAY_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(hallways, toHallway(instance :: BasePart))
		end
	end
	return hallways
end

--- The hallway `position` is standing in, or nil where it is in a room, a doorway or anywhere else
--- off the corridor network. Containment rather than nearest: a caller that lands just outside every
--- corridor wants to know that, not to be handed the corridor through the wall.
function Hallways.At(position: Vector3): Hallway?
	for _, hallway in Hallways.All() do
		local height = position.Y - hallway.FloorY
		if height > HEIGHT_WINDOW or height < -BELOW_WINDOW then continue end

		local offset = position - hallway.Center
		if math.abs(offset:Dot(hallway.Axis)) <= hallway.HalfLength
			and math.abs(offset:Dot(hallway.Across)) <= hallway.HalfWidth
		then
			return hallway
		end
	end
	return nil
end

--- The point on `hallway`'s walkable surface closest to `position`: inside the corridor, that is
--- `position` dropped onto the floor; outside it, the nearest point along the floor's edge.
function Hallways.ClosestPoint(hallway: Hallway, position: Vector3): Vector3
	local surface = Vector3.new(hallway.Center.X, hallway.FloorY, hallway.Center.Z)
	local offset = position - surface
	local along = math.clamp(offset:Dot(hallway.Axis), -hallway.HalfLength, hallway.HalfLength)
	local across = math.clamp(offset:Dot(hallway.Across), -hallway.HalfWidth, hallway.HalfWidth)
	return surface + hallway.Axis * along + hallway.Across * across
end

--- The hallway whose floor `position` is nearest to, which for a position inside one is that one.
--- Nearest rather than containment, and so the counterpart to `At`: a caller floating over a wall or
--- out past the edge of the building still gets the corridor it belongs to. Nil only while nothing
--- is tagged at all.
function Hallways.Nearest(position: Vector3): Hallway?
	local nearest = nil :: Hallway?
	local best = math.huge

	for _, hallway in Hallways.All() do
		local distance = (position - Hallways.ClosestPoint(hallway, position)).Magnitude
		if distance < best then
			nearest, best = hallway, distance
		end
	end
	return nearest
end

--- How far `position` is along `hallway` from its middle, signed along the axis.
function Hallways.Along(hallway: Hallway, position: Vector3): number
	return (position - hallway.Center):Dot(hallway.Axis)
end

--- The point `along` studs down the middle of `hallway`, on its floor.
function Hallways.PointAt(hallway: Hallway, along: number): Vector3
	local center = hallway.Center + hallway.Axis * along
	return Vector3.new(center.X, hallway.FloorY, center.Z)
end

return Hallways
