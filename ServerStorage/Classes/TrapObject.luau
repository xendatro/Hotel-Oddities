local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local NPC = require(ServerStorage.Classes.NPC)
local StunService = require(ServerStorage.Services.StunService)

local STUN_DURATION = 5
local DESPAWN_DELAY = 5 -- how long the sprung trap lingers before cleaning itself up

--- @class TrapObject
--- An armed bear trap sitting in the world. It watches its own parts for contact rather than
--- waiting to be told it was stepped on, so it works against any enemy without the enemies
--- needing to know traps exist. Springing is one-shot: it snaps shut, stuns, and clears itself.
local TrapObject = {}
TrapObject.__index = TrapObject

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

	local humanoid = self.Trap:FindFirstChild("Humanoid")
	local animation = self.Trap:FindFirstChild("Animations")
	if humanoid and animation then
		self.Track = humanoid.Animator:LoadAnimation(animation.Trap)
	end

	setUpConnections(self)

	return self
end

--- Snaps shut on whatever walked into it. A no-op unless `model` is a live enemy, so players walk
--- over their own traps safely.
function TrapObject:Spring(model: Instance?)
	if self.Trap:GetAttribute("Closed") then return end
	if not NPC.FromModel(model) then return end

	self.Trap:SetAttribute("Closed", true)
	StunService:Stun(model, STUN_DURATION)

	if self.Track then
		self.Track:Play()
		self.Track:GetMarkerReachedSignal("Finished"):Wait()
		self.Track:AdjustSpeed(0)
	end

	AudioService:Play3DSound("TrapClose", self.Trap.PrimaryPart, false, "SFX")
	Debris:AddItem(self.Trap, DESPAWN_DELAY)
end

function TrapObject:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return TrapObject
