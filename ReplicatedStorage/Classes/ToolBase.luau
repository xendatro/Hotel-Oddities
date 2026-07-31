local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local Signal = ReplicatedStorage.Communication.Tools.Signal

--- @class ToolBase
--- The chassis every tool sits on, server or client. It owns the parts each tool used to repeat:
--- tracking who is holding it, routing activation, talking to its opposite half, and tearing itself
--- down. A tool subclass overrides hooks and nothing else.
---
--- Hooks, all optional:
---   OnEquipped()   -- they just took it out
---   OnUnequipped() -- they just put it away
---   OnActivated()  -- they used it; may yield
---   OnCleanup()    -- always runs after OnActivated, even if it errored or they died mid-use
---   OnDestroy()    -- the tool is gone
local ToolBase = {}
ToolBase.__index = ToolBase

local IS_SERVER = RunService:IsServer()

--- Creates a subclass with the inheritance chain wired up.
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
		self.Mouse = mouse -- nil on the server; the client half uses it for aiming
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

--- @param tool Tool
--- @param class any -- the subclass to instantiate as
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

--- Who is holding this tool, whether it is stowed or equipped, or nil if nobody is.
function ToolBase:GetPlayer(): Player?
	local parent = self.Tool.Parent
	if not parent then return nil end

	local player = Players:GetPlayerFromCharacter(parent)
	if player then return player end
	if parent:IsA("Backpack") then return parent.Parent :: Player end
	return nil
end

--- Whether the holder is currently alive and usable. Checked before activation and worth
--- re-checking after any yield, since they can die in the middle of a long action.
function ToolBase:IsAlive(): boolean
	local character = self.Tool.Parent
	if not character or not character:IsA("Model") then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

--- How many are left in the stack.
function ToolBase:GetQuantity(): number
	return self.Tool:GetAttribute("quantity") or 0
end

--- Runs the tool's action, guarding against overlap and guaranteeing the guard is released.
---
--- The release is the important part. Every one of these tools used to hold a `Playing` flag that
--- it cleared on the last line of a long, yielding routine -- so an animation whose end marker
--- never fired, or a player who died mid-action, left the flag set and the tool dead for the rest
--- of the round. Here the flag is cleared no matter how `OnActivated` ends.
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

-- Resumes this thread on whichever of the given signals fires first, or on the timeout. Every
-- animation wait in every tool goes through here, which is what makes them all unhangable.
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
			finish(index == 1) -- only the first signal counts as "what we wanted"
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

--- Waits for an animation marker, but never forever.
---
--- Returns true if the marker fired, false if the track ended without it or the timeout ran out.
--- A bare `GetMarkerReachedSignal(name):Wait()` hangs indefinitely when the marker is missing from
--- the animation, misspelled, or simply never reached because the track was interrupted -- which is
--- how a player ends up frozen holding an unusable tool.
function ToolBase:WaitForMarker(track: AnimationTrack, markerName: string, timeout: number?): boolean
	local name = self.Name
	return waitForFirst(timeout or 10, function()
		warn(`[{name}] animation marker "{markerName}" never fired; continuing anyway`)
	end, track:GetMarkerReachedSignal(markerName), track.Ended)
end

--- Waits for an animation to finish, but never forever. Returns true if it ended on its own.
function ToolBase:WaitForTrack(track: AnimationTrack, timeout: number?): boolean
	local name = self.Name
	return waitForFirst(timeout or 10, function()
		warn(`[{name}] animation did not end within {timeout or 10}s; continuing anyway`)
	end, track.Ended)
end

--- Plays one of this tool's sounds at a part, skipping silently if the part is gone.
function ToolBase:PlaySound(soundName: string?, part: BasePart?)
	if not soundName or not part then return end

	local AudioService = require(ReplicatedStorage.Services.AudioService)
	AudioService:Play3DSound(soundName, part, false, "SFX")
end

--- Cross-boundary messaging ----------------------------------------------------------------------

--- Sends a message to this tool's other half. On the client it goes to the server; on the server it
--- goes to whoever is holding the tool. Either way the receiving side dispatches it to the matching
--- instance of the same tool, so neither half needs to know a remote exists.
function ToolBase:Fire(eventName: string, ...)
	if IS_SERVER then
		local player = self:GetPlayer()
		if not player then return end
		Signal:FireClient(player, self.Name, eventName, ...)
	else
		Signal:FireServer(self.Name, eventName, ...)
	end
end

--- Registers a handler for a message from the other half. On the server the handler receives
--- `(player, ...)`; the player is already verified to own this tool before it is called.
function ToolBase:On(eventName: string, handler: (...any) -> ())
	self.Handlers[eventName] = handler
end

--- Called by the tool services when a message arrives. Not for tools to call.
function ToolBase:_Dispatch(eventName: string, ...)
	local handler = self.Handlers[eventName]
	if not handler then return end

	local ok, err = pcall(handler, ...)
	if not ok then
		warn(`[{self.Name}] handler "{eventName}" failed: {err}`)
	end
end

--- Hooks ----------------------------------------------------------------------------------------

function ToolBase:OnEquipped() end
function ToolBase:OnUnequipped() end
function ToolBase:OnActivated() end
function ToolBase:OnCleanup() end
function ToolBase:OnDestroy() end

-- Bracket an activation that actually passed the guards. Side-specific bases use these for effects
-- that must wrap the whole action regardless of what the tool itself does -- the client's limb
-- reveal being the reason they exist. Tools should override the On* hooks above instead.
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
