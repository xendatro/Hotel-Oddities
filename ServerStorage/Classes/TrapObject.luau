local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local NPC = require(ServerStorage.Classes.NPC)
local StunService = require(ServerStorage.Services.StunService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local CONFIG = ToolConfigs.Trap

--- @class TrapObject
--- An armed bear trap sitting in the world -- what the Trap tool leaves behind. It watches its own
--- parts for contact rather than waiting to be told it was stepped on, so it works against any
--- enemy without enemies needing to know traps exist. Springing is one-shot.
local TrapObject = {}
TrapObject.__index = TrapObject

-- Touched parts are not guaranteed to sit directly under the enemy model. Resolve upward until the
-- live NPC is found; this matters for nested parts in models such as the Ceiling Dweller. Eye has
-- no NPC entry, which deliberately keeps it immune to traps.
local function findNpcModel(instance: Instance?): Model?
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and NPC.FromModel(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function setUpConnections(self)
	self.Connections = {}

	for _, part in self.Trap:GetDescendants() do
		if part:IsA("BasePart") then
			self.Connections[part] = part.Touched:Connect(function(hit: BasePart)
				self:Spring(hit.Parent)
			end)
		end
	end
end

function TrapObject.new(trap: Model)
	local self = setmetatable({}, TrapObject)

	self.Trap = trap
	self.Trap:SetAttribute("Closed", false)

	local humanoid = trap:FindFirstChild("Humanoid")
	local animations = trap:FindFirstChild("Animations")
	if humanoid and animations and animations:FindFirstChild("Trap") then
		self.Track = humanoid.Animator:LoadAnimation(animations.Trap)
	end

	setUpConnections(self)

	return self
end

--- Snaps shut on whatever walked into it. A no-op unless `model` is a live enemy, so players walk
--- over their own traps safely.
function TrapObject:Spring(model: Instance?)
	if self.Trap:GetAttribute("Closed") then return end
	local npcModel = findNpcModel(model)
	if not npcModel then return end

	self.Trap:SetAttribute("Closed", true)
	StunService:Stun(npcModel, CONFIG.StunDuration)

	if self.Track then
		self.Track:Play()

		-- Bounded. A bare `GetMarkerReachedSignal("Finished"):Wait()` never returns if the marker is
		-- missing from the animation, which would leave the trap sprung but never cleaned up.
		local thread = coroutine.running()
		local resolved = false
		local function finish()
			if resolved then return end
			resolved = true
			task.spawn(thread)
		end

		local reached = self.Track:GetMarkerReachedSignal("Finished"):Connect(finish)
		local ended = self.Track.Ended:Connect(finish)
		task.delay(CONFIG.DespawnDelay, finish)
		coroutine.yield()

		reached:Disconnect()
		ended:Disconnect()
		self.Track:AdjustSpeed(0)
	end

	if self.Trap.PrimaryPart then
		AudioService:Play3DSound(CONFIG.CloseSound, self.Trap.PrimaryPart, false, "SFX")
	end
	Debris:AddItem(self.Trap, CONFIG.DespawnDelay)
end

function TrapObject:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
end

return TrapObject
