local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local ChaosTrackerService = {}

local CHAOS_TAG = "Chaos"

export type Mover = {
	Model: Model,
	Position: Vector3,
	Look: Vector3,
}

local Movers: { Mover } = {}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

ChaosTrackerService.Tag = CHAOS_TAG

function ChaosTrackerService:GetMovers(): { Mover }
	table.clear(Movers)

	for _, instance in CollectionService:GetTagged(CHAOS_TAG) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then continue end

		local pivot = CharacterService.GetStreamedPivot(instance :: Model)
		if not pivot then continue end
		local look = horizontal(pivot.LookVector)
		if look.Magnitude < 1e-3 then continue end

		table.insert(Movers, {
			Model = instance :: Model,
			Position = pivot.Position,
			Look = look.Unit,
		})
	end

	return Movers
end

function ChaosTrackerService.AlongTo(mover: Mover, point: Vector3): number
	return horizontal(point - mover.Position):Dot(mover.Look)
end

function ChaosTrackerService.RangeTo(mover: Mover, point: Vector3): number
	return horizontal(point - mover.Position).Magnitude
end

return ChaosTrackerService
