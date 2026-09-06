local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaosWarningSoundService = {}

if not RunService:IsClient() then
	return ChaosWarningSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local Config = require(ReplicatedStorage.Configs.ChaosWarningConfig)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)

local WARNING_MARKER = "ChaosWarning"
local ROOM_TAG = "Room"
local DOORWAY_TAG = "Doorway"
local ROOM_DOOR_TAG = "RoomDoor"
local THRESHOLD_NAME = "Threshold"

type WarningRegion = {
	CFrame: CFrame,
	Size: Vector3,
	ArrivalAtStart: number,
	ArrivalAtFinish: number,
	WarningTime: number,
}

type RoomEntry = {
	Model: Model,
	CFrame: CFrame,
	HalfSize: Vector3,
	Threshold: Vector3?,
}

type Voice = {
	Player: AudioPlayer,
	Emitter: AudioEmitter,
	Gain: number,
	Applied: number,
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
local StungTokens: { [number]: true } = {}

local TargetPoint: Vector3? = nil
local TargetGain = 0
local PassFading = false
local SilentFor = 0
local TimeSinceCheck = math.huge

local Rooms: { RoomEntry } = {}
local RoomsDirty = true
local CurrentRoom: RoomEntry? = nil

local function buildRooms()
	local thresholds: { [string]: Vector3 } = {}
	for _, instance in CollectionService:GetTagged(DOORWAY_TAG) do
		if not instance:IsA("Model") or not instance:HasTag(ROOM_DOOR_TAG) then continue end

		local suffix = instance.Name:match("^Doorway_(.+)$")
		if not suffix then continue end

		local threshold = instance:FindFirstChild(THRESHOLD_NAME, true)
		thresholds[suffix] = if threshold and threshold:IsA("BasePart")
			then threshold.Position
			else instance:GetPivot().Position
	end

	table.clear(Rooms)
	for _, instance in CollectionService:GetTagged(ROOM_TAG) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then continue end

		local room = instance :: Model
		local cframe, size = room:GetBoundingBox()
		local suffix = room.Name:match("^Room_(.+)$")
		table.insert(Rooms, {
			Model = room,
			CFrame = cframe,
			HalfSize = size / 2,
			Threshold = if suffix then thresholds[suffix] else nil,
		})
	end

	CurrentRoom = nil
	RoomsDirty = false
end

local function insideRoom(entry: RoomEntry, position: Vector3): boolean
	local offset = entry.CFrame:PointToObjectSpace(position)
	local half = entry.HalfSize
	return math.abs(offset.X) <= half.X
		and math.abs(offset.Y) <= half.Y
		and math.abs(offset.Z) <= half.Z
end

local function roomAt(position: Vector3): RoomEntry?
	if RoomsDirty then buildRooms() end

	local cached = CurrentRoom
	if cached and cached.Model.Parent and insideRoom(cached, position) then return cached end

	for _, entry in Rooms do
		if insideRoom(entry, position) then
			CurrentRoom = entry
			return entry
		end
	end

	CurrentRoom = nil
	return nil
end

local function boxPoint(region: WarningRegion, offset: Vector3): Vector3
	local half = region.Size / 2
	return region.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z)
	))
end

local function centreAt(region: WarningRegion, height: number, along: number): Vector3
	local half = region.Size / 2
	return region.CFrame:PointToWorldSpace(Vector3.new(0, math.clamp(height, -half.Y, half.Y), along))
end

local function arrivalAt(region: WarningRegion, along: number): number
	local half = region.Size.Z / 2
	if half <= 0 then return region.ArrivalAtStart end

	local alpha = math.clamp((half - along) / (half * 2), 0, 1)
	return region.ArrivalAtStart + (region.ArrivalAtFinish - region.ArrivalAtStart) * alpha
end

local function approachSign(region: WarningRegion): number
	return if region.ArrivalAtFinish >= region.ArrivalAtStart then 1 else -1
end

local function insideRegion(region: WarningRegion, offset: Vector3): boolean
	local half = region.Size / 2
	return math.abs(offset.X) <= half.X
		and math.abs(offset.Y) <= half.Y
		and math.abs(offset.Z) <= half.Z
end

local function listenTo(
	region: WarningRegion,
	position: Vector3,
	inHallway: boolean,
	room: RoomEntry?
): (Vector3?, number, number)
	local offset = region.CFrame:PointToObjectSpace(position)
	local half = region.Size / 2
	local along = math.clamp(offset.Z, -half.Z, half.Z)

	if insideRegion(region, offset) or (inHallway
		and (boxPoint(region, offset) - position).Magnitude <= Config.AdjacentHallwayRange)
	then
		local nearest = centreAt(region, offset.Y, along)
		local gap = (nearest - position).Magnitude
		local slide = math.sqrt(math.max(Config.MinSourceDistance ^ 2 - gap * gap, 0))
		local source = centreAt(region, offset.Y, along + approachSign(region) * slide)
		return source, gap, arrivalAt(region, along)
	end

	local threshold = room and room.Threshold
	if threshold then
		local doorOffset = region.CFrame:PointToObjectSpace(threshold)
		if (boxPoint(region, doorOffset) - threshold).Magnitude <= Config.RoomDoorRange then
			local doorAlong = math.clamp(doorOffset.Z, -half.Z, half.Z)
			local source = centreAt(region, doorOffset.Y, doorAlong)
			return source, (source - position).Magnitude, arrivalAt(region, doorAlong)
		end
	end

	return nil, 0, 0
