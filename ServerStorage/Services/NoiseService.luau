--- Server-owned sounds that enemies may react to. A noise is a short-lived fact about a position,
--- not necessarily a `Sound` Instance: footsteps publish here directly, and a shovel, door or trap
--- can do the same later without making an enemy inspect client audio.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DEFAULT_WALK_SPEED = 16
local WALK_RADIUS = 45
local SPRINT_RADIUS = 80
local WALK_INTERVAL = 0.45
local SPRINT_INTERVAL = 0.3
local MOVEMENT_SPEED_MIN = 1
local UPDATE_INTERVAL = 0.05
local NOISE_LIFETIME = 1

export type Noise = {
	Position: Vector3,
	Radius: number,
	Source: Player?,
	Sequence: number,
	CreatedAt: number,
}

local NoiseService = {}

local RecentNoises: { Noise } = {}
local LastFootstepAt: { [Player]: number } = {}
local Sequence = 0
local Accumulator = 0

local function horizontalMagnitude(vector: Vector3): number
	return Vector3.new(vector.X, 0, vector.Z).Magnitude
end

local function discardExpired(now: number)
	while RecentNoises[1] and now - RecentNoises[1].CreatedAt > NOISE_LIFETIME do
		table.remove(RecentNoises, 1)
	end
end

--- Publishes one noise. `source` is nil for world sounds that do not belong to a player.
function NoiseService:Emit(position: Vector3, radius: number, source: Player?): Noise
	local now = os.clock()
	Sequence += 1
	discardExpired(now)

	local noise = {
		Position = position,
		Radius = radius,
		Source = source,
		Sequence = Sequence,
		CreatedAt = now,
	}
	table.insert(RecentNoises, noise)
	return noise
end

--- Newest still-live noise after `sequence` that reaches `origin` and satisfies `predicate`.
function NoiseService:GetLatest(
	origin: Vector3,
	sequence: number,
	predicate: ((Noise) -> boolean)?
): Noise?
	local now = os.clock()
	discardExpired(now)

	for index = #RecentNoises, 1, -1 do
		local noise = RecentNoises[index]
		if noise.Sequence > sequence
			and (noise.Position - origin).Magnitude <= noise.Radius
			and (not predicate or predicate(noise))
		then
			return noise
		end
	end
	return nil
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < UPDATE_INTERVAL then return end
	Accumulator = 0

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (humanoid and root and humanoid.Health > 0) then continue end
		if humanoid.FloorMaterial == Enum.Material.Air then continue end
		if horizontalMagnitude(root.AssemblyLinearVelocity) < MOVEMENT_SPEED_MIN then continue end

		local sprinting = humanoid.WalkSpeed > DEFAULT_WALK_SPEED
		local interval = if sprinting then SPRINT_INTERVAL else WALK_INTERVAL
		local now = os.clock()
		if now - (LastFootstepAt[player] or 0) < interval then continue end

		LastFootstepAt[player] = now
		NoiseService:Emit(root.Position, if sprinting then SPRINT_RADIUS else WALK_RADIUS, player)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastFootstepAt[player] = nil
end)

return NoiseService
