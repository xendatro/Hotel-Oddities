local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)
local VoiceChatConfig = require(ReplicatedStorage.Configs.VoiceChatConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local WalkieTalkieService = {}

if not RunService:IsClient() then
	return WalkieTalkieService
end

local player = Players.LocalPlayer
local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild("PlayerLocator") :: ScreenGui
local frame = gui:WaitForChild("Mode") :: Frame
local modeLabel = frame:WaitForChild("Mode") :: TextLabel
local toggle = frame:WaitForChild("Toggle") :: ImageButton
local cooldownLabel = frame:FindFirstChild("TeleportCooldown") :: TextLabel?

local SetMode = CommunicationService.Get("WalkieTalkie", "SetMode") :: RemoteEvent
local modeIndex = 1
local enabled = false
local emitterConnection: RBXScriptConnection?
local mutedEmitterGroup = `WalkieTalkieMuted_{player.UserId}`

type VoiceRoute = {
	Target: Player,
	Source: AudioDeviceInput,
	Fader: AudioFader,
	InputWire: Wire,
	OutputWire: Wire,
	Owned: boolean,
	OriginalVolume: number,
}

type RadioRoute = {
	Sender: Player,
	Source: Instance,
	Fader: AudioFader,
	InputWire: Wire,
	OutputWire: Wire,
}

local voiceRoutes: { [AudioEmitter]: VoiceRoute } = {}
local radioRoutes: { [AudioDeviceOutput]: RadioRoute } = {}

local function connect(source: Instance, target: Instance, parent: Instance): Wire
	local wire = Instance.new("Wire")
	wire.Name = `{source.Name}To{target.Name}`
	wire.SourceInstance = source
	wire.TargetInstance = target
	wire.Parent = parent
	return wire
end

local function addWire(wires: { Wire }, seen: { [Wire]: boolean }, wire: Wire)
	if seen[wire] then return end
	seen[wire] = true
	table.insert(wires, wire)
end

local function getDirectVoiceWires(source: AudioDeviceInput, emitter: AudioEmitter): { Wire }
	local wires: { Wire } = {}
	local seen: { [Wire]: boolean } = {}
	for _, wire in emitter:GetConnectedWires("Input") do
		if wire.SourceInstance == source and wire.TargetInstance == emitter then
			addWire(wires, seen, wire)
		end
	end
	for _, wire in source:GetConnectedWires("Output") do
		if wire.SourceInstance == source and wire.TargetInstance == emitter then
			addWire(wires, seen, wire)
		end
	end
	return wires
end

local function getRadioWires(output: AudioDeviceOutput, excluded: Wire?): { Wire }
	local wires: { Wire } = {}
	local seen: { [Wire]: boolean } = {}
	for _, wire in output:GetConnectedWires("Input") do
		if wire ~= excluded and wire.TargetInstance == output then
			addWire(wires, seen, wire)
		end
	end
	return wires
end

local function getWorldPosition(instance: Instance): Vector3?
	local parent = instance.Parent
	if not parent then return nil end
	if parent:IsA("BasePart") then return parent.Position end
	if parent:IsA("Attachment") then return parent.WorldPosition end
	if parent:IsA("PVInstance") then return parent:GetPivot().Position end
	return nil
end

local function getListenerPosition(): Vector3?
	local camera = workspace.CurrentCamera
	if camera then return camera.CFrame.Position end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position end
	return nil
end

local function getProximityAttenuation(distance: number): number
	local minimum = VoiceChatConfig.Distance.Minimum
	local maximum = VoiceChatConfig.Distance.Maximum
	if maximum <= minimum then return if distance <= minimum then 1 else 0 end
	return 1 - math.clamp((distance - minimum) / (maximum - minimum), 0, 1)
end

local function findVoiceEmitter(target: Player): AudioEmitter?
	local character = target.Character
	if not character then return nil end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AudioEmitter") and descendant.Name == "AudioEmitter" then
			return descendant
		end
	end
	return nil
end

local function findExistingVoiceRoute(source: AudioDeviceInput, emitter: AudioEmitter): (AudioFader?, Wire?, Wire?)
	for _, descendant in emitter:GetChildren() do
		if not descendant:IsA("AudioFader") then continue end
		local inputWire: Wire?
		for _, wire in descendant:GetConnectedWires("Input") do
			if wire.SourceInstance == source and wire.TargetInstance == descendant then
				inputWire = wire
				break
			end
		end
		local outputWire: Wire?
		for _, wire in emitter:GetConnectedWires("Input") do
			if wire.SourceInstance == descendant and wire.TargetInstance == emitter then
				outputWire = wire
				break
			end
		end
		if inputWire and outputWire then
			return descendant, inputWire, outputWire
		end
	end
	return nil, nil, nil
end

local function destroyVoiceRoute(emitter: AudioEmitter, restoreDirect: boolean)
	local route = voiceRoutes[emitter]
	if not route then return end
	if route.Owned then
		if route.InputWire.Parent then route.InputWire:Destroy() end
		if route.OutputWire.Parent then route.OutputWire:Destroy() end
		if route.Fader.Parent then route.Fader:Destroy() end
	end
	voiceRoutes[emitter] = nil
	if restoreDirect and not route.Owned and route.Fader.Parent then
		route.Fader.Volume = route.OriginalVolume
	elseif restoreDirect and route.Owned and route.Source.Parent and emitter.Parent and #getDirectVoiceWires(route.Source, emitter) == 0 then
		connect(route.Source, emitter, emitter)
	end
end

local function destroyRadioRoute(output: AudioDeviceOutput, restoreDirect: boolean)
	local route = radioRoutes[output]
	if not route then return end
	if route.InputWire.Parent then route.InputWire:Destroy() end
	if route.OutputWire.Parent then route.OutputWire:Destroy() end
	if route.Fader.Parent then route.Fader:Destroy() end
	radioRoutes[output] = nil
	if restoreDirect and route.Source.Parent and output.Parent and #getRadioWires(output) == 0 then
		connect(route.Source, output, output)
	end
end

local function ensureVoiceRoute(target: Player, emitter: AudioEmitter)
	local source = target:FindFirstChild("AudioDeviceInput")
	if not source or not source:IsA("AudioDeviceInput") then
		destroyVoiceRoute(emitter, false)
		return
	end

	local route = voiceRoutes[emitter]
	if route and (not route.Fader.Parent or route.Source ~= source) then
		destroyVoiceRoute(emitter, false)
		route = nil
	end

	local directWires = getDirectVoiceWires(source, emitter)
	if route then
		for _, wire in directWires do wire:Destroy() end
		return
	end

	local existingFader, existingInputWire, existingOutputWire = findExistingVoiceRoute(source, emitter)
	if existingFader and existingInputWire and existingOutputWire then
		voiceRoutes[emitter] = {
			Target = target,
			Source = source,
			Fader = existingFader,
			InputWire = existingInputWire,
			OutputWire = existingOutputWire,
			Owned = false,
			OriginalVolume = existingFader.Volume,
		}
		return
	end

	if #directWires == 0 then return end
	for _, wire in directWires do wire:Destroy() end

	local fader = Instance.new("AudioFader")
	fader.Name = "WalkieVoiceSelectVolume"
	fader.Volume = 1
	fader.Parent = emitter
	local inputWire = connect(source, fader, fader)
	local outputWire = connect(fader, emitter, fader)
	voiceRoutes[emitter] = {
		Target = target,
		Source = source,
		Fader = fader,
		InputWire = inputWire,
		OutputWire = outputWire,
		Owned = true,
		OriginalVolume = 1,
	}
end

local function ensureRadioRoute(sender: Player, output: AudioDeviceOutput)
	local route = radioRoutes[output]
	local directWires = getRadioWires(output, route and route.OutputWire)
	if route and not route.Fader.Parent then
		destroyRadioRoute(output, false)
		route = nil
	end
	if route and #directWires > 0 then
		local source = directWires[1].SourceInstance
		if source ~= route.Source then
			destroyRadioRoute(output, false)
			route = nil
		else
			for _, wire in directWires do wire:Destroy() end
		end
	end
	if route then return end
	if #directWires == 0 then return end
	for _, wire in directWires do wire:Destroy() end

	local source = directWires[1].SourceInstance
	if not source then return end
	local fader = Instance.new("AudioFader")
	fader.Name = "WalkieVoiceDistanceVolume"
	fader.Volume = 1
	fader.Parent = output
	local inputWire = connect(source, fader, fader)
	local outputWire = connect(fader, output, fader)
	radioRoutes[output] = {
		Sender = sender,
		Source = source,
		Fader = fader,
		InputWire = inputWire,
		OutputWire = outputWire,
	}
end

local function updateRouteVolumes()
	local listenerPosition = getListenerPosition()
	if not listenerPosition then return end
	local radioLevel = math.max(Config.VoiceVolume, 0)
	local blend = math.max(Config.ProximityRadioBlend, 0.001)

	for emitter, route in voiceRoutes do
		local emitterPosition = getWorldPosition(emitter)
		if emitterPosition then
			local directLevel = getProximityAttenuation((emitterPosition - listenerPosition).Magnitude)
			local radioWeight = math.clamp((radioLevel + blend - directLevel) / (2 * blend), 0, 1)
			route.Fader.Volume = 1 - radioWeight
		end
	end

	for _, route in radioRoutes do
		local emitter = findVoiceEmitter(route.Sender)
		local emitterPosition = emitter and getWorldPosition(emitter)
		if emitterPosition then
			local directLevel = getProximityAttenuation((emitterPosition - listenerPosition).Magnitude)
			local radioWeight = math.clamp((radioLevel + blend - directLevel) / (2 * blend), 0, 1)
			route.Fader.Volume = radioWeight
		end
	end
end

local function refreshRoutes()
	if not enabled then return end
	local seenEmitters: { [AudioEmitter]: boolean } = {}
	local seenOutputs: { [AudioDeviceOutput]: boolean } = {}
	for _, target in Players:GetPlayers() do
		if target == player then continue end
		local emitter = findVoiceEmitter(target)
		if emitter then
			seenEmitters[emitter] = true
			ensureVoiceRoute(target, emitter)
		end
		for _, descendant in target:GetDescendants() do
			if descendant:IsA("AudioDeviceOutput")
				and descendant.Player == player
				and descendant.Name:match("^RadioOutput_%d+$")
			then
				seenOutputs[descendant] = true
				ensureRadioRoute(target, descendant)
			end
		end
	end
	for emitter in voiceRoutes do
		if not seenEmitters[emitter] then destroyVoiceRoute(emitter, false) end
	end
	for output in radioRoutes do
		if not seenOutputs[output] then destroyRadioRoute(output, false) end
	end
	updateRouteVolumes()
end

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
		refreshRoutes()
	else
		enabled = false
		for emitter in voiceRoutes do destroyVoiceRoute(emitter, true) end
		for output in radioRoutes do destroyRadioRoute(output, true) end
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

RunService.Heartbeat:Connect(refreshRoutes)

setMode(1, false)
gui.Enabled = false

return WalkieTalkieService
