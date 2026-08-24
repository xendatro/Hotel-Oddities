local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local STEALTH = CrouchConfig.Stealth
local DEFAULT_WALK_SPEED = 16
local WALK_RADIUS = 45
local SPRINT_RADIUS = 80
--- Movement stick or WASD held this far. Moving at all is the noise; there is no step timer.
local MOVE_INPUT_MIN = 0.05
local UPDATE_INTERVAL = 0.05
local NOISE_LIFETIME = 1
--- One player only makes so much sound: their footsteps, voice and radio share this
--- interval. A louder noise still cuts in early rather than being masked by a quiet one.
local SOURCE_INTERVAL = 0.4

export type Noise = {
	Position: Vector3,
	Radius: number,
	Source: Player?,
	Sequence: number,
	CreatedAt: number,
}

local NoiseService = {}

local RecentNoises: { Noise } = {}
local LastEmit: { [Player]: { At: number, Radius: number } } = {}
local Observers: { (Noise) -> () } = {}
local Sequence = 0
local Accumulator = 0

local function discardExpired(now: number)
	local expired = 0
	while RecentNoises[expired + 1] and now - RecentNoises[expired + 1].CreatedAt > NOISE_LIFETIME do
		expired += 1
	end
	if expired == 0 then return end

	local count = #RecentNoises
	table.move(RecentNoises, expired + 1, count, 1)
	for index = count - expired + 1, count do
		RecentNoises[index] = nil
	end
end

function NoiseService:Emit(
	position: Vector3,
	radius: number,
	source: Player?,
	ignoreSourceInterval: boolean?
): Noise?
	local now = os.clock()
	if source and not ignoreSourceInterval then
		local last = LastEmit[source]
		if last and now - last.At < SOURCE_INTERVAL and radius <= last.Radius then
			return nil
		end
		LastEmit[source] = { At = now, Radius = radius }
	end

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
		local humanoid = CharacterService.GetAliveHumanoid(player)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (humanoid and root) then continue end
		if humanoid.FloorMaterial == Enum.Material.Air then continue end
		if humanoid.MoveDirection.Magnitude < MOVE_INPUT_MIN then continue end

		local crouching = character:GetAttribute(STEALTH.Attribute) == true
		if crouching and STEALTH.NoiseRadius <= 0 then continue end

		local boosted = player:GetAttribute("SpeedBoostSpeed")
		local unsprinted = if type(boosted) == "number" then boosted else DEFAULT_WALK_SPEED
		local sprinting = not crouching and humanoid.WalkSpeed > unsprinted + 0.01
		local radius = if crouching
			then STEALTH.NoiseRadius
			elseif sprinting then SPRINT_RADIUS
			else WALK_RADIUS
		NoiseService:Emit(root.Position, radius, player)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastEmit[player] = nil
end)

return NoiseService
