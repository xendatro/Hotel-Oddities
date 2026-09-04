local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local HolePlacementService = require(ReplicatedStorage.Services.HolePlacementService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local Create = CommunicationService.Get("Hole", "Create")
local Other = ReplicatedStorage.Props.Other

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

function Shovel:_growHole(hole: Model)
	local tween = TweenProxyService.ScaleModel(
		hole,
		self.Config.HoleStartScale,
		self.Config.HoleEndScale,
		TweenInfo.new(self.Config.HoleGrowTime, Enum.EasingStyle.Linear)
	)
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

	local floors = HolePlacementService.GetFloors(workspace)
	if #floors == 0 then
		warn("Shovel: no tagged floor parts -- nothing to dig into")
		return
	end

	local ground = HolePlacementService.FindGround(character:GetPivot().Position, self.Config.DigDepth, floors)
	if not ground then return end

	local entry = ground.Position + Vector3.new(0, 0.5, 0)
	local footprintTemplate = (Other:FindFirstChild("Hole") or template) :: Model
	if not HolePlacementService.IsFootprintSupported(entry, footprintTemplate, floors, 1, ground.Position.Y) then
		return
	end

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

	self:WaitForTrack(track, self.Config.HoleGrowTime + 3)

	if not self:IsAlive() then return end

	if Create:InvokeServer(entry) then
		if self:GetQuantity() <= 1 and self.EquipTrack then
			self.EquipTrack:Stop()
		end
		self:Consume(1)
	end
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
