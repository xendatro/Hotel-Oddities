local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local HearingConfig = require(ReplicatedStorage.Configs.HearingConfig)
local NoiseService = require(ServerStorage.Services.NoiseService)

local HearingService = {}

export type Ear = {
	GetPosition: () -> Vector3?,
	GetCooldown: (source: Player?) -> number,
	Accepts: (noise: NoiseService.Noise) -> boolean,
	OnHeard: (noise: NoiseService.Noise, distance: number) -> (),
	IsAlive: () -> boolean,
}

type Registration = {
	Ear: Ear,
	LastHeardAt: { [any]: number },
}

local Ears: { [any]: Registration } = {}

local communication = ReplicatedStorage:FindFirstChild("Communication")
if not communication then
	communication = Instance.new("Folder")
	communication.Name = "Communication"
	communication.Parent = ReplicatedStorage
end

local folder = communication:FindFirstChild("Hearing")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Hearing"
	folder.Parent = communication
end

local Travel = folder:FindFirstChild("Travel") :: RemoteEvent?
if not Travel then
	Travel = Instance.new("RemoteEvent")
	Travel.Name = "Travel"
	Travel.Parent = folder
end

function HearingService:AddEar(key: any, ear: Ear): () -> ()
	Ears[key] = { Ear = ear, LastHeardAt = {} }
	return function()
		Ears[key] = nil
	end
end

local function travelTime(distance: number): number
	return math.clamp(
		distance / HearingConfig.TravelSpeed,
		HearingConfig.MinTravelTime,
		HearingConfig.MaxTravelTime
	)
end

local function announce(origin: Vector3, key: any, duration: number)
	if typeof(key) == "Instance" then
		Travel:FireAllClients(origin, key, duration)
	end
end

local function offer(noise: NoiseService.Noise)
	local now = os.clock()

	for key, registration in Ears do
		local ear = registration.Ear
		if not ear.IsAlive() then
			Ears[key] = nil
			continue
		end

		local position = ear.GetPosition()
		if not position then continue end

		local distance = (noise.Position - position).Magnitude
		if distance > noise.Radius then continue end
		if not ear.Accepts(noise) then continue end

		local sourceKey = noise.Source or "World"
		local cooldown = ear.GetCooldown(noise.Source)
		if now - (registration.LastHeardAt[sourceKey] or -math.huge) < cooldown then continue end
		registration.LastHeardAt[sourceKey] = now

		local duration = travelTime(distance)
		announce(noise.Position, key, duration)
		task.delay(duration, function()
			if not ear.IsAlive() then return end
			ear.OnHeard(noise, distance)
		end)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	for _, registration in Ears do
		registration.LastHeardAt[player] = nil
	end
end)

NoiseService:Observe(offer)

return HearingService