end

local function gainFor(distance: number): number
	if distance <= Config.FullVolumeDistance then return 1 end
	if distance >= Config.SilentDistance then return 0 end

	local alpha = (distance - Config.FullVolumeDistance)
		/ (Config.SilentDistance - Config.FullVolumeDistance)
	return 1 - alpha * alpha
end

local function writeGain(voice: Voice)
	voice.Applied = voice.Gain
	voice.Emitter:SetDistanceAttenuation({
		[0] = voice.Gain,
		[Config.AttenuationRange] = voice.Gain,
	})
end

local function rampGain(voice: Voice, target: number, delta: number)
	local stepped = voice.Gain + (target - voice.Gain) * delta
	voice.Gain = if math.abs(target - stepped) <= Config.GainSnap then target else stepped

	if voice.Gain == target or math.abs(voice.Gain - voice.Applied) >= Config.GainEpsilon then
		writeGain(voice)
	end
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

		local player = AudioService:Play3DSound(source, anchor, true, Config.AmbienceBus)
		local voice: Voice = {
			Player = player,
			Emitter = player.Parent :: AudioEmitter,
			Gain = 0,
			Applied = 0,
		}
		writeGain(voice)
		table.insert(Voices, voice)
	end
	return anchor
end

local function teardown()
	for _, voice in Voices do
		if voice.Player.Parent then
			AudioService:StopSound(voice.Player)
		end
	end
	table.clear(Voices)

	if Anchor then
		Anchor:Destroy()
		Anchor = nil
	end
	AnchorPlaced = false
	TargetPoint = nil
	TargetGain = 0
	PassFading = false
	SilentFor = 0
end

local function resolve()
	if not next(ActiveWarnings) then
		TargetPoint, TargetGain = nil, 0
		return
	end

	local root = CharacterService.GetAliveRoot(LocalPlayer)
	if not root then
		TargetPoint, TargetGain = nil, 0
		return
	end

	local position = root.Position
	local inHallway = Hallways.At(position, true) ~= nil
	local room = if inHallway then nil else roomAt(position)
	local now = workspace:GetServerTimeNow()

	local bestPoint: Vector3? = nil
	local bestToken: number? = nil
	local bestGain = 0
	local bestLead = math.huge
	for token, region in ActiveWarnings do
		local point, distance, arrival = listenTo(region, position, inHallway, room)
		if not point then continue end

		local lead = arrival - now
		if lead <= 0 or lead > region.WarningTime then continue end

		local gain = gainFor(distance)
		if gain <= 0 or lead >= bestLead then continue end
		bestPoint, bestToken, bestGain, bestLead = point, token, gain, lead
	end

	TargetPoint = bestPoint
	if bestPoint then
		local duck = math.clamp(bestLead / Config.PassFadeLead, 0, 1)
		TargetGain = bestGain * duck
		PassFading = duck < 1
	else
		TargetGain = 0
	end

	if bestToken and not StungTokens[bestToken] then
		StungTokens[bestToken] = true
		AudioService:Play2DSound(Config.IncomingSound, false, Config.AmbienceBus)
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
	if PassFading then
		speed = Config.PassFadeSpeed
	elseif TargetGain > 0 then
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
	warningTime: any
)
	if type(token) ~= "number" then return end

	if action == "Start" then
		if marker ~= WARNING_MARKER
			or typeof(boxCFrame) ~= "CFrame"
			or typeof(boxSize) ~= "Vector3"
			or type(arrivalAtStart) ~= "number"
			or type(arrivalAtFinish) ~= "number"
			or type(warningTime) ~= "number"
		then
			return
		end
		ActiveWarnings[token] = {
			CFrame = boxCFrame,
			Size = boxSize,
			ArrivalAtStart = arrivalAtStart,
			ArrivalAtFinish = arrivalAtFinish,
			WarningTime = warningTime,
		}
	elseif action == "Stop" then
		ActiveWarnings[token] = nil
		StungTokens[token] = nil
	end
end)

for _, tag in { ROOM_TAG, DOORWAY_TAG } do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function()
		RoomsDirty = true
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function()
		RoomsDirty = true
	end)
end

RunService.Heartbeat:Connect(step)

RequestMapDoors:FireServer()

return ChaosWarningSoundService
