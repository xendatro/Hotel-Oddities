local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)

local WalkieTalkieService = {}

if not RunService:IsClient() then
	return WalkieTalkieService
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("PlayerLocator") :: ScreenGui
local frame = gui:WaitForChild("Mode") :: Frame
local modeLabel = frame:WaitForChild("Mode") :: TextLabel
local toggle = frame:WaitForChild("Toggle") :: ImageButton
local cooldownLabel = frame:FindFirstChild("TeleportCooldown") :: TextLabel?

local SetMode = ReplicatedStorage.Communication.WalkieTalkie.SetMode :: RemoteEvent
local modeIndex = 1
local enabled = false
local emitterConnection: RBXScriptConnection?
local mutedEmitterGroup = `WalkieTalkieMuted_{player.UserId}`

local function isVoiceEligible(): boolean
	local success, result = pcall(
		VoiceChatService.IsVoiceEnabledForUserIdAsync,
		VoiceChatService,
		player.UserId
	)
	return success and result == true
end

local function setMode(index: number, send: boolean)
	modeIndex = (index - 1) % #Config.Modes + 1
	modeLabel.Text = Config.Modes[modeIndex].Label
	if send and enabled then SetMode:FireServer(Config.Modes[modeIndex].Id) end
end

local function muteOwnEmitter(descendant: Instance)
	if descendant.Name == "RadioEmitter" and descendant:IsA("AudioEmitter") then
		descendant.AudioInteractionGroup = mutedEmitterGroup
	end
end

local function watchOwnEmitter(tool: Tool)
	if emitterConnection then emitterConnection:Disconnect() end
	for _, descendant in tool:GetDescendants() do
		muteOwnEmitter(descendant)
	end
	emitterConnection = tool.DescendantAdded:Connect(muteOwnEmitter)
end

toggle.Activated:Connect(function()
	if enabled then setMode(modeIndex + 1, true) end
end)

function WalkieTalkieService:SetEnabled(value: boolean, tool: Tool?)
	if value then
		if not isVoiceEligible() then
			enabled = false
			return
		end
		enabled = true
		if tool then watchOwnEmitter(tool) end
		gui.Enabled = true
		if cooldownLabel then cooldownLabel.Visible = false end
		setMode(modeIndex, true)
	else
		enabled = false
		if emitterConnection then
			emitterConnection:Disconnect()
			emitterConnection = nil
		end
		gui.Enabled = false
	end
end

function WalkieTalkieService:IsEnabled(): boolean
	return enabled
end

setMode(1, false)
gui.Enabled = false

return WalkieTalkieService
