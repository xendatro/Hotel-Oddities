local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpawnZoneConfig = require(ReplicatedStorage.Configs.SpawnZoneConfig)

local Isolation = {}
Isolation.__index = Isolation

local BIND_NAME = "IntroCutsceneIsolation"
local BIND_PRIORITY = Enum.RenderPriority.Last.Value + 5
local HIDDEN = 1
local ENEMIES_FOLDER = "Enemies"
local WORLD_NAMES = {
	CreepBackdrop = true,
	CreepDistortion = true,
	EnemyDespawnPoof = true,
	HearingMotes = true,
	CeilingWalkIns = true,
	BookEffects = true,
	VFXDummy = true,
	Trap = true,
	RadioDeathBursts = true,
}
local CAMERA_NAMES = {
	HearingMotes = true,
}
local SWITCHED_CLASSES = {
	"Light",
	"Beam",
	"BillboardGui",
	"SurfaceGui",
	"Highlight",
	"ProximityPrompt",
	"Fire",
	"Smoke",
	"Sparkles",
}
local MUTED_CLASSES = { "Sound", "AudioPlayer" }
local INVISIBLE = NumberSequence.new(1)

type Override = {
	Set: (self: any, instance: Instance, property: string, value: any) -> (),
	Release: (self: any, instance: Instance, property: string?) -> (),
}

type Hidden = {
	Root: Instance,
	Value: number,
}

type Overridden = {
	Root: Instance,
	Properties: { [string]: any },
}

type Watch = {
	Added: RBXScriptConnection,
	Removing: RBXScriptConnection,
}

export type Options = {
	Override: Override,
	HideLocalCharacter: boolean?,
}

export type Isolation = typeof(setmetatable({} :: {
	Override: Override,
	HideLocalCharacter: boolean,
	Running: boolean,
	Roots: { [Instance]: Watch },
	Parts: { [Instance]: Hidden },
	Overridden: { [Instance]: Overridden },
	PlayerConnections: { [Player]: { [string]: RBXScriptConnection } },
	Connections: { [string]: RBXScriptConnection },
}, Isolation))

local function isAny(instance: Instance, classNames: { string }): boolean
	for _, className in classNames do
		if instance:IsA(className) then return true end
	end
	return false
end

local function overridesFor(instance: Instance): { [string]: any }?
	if instance:IsA("ParticleEmitter") or instance:IsA("Trail") then
		return { Enabled = false, Transparency = INVISIBLE }
	end
	if isAny(instance, SWITCHED_CLASSES) then
		return { Enabled = false }
	end
	if isAny(instance, MUTED_CLASSES) then
		return { Volume = 0 }
	end
	return nil
end

local function isFaded(instance: Instance): boolean
	return instance:IsA("BasePart") or instance:IsA("Decal")
end

local function setUpConnections(self: Isolation)
	self.Connections = {}

	self.Connections.PlayerAdded = Players.PlayerAdded:Connect(function(player: Player)
		self:_watchPlayer(player)
	end)
	self.Connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
		self:_unwatchPlayer(player)
	end)
	self.Connections.WorldAdded = workspace.ChildAdded:Connect(function(child: Instance)
		self:_considerWorld(child)
	end)
	self.Connections.WorldRemoved = workspace.ChildRemoved:Connect(function(child: Instance)
		self:_unwatch(child)
	end)
	self.Connections.ZoneAdded = CollectionService:GetInstanceAddedSignal(SpawnZoneConfig.Tag):Connect(function(zone: Instance)
		if zone:IsDescendantOf(workspace) then
			self:_watch(zone)
		end
	end)
	self.Connections.ZoneRemoved = CollectionService:GetInstanceRemovedSignal(SpawnZoneConfig.Tag):Connect(function(zone: Instance)
		self:_unwatch(zone)
	end)

	local camera = workspace.CurrentCamera
	if camera then
		self.Connections.CameraAdded = camera.ChildAdded:Connect(function(child: Instance)
			if CAMERA_NAMES[child.Name] then
				self:_watch(child)
			end
		end)
		self.Connections.CameraRemoved = camera.ChildRemoved:Connect(function(child: Instance)
			self:_unwatch(child)
		end)
	end
end

function Isolation.new(options: Options): Isolation
	assert(options.Override, "Isolation needs a LocalOverride")

	local self = setmetatable({
		Override = options.Override,
		HideLocalCharacter = options.HideLocalCharacter ~= false,
		Running = false,
		Roots = {},
		Parts = {},
		Overridden = {},
		PlayerConnections = {},
		Connections = {},
	}, Isolation)

	return self
end

