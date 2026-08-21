local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local NPC = require(ServerStorage.Classes.NPC)
local StunService = require(ServerStorage.Services.StunService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local CONFIG = ToolConfigs.Trap

local TrapObject = {}
TrapObject.__index = TrapObject

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

function TrapObject:Spring(model: Instance?)
	if self.Trap:GetAttribute("Closed") then return end
	local npcModel = findNpcModel(model)
	if not npcModel then return end

	self.Trap:SetAttribute("Closed", true)
	StunService:Stun(npcModel, CONFIG.StunDuration)

	if self.Track then
		self.Track:Play()

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
