local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaosWarningSoundService = {}

if not RunService:IsClient() then
	return ChaosWarningSoundService
end

local AmbienceService = require(ReplicatedStorage.Services.AmbienceService)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local ChaosLights = require(ReplicatedStorage.Services.ChaosLightService)
local Config = require(ReplicatedStorage.Configs.ChaosWarningConfig)

local WARNING_MARKER = "ChaosWarning"
local SUPPRESSOR_KEY = "ChaosWarning"

type WarningRegion = {
	CFrame: CFrame,
	Size: Vector3,
	ArrivalAtStart: number,
	ArrivalAtFinish: number,
	WarningTime: number,
	Run: number,
}

type Voice = {
	Player: AudioPlayer,
	Full: number,
	Gain: number,
}

local LocalPlayer = Players.LocalPlayer
local MapDoors = CommunicationService.Get("Oddities", "MapDoors") :: RemoteEvent
local RequestMapDoors = CommunicationService.Get("Oddities", "RequestMapDoors") :: RemoteEvent
local Sounds = ReplicatedStorage:WaitForChild("Sounds")
local AmbienceFolder = Sounds:WaitForChild(Config.AmbienceFolder)

local ActiveWarnings: { [number]: WarningRegion } = {}
local Voices: { Voice } = {}
local Anchor: Part? = nil
local AnchorPlaced = false
local StungRuns: { [number]: true } = {}
local RedLights: { [Model]: true } = {}

local TargetPoint: Vector3? = nil
local TargetGain = 0
local SilentFor = 0
local TimeSinceCheck = math.huge

ChaosLights:OnRedChanged(function(model: Model, red: boolean)
	RedLights[model] = if red then true else nil
end)

local function nearestRed(position: Vector3, range: number): (Vector3?, number)
	local closest: Vector3? = nil
	local best = range
	for model in RedLights do
		if not model.Parent then
			RedLights[model] = nil
			continue
		end

		local point = model:GetPivot().Position
		local distance = (point - position).Magnitude
		if distance <= best then
			closest, best = point, distance
		end
	end
	return closest, best
end

-- The gate would otherwise be a step: full volume right up to RedHearingRange
-- and then a fade from full. Ramping over the last RedFadeBand studs means the
-- bed is already near silent by the time the gate closes.
local function edgeGain(distance: number): number
	local band = math.max(Config.RedFadeBand, 1e-3)
	return math.clamp((Config.RedHearingRange - distance) / band, 0, 1)
end

local function centreAt(region: WarningRegion, height: number, along: number): Vector3
	local half = region.Size / 2
	return region.CFrame:PointToWorldSpace(Vector3.new(0, math.clamp(height, -half.Y, half.Y), along))
end

local function insideRegion(region: WarningRegion, offset: Vector3): boolean
	local half = region.Size / 2
	return math.abs(offset.X) <= half.X
		and math.abs(offset.Y) <= half.Y
		and math.abs(offset.Z) <= half.Z
end

local function listenTo(region: WarningRegion, position: Vector3): (Vector3, number, boolean)
	local offset = region.CFrame:PointToObjectSpace(position)
	local half = region.Size / 2
	local along = math.clamp(offset.Z, -half.Z, half.Z)
	local point = centreAt(region, offset.Y, along)
	return point, (point - position).Magnitude, insideRegion(region, offset)
end

local function writeGain(voice: Voice)
	voice.Player.Volume = voice.Full * voice.Gain
end

local function rampGain(voice: Voice, target: number, delta: number)
	local stepped = voice.Gain + (target - voice.Gain) * delta
	voice.Gain = if math.abs(target - stepped) <= Config.GainSnap then target else stepped
	writeGain(voice)
end

local function ensureAnchor(position: Vector3): Part
	local anchor = Anchor
	if anchor then return anchor end

	anchor = Instance.new("Part")
	anchor.Name = "ChaosWarningSoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	Anchor = anchor
	AnchorPlaced = true

	for _, source in AmbienceFolder:GetChildren() do
		if not source:IsA("AudioEmitter") then continue end

		local player = AudioService:Create3DSound(source, anchor, true, Config.AmbienceBus)
		local voice: Voice = { Player = player, Full = player.Volume, Gain = 0 }
		writeGain(voice)
		player:Play()
		table.insert(Voices, voice)
	end
	return anchor
end

