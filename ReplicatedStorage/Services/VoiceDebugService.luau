local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Configs.VoiceDebugConfig)
local PerfGraphConfig = require(ReplicatedStorage.Configs.PerfGraphConfig)
local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local VoiceDebugService = {}

if not (FLAGS.VoiceDebug and RunService:IsClient()) then
	return VoiceDebugService
end

local panel = DebugPanel.new("voice + walkie volumes + perf graphs", Config.ToggleKey, PerfGraphConfig.PanelWidth)
local resets: { () -> () } = {}
local localPlayer = Players.LocalPlayer
local localVolumes: { [string]: number } = {}
local voiceRoutes: { [AudioEmitter]: {
	Fader: AudioFader,
	InputWire: Wire,
	OutputWire: Wire,
	Source: AudioDeviceInput,
} } = {}
local refreshQueued = false

local function getVoiceWires(source: AudioDeviceInput, emitter: AudioEmitter): { Wire }
	local wires: { Wire } = {}
	local seen: { [Wire]: boolean } = {}
	local function addWire(wire: Wire)
		if seen[wire] then return end
		seen[wire] = true
		table.insert(wires, wire)
	end
	for _, wire in emitter:GetConnectedWires("Input") do
		if wire.SourceInstance == source and wire.TargetInstance == emitter then
			addWire(wire)
		end
	end
	for _, wire in source:GetConnectedWires("Output") do
		if wire.SourceInstance == source and wire.TargetInstance == emitter then
			addWire(wire)
		end
	end
	return wires
end

local function destroyVoiceRoute(emitter: AudioEmitter)
	local route = voiceRoutes[emitter]
	if not route then return end
	if route.InputWire.Parent then route.InputWire:Destroy() end
	if route.OutputWire.Parent then route.OutputWire:Destroy() end
	if route.Fader.Parent then route.Fader:Destroy() end
	voiceRoutes[emitter] = nil
end

local function ensureVoiceRoute(target: Player, emitter: AudioEmitter)
	if target == localPlayer then return end

	local source = target:FindFirstChild("AudioDeviceInput")
	if not source or not source:IsA("AudioDeviceInput") then
		destroyVoiceRoute(emitter)
		return
	end

	local route = voiceRoutes[emitter]
	if route and (not route.Fader.Parent or route.Source ~= source) then
		destroyVoiceRoute(emitter)
		route = nil
	end

	local directWires = getVoiceWires(source, emitter)
	if route then
		for _, wire in directWires do wire:Destroy() end
		route.Fader.Volume = localVolumes.ProximityVoice
		return
	end
	if #directWires == 0 then return end

	for _, wire in directWires do wire:Destroy() end

	local fader = Instance.new("AudioFader")
	fader.Name = "VoiceReceiveVolume"
	fader.Volume = localVolumes.ProximityVoice
	fader.Parent = emitter

	local inputWire = Instance.new("Wire")
	inputWire.Name = "VoiceInputToReceiveVolume"
	inputWire.SourceInstance = source
	inputWire.TargetInstance = fader
	inputWire.Parent = fader

	local outputWire = Instance.new("Wire")
	outputWire.Name = "VoiceReceiveVolumeToEmitter"
	outputWire.SourceInstance = fader
	outputWire.TargetInstance = emitter
	outputWire.Parent = fader

	voiceRoutes[emitter] = {
		Fader = fader,
		InputWire = inputWire,
		OutputWire = outputWire,
		Source = source,
	}
end

local function refreshVoiceRoutes()
	for emitter in voiceRoutes do
		if not emitter.Parent then voiceRoutes[emitter] = nil end
	end

	for _, target in Players:GetPlayers() do
		if target == localPlayer or not target.Character then continue end
		for _, descendant in target.Character:GetDescendants() do
			if descendant:IsA("AudioEmitter") then
				ensureVoiceRoute(target, descendant)
			end
		end
	end
end

local function forEachAudioDescendant(callback: (Instance) -> ())
	for _, target in Players:GetPlayers() do
		for _, descendant in target:GetDescendants() do
			callback(descendant)
		end
	end
	for _, descendant in Workspace:GetDescendants() do
		callback(descendant)
	end
