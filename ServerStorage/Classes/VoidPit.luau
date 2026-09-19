local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)
local DeathService = require(ServerStorage.Services.DeathService)

local DEFAULT_CAUSE = "HallwayVoid"

local VoidPit = {}
VoidPit.__index = VoidPit

local function contains(part: BasePart, position: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPosition.X) <= half.X
		and math.abs(localPosition.Y) <= half.Y
		and math.abs(localPosition.Z) <= half.Z
end

local function setUpConnections(self)
	self.Connections = {}

	local part = self.Instance

	self.Connections.Heartbeat = RunService.Heartbeat:Connect(function()
		if not part:IsDescendantOf(workspace) then return end

		for _, player in Players:GetPlayers() do
			local root = CharacterService.GetAliveRoot(player)
			if not root or not contains(part, root.Position) then continue end

			local character = root.Parent :: Model
			local humanoid = CharacterService.GetHumanoid(character)
			if humanoid and not Vanished.Is(character) then
				DeathService:RecordCause(player, self.Cause)
				humanoid.Health = 0
			end
		end
	end)
end

function VoidPit.new(instance: Instance)
	local self = setmetatable({}, VoidPit)

	self.Instance = instance
	self.Connections = {}

	local cause = instance:GetAttribute("DeathCause")
	self.Cause = if type(cause) == "string" and cause ~= "" then cause else DEFAULT_CAUSE

	if instance:IsA("BasePart") then
		setUpConnections(self)
	end

	return self
end

function VoidPit:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
end

return VoidPit