local function teardown()
	table.clear(Voices)

	if Anchor then
		Anchor:Destroy()
		Anchor = nil
	end
	AnchorPlaced = false
	TargetPoint = nil
	TargetGain = 0
	SilentFor = 0
	AmbienceService:Suppress(SUPPRESSOR_KEY, false)
end

local function silence()
	TargetPoint, TargetGain = nil, 0
	CurrentRun = nil
	AmbienceService:Suppress(SUPPRESSOR_KEY, false)
end

local function resolve()
	if not next(ActiveWarnings) then
		silence()
		return
	end

	local root = CharacterService.GetAliveRoot(LocalPlayer)
	if not root then
		silence()
		return
	end

	local position = root.Position
	local red, redDistance = nearestRed(position, Config.RedHearingRange)
	if not red then
		silence()
		return
	end

	local bestPoint: Vector3? = nil
	local bestRun: number? = nil
	local bestDistance = math.huge
	local bestInside = false
	for _, region in ActiveWarnings do
		local point, distance, inside = listenTo(region, position)
		if distance >= bestDistance then continue end

		bestPoint, bestRun, bestDistance, bestInside = point, region.Run, distance, inside
	end

	if not bestPoint or bestDistance > Config.RedHearingRange then
		bestPoint = red
	end

	TargetPoint = bestPoint
	TargetGain = edgeGain(redDistance)
	AmbienceService:Suppress(SUPPRESSOR_KEY, bestInside)

	if bestRun and not StungRuns[bestRun] then
		StungRuns[bestRun] = true
		AudioService:Play3DSound(Config.IncomingSound, ensureAnchor(bestPoint), false, Config.AmbienceBus)
	end
end

local function step(deltaTime: number)
	TimeSinceCheck += deltaTime
	if TimeSinceCheck >= Config.CheckInterval then
		TimeSinceCheck = 0
		resolve()
	end

	local target = TargetPoint
	if target then
		local anchor = ensureAnchor(target)
		local current = anchor.Position
		anchor.CFrame = if AnchorPlaced and (current - target).Magnitude <= Config.AnchorSnapDistance
			then CFrame.new(current:Lerp(target, math.min(deltaTime * Config.AnchorLerpSpeed, 1)))
			else CFrame.new(target)
		AnchorPlaced = true
	end

	if #Voices == 0 then return end

	local speed
	if TargetGain > 0 then
		speed = Config.FadeInSpeed
	else
		speed = Config.FadeOutSpeed
	end

	local delta = math.min(deltaTime * speed, 1)
	local loudest = 0
	for _, voice in Voices do
		rampGain(voice, TargetGain, delta)
		loudest = math.max(loudest, voice.Gain)
	end

	if loudest > 0 or TargetGain > 0 then
		SilentFor = 0
		return
	end

	SilentFor += deltaTime
	if SilentFor >= Config.ReleaseDelay then
		teardown()
	end
end

MapDoors.OnClientEvent:Connect(function(
	action: any,
	token: any,
	boxCFrame: any,
	boxSize: any,
	_speed: any,
	_mode: any,
	_closeSpeed: any,
	_intervalMin: any,
	_intervalMax: any,
	marker: any,
	arrivalAtStart: any,
	arrivalAtFinish: any,
	warningTime: any,
	run: any
)
	if type(token) ~= "number" then return end

	if action == "Start" then
		if marker ~= WARNING_MARKER
			or typeof(boxCFrame) ~= "CFrame"
			or typeof(boxSize) ~= "Vector3"
			or type(arrivalAtStart) ~= "number"
			or type(arrivalAtFinish) ~= "number"
			or type(warningTime) ~= "number"
			or type(run) ~= "number"
		then
			return
		end
		ActiveWarnings[token] = {
			CFrame = boxCFrame,
			Size = boxSize,
			ArrivalAtStart = arrivalAtStart,
			ArrivalAtFinish = arrivalAtFinish,
			WarningTime = warningTime,
			Run = run,
		}
	elseif action == "Stop" then
		local stopped = ActiveWarnings[token]
		ActiveWarnings[token] = nil
		if not stopped then return end

		for _, region in ActiveWarnings do
			if region.Run == stopped.Run then return end
		end
		StungRuns[stopped.Run] = nil
	end
end)

RunService.Heartbeat:Connect(step)

RequestMapDoors:FireServer()

return ChaosWarningSoundService
