local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaosWarningSoundService = {}

if not RunService:IsClient() then
	return ChaosWarningSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local Hallways = require(ReplicatedStorage.Modules.Hallways)

local AMBIENCE_BUS = "SFX"
local AMBIENCE_SILENT_DISTANCE = 60
local ROOM_DOOR_REGION_DISTANCE = 2
local CHECK_INTERVAL = 0.1
local WARNING_TRIGGER_DISTANCE = 24
local WARNING_MARKER = "ChaosWarning"

type WarningRegion = {
	CFrame: CFrame,
	Size: Vector3,
}

type AmbienceSound = {
	Player: AudioPlayer,
}

local LocalPlayer = Players.LocalPlayer
local MapDoors = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Oddities")
	:WaitForChild("MapDoors") :: RemoteEvent
local Sounds = ReplicatedStorage:WaitForChild("Sounds")
local AmbienceFolder = Sounds:WaitForChild("ChaosHallwayAmbience")
local Maze = workspace:WaitForChild("Maze15")
local Rooms = Maze:WaitForChild("Rooms")
local Doors = Maze:WaitForChild("Doors")
local ActiveWarnings: { [number]: WarningRegion } = {}
local AmbienceSounds: { AmbienceSound } = {}
local AmbienceAnchor: Part? = nil
local WasNearWarning = false
local TimeSinceCheck = CHECK_INTERVAL

local function getRoot(): BasePart?
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function closestPoint(region: WarningRegion, position: Vector3): Vector3
	local offset = region.CFrame:PointToObjectSpace(position)
	local half = region.Size / 2
	local closest = Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z)
	)
	return region.CFrame:PointToWorldSpace(closest)
end

local function inRoom(room: Model, position: Vector3): boolean
	local floor = room:FindFirstChild("Floor")
	if not floor or not floor:IsA("BasePart") then return false end

	local offset = floor.CFrame:PointToObjectSpace(position)
	local half = floor.Size / 2
	local height = position.Y - (floor.Position.Y + floor.Size.Y / 2)
	return height >= -4
		and height <= 24
		and math.abs(offset.X) <= half.X
		and math.abs(offset.Z) <= half.Z
end

local function isInAdjacentRoom(region: WarningRegion, position: Vector3): boolean
	for _, room in Rooms:GetChildren() do
		if not room:IsA("Model") or not inRoom(room, position) then continue end

		local id = room.Name:match("^Room_(.+)$")
		local doorway = id and Doors:FindFirstChild("Doorway_" .. id)
		local threshold = doorway and doorway:FindFirstChild("Threshold")
		if threshold and threshold:IsA("BasePart") then
			local distance = (closestPoint(region, threshold.Position) - threshold.Position).Magnitude
			if distance <= ROOM_DOOR_REGION_DISTANCE then return true end
		end
	end
	return false
end

local function isAllowedPosition(region: WarningRegion, position: Vector3): boolean
	if Hallways.At(position, true) then return true end
	return isInAdjacentRoom(region, position)
end

local function sourcePosition(region: WarningRegion): Vector3
	local hallway = Hallways.Nearest(region.CFrame.Position)
	if not hallway then return region.CFrame.Position end

	local along = math.clamp(
		Hallways.Along(hallway, region.CFrame.Position),
		-hallway.HalfLength,
		hallway.HalfLength
	)
	return Hallways.PointAt(hallway, along) + Vector3.yAxis * 2
end

local function nearestWarning(position: Vector3): (Vector3?, number)
	local nearestPoint: Vector3? = nil
	local nearestDistance = math.huge

	for _, region in ActiveWarnings do
		if not isAllowedPosition(region, position) then continue end

		local point = sourcePosition(region)
		local distance = (point - position).Magnitude
		if distance > AMBIENCE_SILENT_DISTANCE then continue end
		if distance < nearestDistance then
			nearestPoint = point
			nearestDistance = distance
		end
	end
	return nearestPoint, nearestDistance
end

local function ensureAnchor(position: Vector3): Part
	if AmbienceAnchor then
		AmbienceAnchor.CFrame = CFrame.new(position)
		return AmbienceAnchor
	end

	local anchor = Instance.new("Part")
	anchor.Name = "ChaosWarningSoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	AmbienceAnchor = anchor
	return anchor
end

local function ensureAmbience(anchor: BasePart)
	if #AmbienceSounds > 0 then return end

	for _, source in AmbienceFolder:GetChildren() do
		if not source:IsA("AudioEmitter") then continue end

		local player = AudioService:Play3DSound(source, anchor, true, AMBIENCE_BUS)
		table.insert(AmbienceSounds, {
			Player = player,
		})
	end
end

local function stopSounds()
	for _, sound in AmbienceSounds do
		if sound.Player.Parent then
			AudioService:StopSound(sound.Player)
		end
	end
	table.clear(AmbienceSounds)

	if AmbienceAnchor then
		AmbienceAnchor:Destroy()
		AmbienceAnchor = nil
	end
end

local function update()
	local root = getRoot()
	local sourcePosition: Vector3? = nil
	local distance = math.huge
	if root then
		sourcePosition, distance = nearestWarning(root.Position)
	end

	local audible = sourcePosition ~= nil
	local near = sourcePosition ~= nil and distance <= WARNING_TRIGGER_DISTANCE

	if audible and sourcePosition then
		local anchor = ensureAnchor(sourcePosition)
		if near and not WasNearWarning then
			AudioService:Play3DSound("ChaosIncoming", anchor, false, AMBIENCE_BUS)
		end
		ensureAmbience(anchor)
	end
	WasNearWarning = near

	if not audible then stopSounds() end
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
	marker: any
)
	if type(token) ~= "number" then return end

	if action == "Start" then
		if marker ~= WARNING_MARKER
			or typeof(boxCFrame) ~= "CFrame"
			or typeof(boxSize) ~= "Vector3"
		then
			return
		end
		ActiveWarnings[token] = {
			CFrame = boxCFrame,
			Size = boxSize,
		}
	elseif action == "Stop" then
		ActiveWarnings[token] = nil
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	TimeSinceCheck += deltaTime
	if TimeSinceCheck < CHECK_INTERVAL then return end

	TimeSinceCheck = 0
	update()
end)

return ChaosWarningSoundService