end

local ownVoiceFaderName = `RadioVoice_{Players.LocalPlayer.UserId}`
local ownMonsterFaderName = `RadioMonster_{Players.LocalPlayer.UserId}`

local function getRadioVolume(instanceName: string): number?
	if instanceName == ownVoiceFaderName then
		return localVolumes.RadioVoice
	elseif instanceName == ownMonsterFaderName then
		return localVolumes.RadioTaggedSound
	elseif instanceName == "RadioPhysicalVolume" then
		return localVolumes.RadioSpeaker
	elseif instanceName == "RadioActiveVolume" then
		return localVolumes.RadioActiveStatic * Config.Entries[2].Table[Config.Entries[2].Key]
	elseif instanceName == "RadioDeathVolume" then
		return localVolumes.RadioDeathStatic * Config.Entries[2].Table[Config.Entries[2].Key]
	end
	return nil
end

local function applyRadioVolumes()
	forEachAudioDescendant(function(instance)
		if not instance:IsA("AudioFader") then return end
		local volume = getRadioVolume(instance.Name)
		if volume then instance.Volume = math.clamp(volume, 0, 3) end
	end)
end

local function queueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refreshVoiceRoutes()
		applyRadioVolumes()
	end)
end

local function applyVolume(entry: Config.Entry, value: number)
	localVolumes[entry.Id] = value

	if entry.Id == "ProximityVoice" then
		refreshVoiceRoutes()
		return
	end
	applyRadioVolumes()
end

for _, entry in Config.Entries do
	local default = if entry.Id == "ProximityVoice" then 1 else entry.Table[entry.Key]
	localVolumes[entry.Id] = default
	local display = panel:AddSlider(entry.Label, 0, entry.Maximum, default, Config.Step, function(value)
		applyVolume(entry, value)
	end)
	table.insert(resets, function()
		display(default)
		applyVolume(entry, default)
	end)
end

Players.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("AudioDeviceInput")
		or descendant:IsA("AudioEmitter")
		or descendant:IsA("Wire")
		or descendant:IsA("AudioFader")
	then
		queueRefresh()
	end
end)

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("AudioFader") then queueRefresh() end
end)

refreshVoiceRoutes()
applyRadioVolumes()

panel:AddButton("reset to config defaults", function()
	for _, reset in resets do
		reset()
	end
end)

panel:AddLabel("changes apply to audio heard by this client and reset when the session ends.")

local addedThisFrame = 0
local removedThisFrame = 0
local graphsPaused = false

local fpsGraph = panel:AddGraph("FPS", {
	Height = PerfGraphConfig.GraphHeight,
	Format = "%.0f",
	ColorFor = function(fps: number): Color3
		if fps < PerfGraphConfig.FpsBad then
			return PerfGraphConfig.FpsColorBad
		elseif fps < PerfGraphConfig.FpsWarn then
			return PerfGraphConfig.FpsColorWarn
		end
		return PerfGraphConfig.FpsColorGood
	end,
})

local churnGraph = panel:AddGraph("Instances streamed in + out per frame", {
	Height = PerfGraphConfig.GraphHeight,
	Format = "%d",
	Color = PerfGraphConfig.ChurnColor,
})

local pauseButton: TextButton
pauseButton = panel:AddButton("pause graphs", function()
	graphsPaused = not graphsPaused
	pauseButton.Text = if graphsPaused then "resume graphs" else "pause graphs"
end)

panel:AddButton("clear graphs", function()
	fpsGraph:Clear()
	churnGraph:Clear()
end)

Workspace.DescendantAdded:Connect(function()
	addedThisFrame += 1
end)

Workspace.DescendantRemoving:Connect(function()
	removedThisFrame += 1
end)

RunService.RenderStepped:Connect(function(deltaTime: number)
	local added, removed = addedThisFrame, removedThisFrame
	addedThisFrame, removedThisFrame = 0, 0
	if graphsPaused then return end
	fpsGraph:Push(1 / math.max(deltaTime, 1e-6))
	churnGraph:Push(added + removed)
end)

return VoiceDebugService
