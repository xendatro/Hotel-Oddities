local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local Signal = ReplicatedStorage.Communication.Tools.Signal

local ToolBase = {}
ToolBase.__index = ToolBase

local IS_SERVER = RunService:IsServer()

function ToolBase.extend(className: string)
	local class = setmetatable({}, { __index = ToolBase })
	class.__index = class
	class.ClassName = className
	return class
end

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Equipped = self.Tool.Equipped:Connect(function(mouse)
		self.Character = self.Tool.Parent
		self.Humanoid = self.Character and self.Character:FindFirstChildOfClass("Humanoid")
		self.Mouse = mouse
		self:OnEquipped()
	end)

	self.Connections.Unequipped = self.Tool.Unequipped:Connect(function()
		self:OnUnequipped()
		self.Mouse = nil
	end)

	self.Connections.Activated = self.Tool.Activated:Connect(function()
		self:Activate()
	end)
end

function ToolBase.new(tool: Tool, class: any?)
	local self = setmetatable({}, class or ToolBase)

	self.Tool = tool
	self.Name = tool.Name
	self.Config = ToolConfigs[tool.Name] or {}
	self.Busy = false
	self.Handlers = {}
	self.Character = nil
	self.Humanoid = nil

	setUpConnections(self)

	return self
end

function ToolBase:GetPlayer(): Player?
	local parent = self.Tool.Parent
	if not parent then return nil end

	local player = Players:GetPlayerFromCharacter(parent)
	if player then return player end
	if parent:IsA("Backpack") then return parent.Parent :: Player end
	return nil
end

function ToolBase:IsAlive(): boolean
	local character = self.Tool.Parent
	if not character or not character:IsA("Model") then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function ToolBase:GetQuantity(): number
	return self.Tool:GetAttribute("quantity") or 0
end

function ToolBase:Activate()
	if self.Busy then return end
	if self.CooldownUntil and os.clock() < self.CooldownUntil then return end
	if not self:IsAlive() then return end

	self.Busy = true
	self:_BeforeActivate()

	local ok, err = pcall(function()
		self:OnActivated()
	end)

	local cleanupOk, cleanupErr = pcall(function()
		self:OnCleanup()
	end)

	self:_AfterActivate()

	self.Busy = false
	if self.Config.Cooldown then
		self.CooldownUntil = os.clock() + self.Config.Cooldown
	end

	if not ok then
		warn(`[{self.Name}] activation failed: {err}`)
	end
	if not cleanupOk then
		warn(`[{self.Name}] cleanup failed: {cleanupErr}`)
	end
end

local function waitForFirst(timeout: number, onTimeout: (() -> ())?, ...): boolean
	local signals = { ... }
	local thread = coroutine.running()
	local connections = {}
	local resolved, result = false, false

	local function finish(value: boolean)
		if resolved then return end
		resolved = true
		result = value
		task.spawn(thread)
	end

	for index, signal in signals do
		connections[index] = signal:Connect(function()
			finish(index == 1)
		end)
	end

	task.delay(timeout, function()
		if not resolved and onTimeout then
			onTimeout()
		end
		finish(false)
	end)

	coroutine.yield()

	for _, connection in connections do
		connection:Disconnect()
	end
	return result
end

function ToolBase:WaitForMarker(track: AnimationTrack, markerName: string, timeout: number?): boolean
	local name = self.Name
	return waitForFirst(timeout or 10, function()
		warn(`[{name}] animation marker "{markerName}" never fired; continuing anyway`)
	end, track:GetMarkerReachedSignal(markerName), track.Ended)
end

function ToolBase:WaitForTrack(track: AnimationTrack, timeout: number?): boolean
	local name = self.Name
	return waitForFirst(timeout or 10, function()
		warn(`[{name}] animation did not end within {timeout or 10}s; continuing anyway`)
	end, track.Ended)
end

function ToolBase:PlaySound(soundName: string?, part: BasePart?)
	if not soundName or not part then return end

	local AudioService = require(ReplicatedStorage.Services.AudioService)
	AudioService:Play3DSound(soundName, part, false, "SFX")
end

function ToolBase:Fire(eventName: string, ...)
	if IS_SERVER then
		local player = self:GetPlayer()
		if not player then return end
		Signal:FireClient(player, self.Name, eventName, ...)
	else
		Signal:FireServer(self.Name, eventName, ...)
	end
end

function ToolBase:On(eventName: string, handler: (...any) -> ())
	self.Handlers[eventName] = handler
end

function ToolBase:_Dispatch(eventName: string, ...)
	local handler = self.Handlers[eventName]
	if not handler then return end

	local ok, err = pcall(handler, ...)
	if not ok then
		warn(`[{self.Name}] handler "{eventName}" failed: {err}`)
	end
end

function ToolBase:OnEquipped() end
function ToolBase:OnUnequipped() end
function ToolBase:OnActivated() end
function ToolBase:OnCleanup() end
function ToolBase:OnDestroy() end

function ToolBase:_BeforeActivate() end
function ToolBase:_AfterActivate() end

function ToolBase:Destroy()
	self:OnDestroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
	self.Handlers = {}
end

return ToolBase
