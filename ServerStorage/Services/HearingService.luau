local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local HearingConfig = require(ReplicatedStorage.Configs.HearingConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local NoiseService = require(ServerStorage.Services.NoiseService)

local HearingService = {}

export type Ear = {
	GetPosition: () -> Vector3?,
	Accepts: (noise: NoiseService.Noise) -> boolean,
	OnHeard: (noise: NoiseService.Noise, distance: number) -> (),
	IsAlive: () -> boolean,
}

local Ears: { [any]: Ear } = {}

local Travel = CommunicationService.Ensure("Hearing", "Travel") :: RemoteEvent

function HearingService:AddEar(key: any, ear: Ear): () -> ()
	Ears[key] = ear
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
	for key, ear in Ears do
		if not ear.IsAlive() then
			Ears[key] = nil
			continue
		end

		local position = ear.GetPosition()
		if not position then continue end

		local distance = (noise.Position - position).Magnitude
		if distance > noise.Radius then continue end
		if not ear.Accepts(noise) then continue end

		local duration = travelTime(distance)
		announce(noise.Position, key, duration)
		task.delay(duration, function()
			if not ear.IsAlive() then return end
			ear.OnHeard(noise, distance)
		end)
	end
end

NoiseService:Observe(offer)

return HearingService
