local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LookConfig = require(ReplicatedStorage.Configs.LookConfig)

local LookService = {}

local PITCH_ATTRIBUTE = "LookPitch"
local YAW_ATTRIBUTE = "LookYaw"
local MIRROR_ATTRIBUTE = "LookMirrorUserId"

local communication = ReplicatedStorage:FindFirstChild("Communication")
if not communication then
	communication = Instance.new("Folder")
	communication.Name = "Communication"
	communication.Parent = ReplicatedStorage
end

local folder = communication:FindFirstChild("Look")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Look"
	folder.Parent = communication
end

local Update = folder:FindFirstChild("Update") :: RemoteEvent?
if not Update then
	Update = Instance.new("RemoteEvent")
	Update.Name = "Update"
	Update.Parent = folder
end

local lastReportAt: { [Player]: number } = {}

Update.OnServerEvent:Connect(function(player: Player, pitch: any, yaw: any)
	if type(pitch) ~= "number" or type(yaw) ~= "number" then return end
	if pitch ~= pitch or yaw ~= yaw then return end

	local now = os.clock()
	if now - (lastReportAt[player] or 0) < LookConfig.SendInterval * 0.5 then return end
	lastReportAt[player] = now

	local character = player.Character
	if not character then return end

	character:SetAttribute(PITCH_ATTRIBUTE, math.clamp(pitch, -LookConfig.MaxPitch, LookConfig.MaxPitch))
	character:SetAttribute(YAW_ATTRIBUTE, math.clamp(yaw, -LookConfig.MaxYaw, LookConfig.MaxYaw))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastReportAt[player] = nil
end)

local nextMimicUpdate = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextMimicUpdate then return end
	nextMimicUpdate = now + LookConfig.MimicUpdateInterval

	for _, model in CollectionService:GetTagged("Enemy") do
		local userId = model:GetAttribute(MIRROR_ATTRIBUTE)
		if type(userId) ~= "number" then
			if model:GetAttribute(PITCH_ATTRIBUTE) then
				model:SetAttribute(PITCH_ATTRIBUTE, 0)
				model:SetAttribute(YAW_ATTRIBUTE, 0)
			end
			continue
		end

		local target = Players:GetPlayerByUserId(userId)
		local character = target and target.Character
		local pitch = character and character:GetAttribute(PITCH_ATTRIBUTE)
		model:SetAttribute(PITCH_ATTRIBUTE, if type(pitch) == "number" then pitch else 0)
		model:SetAttribute(YAW_ATTRIBUTE, 0)
	end
end)

return LookService
