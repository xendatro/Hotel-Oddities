local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)

local STEALTH = CrouchConfig.Stealth
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
local Observers: { (Noise) -> () } = {}
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
	for _, observer in Observers do
		task.spawn(observer, noise)
	end
	return noise
end

function NoiseService:Observe(observer: (Noise) -> ()): () -> ()
	table.insert(Observers, observer)
	return function()
		local index = table.find(Observers, observer)
		if index then
			table.remove(Observers, index)
		end
	end
end

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

		local crouching = character:GetAttribute(STEALTH.Attribute) == true
		if crouching and STEALTH.NoiseRadius <= 0 then
			LastFootstepAt[player] = os.clock()
			continue
		end

		local sprinting = not crouching and humanoid.WalkSpeed > DEFAULT_WALK_SPEED
		local interval = if sprinting then SPRINT_INTERVAL else WALK_INTERVAL
		local now = os.clock()
		if now - (LastFootstepAt[player] or 0) < interval then continue end

		LastFootstepAt[player] = now
		local radius = if crouching
			then STEALTH.NoiseRadius
			elseif sprinting then SPRINT_RADIUS
			else WALK_RADIUS
		NoiseService:Emit(root.Position, radius, player)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastFootstepAt[player] = nil
end)

return NoiseService
