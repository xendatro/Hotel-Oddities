local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.VoiceDebugConfig)
local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local VoiceDebugService = {}

if not (FLAGS.VoiceDebug and RunService:IsClient()) then
	return VoiceDebugService
end

local panel = DebugPanel.new("voice + walkie volumes", Config.ToggleKey)
local resets: { () -> () } = {}

local function applyVolume(entry: Config.Entry, value: number)
	entry.Table[entry.Key] = value

	if entry.Id == "ProximityVoice" then
		local source = game:GetService("Players").LocalPlayer:FindFirstChild("AudioDeviceInput")
		if source then source.Volume = value end
		return
	end

	for _, instance in game:GetService("Players").LocalPlayer:GetDescendants() do
		if instance.Name == "RadioVoiceVolume" then
			(instance :: AudioFader).Volume = entry.Id == "RadioVoice" and value or instance.Volume
		elseif instance.Name == "RadioTaggedSoundVolume" then
			(instance :: AudioFader).Volume = entry.Id == "RadioTaggedSound" and value or instance.Volume
		elseif instance.Name == "RadioPhysicalVolume" then
			(instance :: AudioFader).Volume = entry.Id == "RadioSpeaker" and value or instance.Volume
		elseif instance.Name == "RadioActiveVolume" then
			(instance :: AudioFader).Volume = entry.Id == "RadioActiveStatic" and value * Config.Entries[2].Table[Config.Entries[2].Key] or instance.Volume
		elseif instance.Name == "RadioDeathVolume" then
			(instance :: AudioFader).Volume = entry.Id == "RadioDeathStatic" and value * Config.Entries[2].Table[Config.Entries[2].Key] or instance.Volume
		end
	end
end

for _, entry in Config.Entries do
	local default = entry.Table[entry.Key]
	local display = panel:AddSlider(entry.Label, 0, entry.Maximum, default, Config.Step, function(value)
		applyVolume(entry, value)
	end)
	table.insert(resets, function()
		display(default)
		applyVolume(entry, default)
	end)
end

panel:AddButton("reset to config defaults", function()
	for _, reset in resets do
		reset()
	end
end)

panel:AddLabel("changes apply locally for this client and reset when the session ends.")

return VoiceDebugService