function Isolation:_hide(instance: Instance, root: Instance)
	if isFaded(instance) then
		local faded = instance :: any
		if not self.Parts[instance] then
			self.Parts[instance] = { Root = root, Value = faded.LocalTransparencyModifier }
		end
		if faded.LocalTransparencyModifier ~= HIDDEN then
			faded.LocalTransparencyModifier = HIDDEN
		end
		return
	end

	if self.Overridden[instance] then return end
	local properties = overridesFor(instance)
	if not properties then return end

	self.Overridden[instance] = { Root = root, Properties = properties }
	for property, value in properties do
		self.Override:Set(instance, property, value)
	end
end

function Isolation:_forget(instance: Instance)
	local hidden = self.Parts[instance]
	if hidden then
		self.Parts[instance] = nil
		local faded = instance :: any
		if faded.LocalTransparencyModifier == HIDDEN then
			faded.LocalTransparencyModifier = hidden.Value
		end
	end

	local overridden = self.Overridden[instance]
	if overridden then
		self.Overridden[instance] = nil
		for property in overridden.Properties do
			self.Override:Release(instance, property)
		end
	end
end

function Isolation:_watch(root: Instance)
	if not self.Running or self.Roots[root] then return end

	self.Roots[root] = {
		Added = root.DescendantAdded:Connect(function(descendant: Instance)
			self:_hide(descendant, root)
		end),
		Removing = root.DescendantRemoving:Connect(function(descendant: Instance)
			self:_forget(descendant)
		end),
	}

	self:_hide(root, root)
	for _, descendant in root:GetDescendants() do
		self:_hide(descendant, root)
	end
end

function Isolation:_unwatch(root: Instance)
	local watch = self.Roots[root]
	if not watch then return end

	self.Roots[root] = nil
	watch.Added:Disconnect()
	watch.Removing:Disconnect()

	local owned: { Instance } = {}
	for instance, hidden in self.Parts do
		if hidden.Root == root then
			table.insert(owned, instance)
		end
	end
	for instance, overridden in self.Overridden do
		if overridden.Root == root then
			table.insert(owned, instance)
		end
	end
	for _, instance in owned do
		self:_forget(instance)
	end
end

function Isolation:_watchPlayer(player: Player)
	if not self.Running or self.PlayerConnections[player] then return end
	if player == Players.LocalPlayer and not self.HideLocalCharacter then return end

	self.PlayerConnections[player] = {
		CharacterAdded = player.CharacterAdded:Connect(function(character: Model)
			self:_watch(character)
		end),
		CharacterRemoving = player.CharacterRemoving:Connect(function(character: Model)
			self:_unwatch(character)
		end),
	}

	local character = player.Character
	if character then
		self:_watch(character)
	end
end

function Isolation:_unwatchPlayer(player: Player)
	local connections = self.PlayerConnections[player]
	if not connections then return end

	self.PlayerConnections[player] = nil
	for _, connection in connections do
		connection:Disconnect()
	end

	local character = player.Character
	if character then
		self:_unwatch(character)
	end
end

function Isolation:_considerWorld(child: Instance)
	if child.Name == ENEMIES_FOLDER or WORLD_NAMES[child.Name] then
		self:_watch(child)
	end
end

function Isolation:_step()
	for instance, hidden in self.Parts do
		local faded = instance :: any
		local current = faded.LocalTransparencyModifier
		if current ~= HIDDEN then
			hidden.Value = current
			faded.LocalTransparencyModifier = HIDDEN
		end
	end
end

function Isolation:Start()
	if self.Running then return end
	self.Running = true

	setUpConnections(self)

	for _, player in Players:GetPlayers() do
		self:_watchPlayer(player)
	end
	for _, child in workspace:GetChildren() do
		self:_considerWorld(child)
	end
	local camera = workspace.CurrentCamera
	if camera then
		for _, child in camera:GetChildren() do
			if CAMERA_NAMES[child.Name] then
				self:_watch(child)
			end
		end
	end
	for _, zone in CollectionService:GetTagged(SpawnZoneConfig.Tag) do
		if zone:IsDescendantOf(workspace) then
			self:_watch(zone)
		end
	end

	RunService:BindToRenderStep(BIND_NAME, BIND_PRIORITY, function()
		self:_step()
	end)
end

function Isolation:Stop()
	if not self.Running then return end
	self.Running = false

	RunService:UnbindFromRenderStep(BIND_NAME)

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	for _, connections in self.PlayerConnections do
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	self.PlayerConnections = {}

	for _, watch in self.Roots do
		watch.Added:Disconnect()
		watch.Removing:Disconnect()
	end
	self.Roots = {}

	local parts = self.Parts
	self.Parts = {}
	for instance, hidden in parts do
		local faded = instance :: any
		if faded.LocalTransparencyModifier == HIDDEN then
			faded.LocalTransparencyModifier = hidden.Value
		end
	end

	local overridden = self.Overridden
	self.Overridden = {}
	for instance, entry in overridden do
		for property in entry.Properties do
			self.Override:Release(instance, property)
		end
	end
end

function Isolation:Destroy()
	self:Stop()
end

return Isolation
