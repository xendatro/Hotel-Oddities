local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)
local VoiceChatConfig = require(ReplicatedStorage.Configs.VoiceChatConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MathService = require(ReplicatedStorage.Services.MathService)
local ViewmodelService = require(ReplicatedStorage.Services.ViewmodelService)
local VoiceActivityService = require(ReplicatedStorage.Services.VoiceActivityService)

local WalkieTalkieService = {}

if not RunService:IsClient() then
	return WalkieTalkieService
end

local player = Players.LocalPlayer

local SetMode = CommunicationService.Get("WalkieTalkie", "SetMode") :: RemoteEvent
local SetPower = CommunicationService.Get("WalkieTalkie", "SetPower") :: RemoteEvent
local SetTransmit = CommunicationService.Get("WalkieTalkie", "SetTransmit") :: RemoteEvent
local SetAudio = CommunicationService.Get("WalkieTalkie", "SetAudio") :: RemoteEvent

local modeIndex = 1
local powered = false
local equipped = false
local raised = false
local transmitting = false
local emitterConnection: RBXScriptConnection?
local mutedEmitterGroup = `WalkieTalkieMuted_{player.UserId}`

local categories: { [string]: number } = {}
local categoryMaximums: { [string]: number } = {}
for _, entry in Config.Categories do
	categories[entry.Id] = 1
	categoryMaximums[entry.Id] = entry.Maximum or 1
end

local playerVolumes: { [number]: number } = {}
local playerMuted: { [number]: boolean } = {}
local levels: { [Player]: number } = {}
local selfLevel = 0

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
	Analyzer: AudioAnalyzer,
	AnalyzerWire: Wire,
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

local emitterCache: { [Player]: AudioEmitter } = {}

local function findVoiceEmitter(target: Player): AudioEmitter?
	local cached = emitterCache[target]
	if cached and cached.Parent then return cached end
	local character = target.Character
	if not character then return nil end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AudioEmitter") and descendant.Name == "AudioEmitter" then
			emitterCache[target] = descendant
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
	if route.AnalyzerWire.Parent then route.AnalyzerWire:Destroy() end
	if route.Analyzer.Parent then route.Analyzer:Destroy() end
	if route.Fader.Parent then route.Fader:Destroy() end
	levels[route.Sender] = nil
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
	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.Name = "WalkieLevelAnalyzer"
	analyzer.SpectrumEnabled = false
	analyzer.Parent = fader
	radioRoutes[output] = {
		Sender = sender,
		Source = source,
		Fader = fader,
		InputWire = connect(source, fader, fader),
		OutputWire = connect(fader, output, fader),
		Analyzer = analyzer,
		AnalyzerWire = connect(source, analyzer, analyzer),
	}
end

local function getPlayerGain(target: Player): number
	if playerMuted[target.UserId] then return 0 end
	local volume = playerVolumes[target.UserId]
	return if volume then math.clamp(volume, 0, 1) else 1
end

local function smooth(current: number, target: number, deltaTime: number): number
	local meter = Config.Ui.Meter
	local speed = if target > current then meter.Attack else meter.Release
	return current + (target - current) * MathService.ExpAlpha(speed, deltaTime)
end

local function updateSelfLevel(deltaTime: number)
	local target = if transmitting
		then math.clamp(VoiceActivityService:GetLevel() * Config.Ui.Meter.Gain, 0, 1)
		else 0
	selfLevel = smooth(selfLevel, target, deltaTime)
end

local function updateRouteVolumes(deltaTime: number)
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

	local meter = Config.Ui.Meter
	for _, route in radioRoutes do
		local emitter = findVoiceEmitter(route.Sender)
		local emitterPosition = emitter and getWorldPosition(emitter)
		local weight = 1
		if emitterPosition then
			local directLevel = getProximityAttenuation((emitterPosition - listenerPosition).Magnitude)
			weight = math.clamp((radioLevel + blend - directLevel) / (2 * blend), 0, 1)
		end
		route.Fader.Volume = weight * getPlayerGain(route.Sender)

		levels[route.Sender] = smooth(
			levels[route.Sender] or 0,
			math.clamp(route.Analyzer.RmsLevel * meter.Gain, 0, 1),
			deltaTime
		)
	end
end

local function findWalkie(target: Player): Tool?
	local backpack = target:FindFirstChildOfClass("Backpack")
	for _, root in { target.Character, backpack } do
		if not root then continue end
		local tool = root:FindFirstChild(Config.ToolName)
		if tool and tool:IsA("Tool") then return tool end
	end
	return nil
end

local function isOwnedRadioOutput(descendant: Instance): boolean
	return descendant:IsA("AudioDeviceOutput")
		and descendant.Player == player
		and string.match(descendant.Name, "^RadioOutput_%d+$") ~= nil
end

local function refreshRoutes(deltaTime: number)
	updateSelfLevel(deltaTime)
	if not powered then return end
	local seenEmitters: { [AudioEmitter]: boolean } = {}
	local seenOutputs: { [AudioDeviceOutput]: boolean } = {}
	for _, target in Players:GetPlayers() do
		if target == player then continue end
		local emitter = findVoiceEmitter(target)
		if emitter then
			seenEmitters[emitter] = true
			ensureVoiceRoute(target, emitter)
		end
		local tool = findWalkie(target)
		if tool then
			for _, child in tool:GetChildren() do
				if isOwnedRadioOutput(child) then
					seenOutputs[child] = true
					ensureRadioRoute(target, child)
				end
			end
		end
	end
	for emitter in voiceRoutes do
		if not seenEmitters[emitter] then destroyVoiceRoute(emitter, false) end
	end
	for output in radioRoutes do
		if not seenOutputs[output] then destroyRadioRoute(output, false) end
	end
	updateRouteVolumes(deltaTime)
end

local function clearRoutes()
	for emitter in voiceRoutes do destroyVoiceRoute(emitter, true) end
	for output in radioRoutes do destroyRadioRoute(output, true) end
	table.clear(levels)
end

local function muteOwnEmitter(descendant: Instance)
	if descendant.Name == "RadioEmitter" and descendant:IsA("AudioEmitter") then
		descendant.AudioInteractionGroup = mutedEmitterGroup
	end
end

local function findTool(): Tool?
	return findWalkie(player)
end

local function watchOwnEmitter()
	if emitterConnection then
		emitterConnection:Disconnect()
		emitterConnection = nil
	end
	local tool = findTool()
	if not tool then return end
	for _, descendant in tool:GetDescendants() do
		muteOwnEmitter(descendant)
	end
	emitterConnection = tool.DescendantAdded:Connect(muteOwnEmitter)
end

local function applyPose()
	ViewmodelService:SetPose(if raised then "Raised" elseif transmitting then "Talk" else nil)
end

function WalkieTalkieService:GetTool(): Tool?
	return findTool()
end

function WalkieTalkieService:IsPowered(): boolean
	return powered
end

function WalkieTalkieService:IsEquipped(): boolean
	return equipped
end

function WalkieTalkieService:IsRaised(): boolean
	return raised
end

function WalkieTalkieService:IsTransmitting(): boolean
	return transmitting
end

function WalkieTalkieService:SetTransmitting(value: boolean)
	local wanted = value == true and powered and equipped
	if transmitting == wanted then return end
	transmitting = wanted
	SetTransmit:FireServer(transmitting)
	applyPose()
end

function WalkieTalkieService:SetRaised(value: boolean)
	local wanted = value == true and powered and equipped
	if raised == wanted then return end
	raised = wanted
	if raised then self:SetTransmitting(false) end
	applyPose()
end

function WalkieTalkieService:ToggleRaised()
	self:SetRaised(not raised)
end

function WalkieTalkieService:SetPowered(value: boolean)
	local wanted = value == true and player:GetAttribute(Config.VoiceAttribute) ~= false
	if powered == wanted then return end
	powered = wanted
	SetPower:FireServer(powered)
	if powered then
		watchOwnEmitter()
		return
	end
	self:SetTransmitting(false)
	self:SetRaised(false)
	clearRoutes()
	if emitterConnection then
		emitterConnection:Disconnect()
		emitterConnection = nil
	end
end

function WalkieTalkieService:TogglePower()
	self:SetPowered(not powered)
end

function WalkieTalkieService:SetEquipped(value: boolean)
	equipped = value == true
	if not equipped then
		self:SetTransmitting(false)
		self:SetRaised(false)
	end
	if powered then watchOwnEmitter() end
end

function WalkieTalkieService:GetMode(): string
	return Config.Modes[modeIndex].Id
end

function WalkieTalkieService:GetModeLabel(): string
	return Config.Modes[modeIndex].Label
end

function WalkieTalkieService:CycleMode()
	modeIndex = modeIndex % #Config.Modes + 1
	SetMode:FireServer(Config.Modes[modeIndex].Id)
end

function WalkieTalkieService:GetCategory(id: string): number
	return (categories[id] or 1) / (categoryMaximums[id] or 1)
end

function WalkieTalkieService:SetCategory(id: string, value: number)
	if categories[id] == nil then return end
	categories[id] = math.clamp(value, 0, 1) * categoryMaximums[id]
	SetAudio:FireServer(categories)
end

function WalkieTalkieService:IsMuted(target: Player): boolean
	return playerMuted[target.UserId] == true
end

function WalkieTalkieService:SetMuted(target: Player, value: boolean)
	playerMuted[target.UserId] = if value then true else nil
end

function WalkieTalkieService:GetPlayerVolume(target: Player): number
	return playerVolumes[target.UserId] or 1
end

function WalkieTalkieService:SetPlayerVolume(target: Player, value: number)
	playerVolumes[target.UserId] = math.clamp(value, 0, 1)
end

function WalkieTalkieService:GetLevel(target: Player): number
	return levels[target] or 0
end

function WalkieTalkieService:GetCategoryFor(target: Player): string
	if target:GetAttribute(Config.VoiceAttribute) == false then return "NoVoice" end
	if target:GetAttribute(Config.PowerAttribute) == true then return "Enabled" end
	return "Disabled"
end

local ORDER = { Enabled = 1, Disabled = 2, NoVoice = 3 }

export type RosterEntry = { Player: Player, Category: string, Level: number }

function WalkieTalkieService:GetRoster(): { RosterEntry }
	local roster: { RosterEntry } = {}
	for _, target in Players:GetPlayers() do
		table.insert(roster, {
			Player = target,
			Category = self:GetCategoryFor(target),
			Level = if target == player then selfLevel else self:GetLevel(target),
		})
	end
	table.sort(roster, function(a, b)
		local rankA, rankB = ORDER[a.Category], ORDER[b.Category]
		if rankA ~= rankB then return rankA < rankB end
		local nameA, nameB = a.Player.DisplayName:lower(), b.Player.DisplayName:lower()
		if nameA ~= nameB then return nameA < nameB end
		return a.Player.UserId < b.Player.UserId
	end)
	return roster
end

SetAudio.OnClientEvent:Connect(function(saved: any, mode: any)
	if type(saved) == "table" then
		for id, value in saved do
			if categories[id] ~= nil and type(value) == "number" then
				categories[id] = math.clamp(value, 0, categoryMaximums[id])
			end
		end
	end
	if type(mode) == "string" then
		for index, entry in Config.Modes do
			if entry.Id == mode then modeIndex = index end
		end
	end
end)

Players.PlayerRemoving:Connect(function(target)
	emitterCache[target] = nil
	levels[target] = nil
	playerMuted[target.UserId] = nil
	playerVolumes[target.UserId] = nil
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Config.Keys.Power then
		if equipped or powered then WalkieTalkieService:TogglePower() end
	elseif input.KeyCode == Config.Keys.Raise then
		WalkieTalkieService:ToggleRaised()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not raised then
		WalkieTalkieService:SetTransmitting(true)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		WalkieTalkieService:SetTransmitting(false)
	end
end)

RunService.Heartbeat:Connect(refreshRoutes)

return WalkieTalkieService
