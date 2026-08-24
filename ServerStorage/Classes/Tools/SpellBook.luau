local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local Other = ReplicatedStorage.Props.Other

local SpellBook = ServerTool.extend("SpellBook")

function SpellBook.new(tool: Tool)
	return ServerTool.new(tool, SpellBook)
end

function SpellBook:OnActivated()
	local humanoid = self.Humanoid
	local character = self.Character
	if not humanoid or not character then return end

	local animations = self.Tool:FindFirstChild("Animations")
	local animation = animations and animations:FindFirstChild("Book")
	if not animation then
		warn("SpellBook: no Book animation on the tool")
		return
	end

	character:AddTag(Vanished.Tag)
	self.CastCharacter = character
	self.CastSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0

	local track = humanoid.Animator:LoadAnimation(animation)
	self.CastTrack = track
	track:Play()
	self:PlaySound(self.Config.Sound, self.Tool:FindFirstChild("Handle"))

	self:_startEffects()

	self:WaitForMarker(track, "BookEnd", self.Config.MaxCastTime)

	if self:IsAlive() then
		self:Consume(1)
	end
end

function SpellBook:_startEffects()
	local effects = Other:FindFirstChild("BookEffects")
	local dummy = Other:FindFirstChild("VFXDummy")

	if effects then
		self.Effects = effects:Clone()
		self.FollowActive = true

		task.spawn(function()
			task.wait(self.Config.EffectDelay)
			if not self.FollowActive or not self.Effects then return end

			self.Effects.Parent = workspace
			for _, effect in self.Effects.Attachment:GetChildren() do
				effect.Enabled = true
			end

			while self.FollowActive do
				local mesh = self.Tool:FindFirstChild("Meshes/Unrigged")
				if mesh and self.Effects then
					self.Effects:PivotTo(mesh.CFrame)
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	if dummy then
		self.Reader = dummy:Clone()

		task.spawn(function()
			task.wait(self.Config.ReaderDelay)
			local character = self.CastCharacter
			if not self.Reader or not character or not character.PrimaryPart then return end

			self.Reader.Parent = workspace
			self.Reader:PivotTo(character:GetPivot())

			local motor = Instance.new("Motor6D")
			motor.Part0 = character.PrimaryPart
			motor.Part1 = self.Reader.PrimaryPart
			motor.Parent = self.Reader.PrimaryPart
		end)
	end
end

function SpellBook:OnCleanup()
	self.FollowActive = false

	if self.CastTrack then
		self.CastTrack:Stop()
		self.CastTrack = nil
	end

	if self.Effects then
		self.Effects:Destroy()
		self.Effects = nil
	end
	if self.Reader then
		self.Reader:Destroy()
		self.Reader = nil
	end

	local character = self.CastCharacter
	if character then
		character:RemoveTag(Vanished.Tag)

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and self.CastSpeed then
			humanoid.WalkSpeed = self.CastSpeed
		end
	end

	self.CastCharacter = nil
	self.CastSpeed = nil
end

function SpellBook:OnDestroy()
	self:OnCleanup()
end

return SpellBook
