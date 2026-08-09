local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local TagService = require(ReplicatedStorage.Services.TagService)

local Create = ReplicatedStorage.Communication.Hole.Create
local Other = ReplicatedStorage.Props.Other
local MAZE_FLOOR_TAG = "MazeFloor"

--- @class Shovel
--- Digs an escape hole. The player is rooted for the dig while a widening placeholder opens under
--- them; when it finishes the server is asked to cut the real hole pair. Digging in midair is
--- refused outright, so the dig cannot be started off a ledge.
local Shovel = ClientTool.extend("Shovel")

function Shovel.new(tool: Tool)
	return ClientTool.new(tool, Shovel)
end

function Shovel:OnEquipped()
	local animations = self.Tool:FindFirstChild("Animations")
	local animation = animations and animations:FindFirstChild("Equip")
	if not animation or not self.Humanoid then return end

	self.EquipTrack = self.Humanoid.Animator:LoadAnimation(animation)
	self.EquipTrack.Priority = Enum.AnimationPriority.Action
	self.EquipTrack:Play(0.25)
end

function Shovel:OnUnequipped()
	if self.EquipTrack then
		self.EquipTrack:Stop()
		self.EquipTrack = nil
	end
end

-- Grows the placeholder hole. Model:ScaleTo is a method rather than a property, so the tween drives
-- a NumberValue and the scale follows it.
function Shovel:_growHole(hole: Model)
	local scale = Instance.new("NumberValue")
	scale.Value = self.Config.HoleStartScale

	local connection = scale:GetPropertyChangedSignal("Value"):Connect(function()
		if hole.Parent then
			hole:ScaleTo(scale.Value)
		end
	end)

	local tween = TweenService:Create(
		scale,
		TweenInfo.new(self.Config.HoleGrowTime, Enum.EasingStyle.Linear),
		{ Value = self.Config.HoleEndScale }
	)
	tween.Completed:Once(function()
		connection:Disconnect()
		scale:Destroy()
	end)
	tween:Play()
end

function Shovel:OnActivated()
	local character = self.Character
	local humanoid = self.Humanoid
	if not character or not humanoid then return end

	local animations = self.Tool:FindFirstChild("Animations")
	local digAnimation = animations and animations:FindFirstChild("Dig")
	local template = Other:FindFirstChild("DummyHole")
	if not digAnimation or not template then
		warn("Shovel: missing Dig animation or DummyHole prop")
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = TagService:GetTaggedOfAncestor(workspace, MAZE_FLOOR_TAG)
	if #params.FilterDescendantsInstances == 0 then
		warn(`Shovel: no parts tagged "{MAZE_FLOOR_TAG}" -- there is nowhere to dig`)
		return
	end

	local ground = workspace:Raycast(character:GetPivot().Position, Vector3.new(0, -self.Config.DigDepth, 0), params)
	if not ground then return end -- only MazeFloor can be dug

	local entry = ground.Position + Vector3.new(0, 0.5, 0)
	self:PlaySound(self.Config.Sound, character.PrimaryPart)

	local dummy = template:Clone()
	local x, y, z = dummy:GetPivot():ToOrientation()
	dummy:PivotTo(CFrame.new(entry) * CFrame.fromOrientation(x, y, z))
	dummy:ScaleTo(self.Config.HoleStartScale)
	dummy.Parent = workspace
	self.Dummy = dummy

	self.DigSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0

	local track = humanoid.Animator:LoadAnimation(digAnimation)
	track.Priority = Enum.AnimationPriority.Action2
	track:Play()
	self.DigTrack = track

	self:_growHole(dummy)

	-- Bounded rather than a bare `track.Ended:Wait()`: an interrupted or missing animation used to
	-- leave the player rooted at WalkSpeed 0 with the placeholder hole stuck in the world.
	self:WaitForTrack(track, self.Config.HoleGrowTime + 3)

	if not self:IsAlive() then return end

	-- Spending the last shovel ends the equip pose with it.
	if self:GetQuantity() <= 1 and self.EquipTrack then
		self.EquipTrack:Stop()
	end

	self:Consume(1)
	Create:InvokeServer(entry)
end

function Shovel:OnCleanup()
	if self.Dummy then
		self.Dummy:Destroy()
		self.Dummy = nil
	end
	if self.DigTrack then
		self.DigTrack:Stop()
		self.DigTrack = nil
	end

	local humanoid = self.Humanoid
	if humanoid and humanoid.Health > 0 and self.DigSpeed then
		humanoid.WalkSpeed = self.DigSpeed
	end
	self.DigSpeed = nil
end

function Shovel:OnDestroy()
	self:OnCleanup()
end

return Shovel
