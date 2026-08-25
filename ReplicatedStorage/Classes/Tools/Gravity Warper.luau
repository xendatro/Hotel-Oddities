local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local WallstickService = require(ReplicatedStorage.Services.WallstickService)

local GravityWarper = ClientTool.extend("GravityWarper")

function GravityWarper.new(tool: Tool)
	local self = ClientTool.new(tool, GravityWarper)
	self.Warping = false
	self:On("Warp", function(duration: number)
		task.spawn(function()
			self:_Warp(duration)
		end)
	end)
	return self
end

local function rayParamsFor(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	return params
end

local function tweenRoot(root: BasePart, goal: CFrame, time: number)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local tween = TweenService:Create(
		root,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ CFrame = goal }
	)
	tween:Play()
	tween.Completed:Wait()
	root.Anchored = false
end

function GravityWarper:_Warp(duration: number)
	if self.Warping then return end

	local character = Players.LocalPlayer.Character
	local humanoid = CharacterService.GetHumanoid(character)
	local root = character and CharacterService.GetAliveRootFromCharacter(character)
	if not character or not humanoid or not root then return end

	local params = rayParamsFor(character)
	local ceiling = workspace:Raycast(root.Position, Vector3.new(0, self.Config.MaxCeilingDistance, 0), params)
	if not ceiling then return end

	self.Warping = true

	local hipHeight = humanoid.HipHeight
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		hipHeight = 2
	end
	local clearance = hipHeight + root.Size.Y / 2 + 0.05

	local rotation = root.CFrame.Rotation
	local flipped = rotation * CFrame.Angles(0, 0, math.pi)
	tweenRoot(root, CFrame.new(ceiling.Position - Vector3.new(0, clearance, 0)) * flipped, self.Config.AscendTime)

	if not CharacterService.IsAlive(character) then
		self.Warping = false
		return
	end

	WallstickService.Enable()

	local elapsed = 0
	while elapsed < duration do
		elapsed += task.wait(0.1)
		if not CharacterService.IsAlive(character) or root.Parent == nil then
			self.Warping = false
			return
		end
	end

	WallstickService.Disable()

	if CharacterService.IsAlive(character) and root.Parent ~= nil then
		local uprightRotation = root.CFrame.Rotation * CFrame.Angles(0, 0, math.pi)
		local floor = workspace:Raycast(root.Position, Vector3.new(0, -self.Config.MaxCeilingDistance, 0), params)
		local goalPosition = floor and floor.Position + Vector3.new(0, clearance, 0)
			or root.Position - Vector3.new(0, 4, 0)
		tweenRoot(root, CFrame.new(goalPosition) * uprightRotation, self.Config.DescendTime)
	end

	self.Warping = false
end

function GravityWarper:OnDestroy()
	if self.Warping then
		self.Warping = false
		WallstickService.Disable()
	end
end

return GravityWarper
