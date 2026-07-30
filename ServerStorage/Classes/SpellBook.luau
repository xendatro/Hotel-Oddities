local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local Other = ReplicatedStorage.Props.Other

local IGNORE_TAG = "Ignore" -- read by NPC:IsValidTarget / NPC:CanSee

--- @class SpellBook
--- A one-shot vanish. Reading it roots the player for the length of the cast, and for that whole
--- window their character carries `Ignore`, which every enemy's perception refuses to target --
--- so the cast is both the cost and the escape. Consumed when the animation finishes.
local SpellBook = {}
SpellBook.__index = SpellBook

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Equipped = self.SpellBook.Equipped:Connect(function()
		self.Character = self.SpellBook.Parent
	end)

	self.Connections.Activated = self.SpellBook.Activated:Connect(function()
		self:Activated()
	end)
end

function SpellBook.new(spellBook: Tool)
	local self = setmetatable({}, SpellBook)

	self.SpellBook = spellBook
	self.Character = nil
	self.Playing = false

	setUpConnections(self)

	return self
end

function SpellBook:Activated()
	if self.Playing or not self.Character then return end

	local player = Players:GetPlayerFromCharacter(self.Character)
	local humanoid = self.Character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid then return end

	self.Playing = true
	self.Character:AddTag(IGNORE_TAG)

	local track = humanoid.Animator:LoadAnimation(self.SpellBook.Animations.Book)
	track:Play()
	AudioService:Play3DSound("SpellBook", self.SpellBook.Handle, false, "SFX")

	-- The book's own particles ride along with the mesh; the dummy carries the effect that plays
	-- on the reader. Both are welded off and destroyed together when the cast ends.
	local effects = Other.BookEffects:Clone()
	local reader = Other.VFXDummy:Clone()

	local followThread = task.spawn(function()
		task.wait(1)
		effects.Parent = workspace
		for _, effect in effects.Attachment:GetChildren() do
			effect.Enabled = true
		end

		local mesh = self.SpellBook:FindFirstChild("Meshes/Unrigged")
		while mesh and RunService.Heartbeat:Wait() do
			effects:PivotTo(mesh.CFrame)
		end
	end)

	task.delay(1.8, function()
		if not reader.Parent and self.Character.PrimaryPart then
			reader.Parent = workspace
			reader:PivotTo(self.Character:GetPivot())

			local motor = Instance.new("Motor6D")
			motor.Part0 = self.Character.PrimaryPart
			motor.Part1 = reader.PrimaryPart
			motor.Parent = reader.PrimaryPart
		end
	end)

	local speed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	track:GetMarkerReachedSignal("BookEnd"):Wait()

	task.cancel(followThread)
	for _, effect in effects.Attachment:GetChildren() do
		effect.Enabled = false
	end
	humanoid.WalkSpeed = speed

	track.Ended:Wait()
	effects:Destroy()
	reader:Destroy()

	InventoryService:Remove(player, self.SpellBook.Name, 1)
	self.Character:RemoveTag(IGNORE_TAG)
	self.Playing = false
end

function SpellBook:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	if self.Character then
		self.Character:RemoveTag(IGNORE_TAG)
	end
end

return SpellBook
