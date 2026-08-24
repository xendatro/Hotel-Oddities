local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LookConfig = require(ReplicatedStorage.Configs.LookConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local LookService = {}

local PITCH_ATTRIBUTE = "LookPitch"
local YAW_ATTRIBUTE = "LookYaw"
local MIRROR_ATTRIBUTE = "LookMirrorUserId"
local ENEMY_TAG = "Enemy"

local Update = CommunicationService.Ensure("Look", "Update")

local lastReportAt: { [Player]: number } = {}

local EnemyModels: { [Model]: true } = {}

for _, model in CollectionService:GetTagged(ENEMY_TAG) do
	if model:IsA("Model") then
		EnemyModels[model] = true
	end
end
CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(function(model)
	if model:IsA("Model") then
		EnemyModels[model] = true
	end
end)
CollectionService:GetInstanceRemovedSignal(ENEMY_TAG):Connect(function(model)
	EnemyModels[model] = nil
end)

local function setAttributeIfChanged(instance: Instance, attribute: string, value: number)
	if instance:GetAttribute(attribute) ~= value then
		instance:SetAttribute(attribute, value)
	end
end

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

CharacterService.CleanupOnLeave(lastReportAt)

local nextMimicUpdate = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextMimicUpdate then return end
	nextMimicUpdate = now + LookConfig.MimicUpdateInterval

	for model in EnemyModels do
		local userId = model:GetAttribute(MIRROR_ATTRIBUTE)
		if type(userId) ~= "number" then
			if model:GetAttribute(PITCH_ATTRIBUTE) then
				setAttributeIfChanged(model, PITCH_ATTRIBUTE, 0)
				setAttributeIfChanged(model, YAW_ATTRIBUTE, 0)
			end
			continue
		end

		local target = Players:GetPlayerByUserId(userId)
		local character = target and target.Character
		local pitch = character and character:GetAttribute(PITCH_ATTRIBUTE)
		setAttributeIfChanged(model, PITCH_ATTRIBUTE, if type(pitch) == "number" then pitch else 0)
		setAttributeIfChanged(model, YAW_ATTRIBUTE, 0)
	end
end)

return LookService
