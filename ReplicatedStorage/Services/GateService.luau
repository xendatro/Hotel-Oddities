local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GateService = {}

if not RunService:IsClient() then
	return GateService
end

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GateConfig = require(ReplicatedStorage.Configs.GateConfig)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local TagService = require(ReplicatedStorage.Services.TagService)

local UnlockRemote = CommunicationService.Get(GateConfig.Remotes.Folder, GateConfig.Remotes.Unlock)
local player = Players.LocalPlayer

local States: { [Model]: true } = {}
local LastUnlock = 0

local function hasKey(): boolean
	local character = player.Character
	local tool = character and character:FindFirstChild(GateConfig.ToolName)
	return tool ~= nil and tool:IsA("Tool")
end

local function register(model: Model): Model?
	if not model:IsA("Model") then return nil end

	States[model] = true
	Interaction:Register(model, {
		Prompt = GateConfig.Prompt,
		TextWidth = GateConfig.TextWidth,
		Reach = GateConfig.Targeting.Reach,
		CanSelect = function()
			return hasKey()
		end,
		OnActivated = function(target: Model)
			local now = os.clock()
			if now - LastUnlock < GateConfig.Cooldown or not hasKey() then return false end
			LastUnlock = now
		local remote = UnlockRemote :: RemoteEvent
		remote:FireServer(target)
			return true
		end,
	})
	return model
end

local function unregister(model: Model)
	States[model] = nil
	Interaction:Unregister(model)
end

TagService:Listen(GateConfig.Tag, register, unregister, workspace)

return GateService
