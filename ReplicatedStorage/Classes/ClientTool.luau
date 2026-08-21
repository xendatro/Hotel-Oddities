local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolBase = require(ReplicatedStorage.Classes.ToolBase)

local Delete = ReplicatedStorage.Communication.Backpack.Delete

local ClientTool = ToolBase.extend("ClientTool")

local LIMB_PARTS = {
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local DEFAULT_TRANSPARENCY = 0.5
local BIND_NAME = "ToolLimbReveal"

local player = Players.LocalPlayer

local revealers = 0
local transparency = DEFAULT_TRANSPARENCY

local function isFirstPerson(character: Model): boolean
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then return true end

	local head = character:FindFirstChild("Head")
	return head ~= nil and head.LocalTransparencyModifier > 0.5
end

local function applyReveal()
	local character = player.Character
	if not character then return end

	for _, partName in LIMB_PARTS do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.LocalTransparencyModifier = transparency
		end
	end
end

local function startReveal(value: number): boolean
	local character = player.Character
	if not character then return false end

	if revealers == 0 and not isFirstPerson(character) then return false end

	transparency = value
	revealers += 1
	if revealers > 1 then return true end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, applyReveal)
	return true
end

local function stopReveal()
	if revealers <= 0 then return end
	revealers -= 1
	if revealers > 0 then return end

	RunService:UnbindFromRenderStep(BIND_NAME)

	local character = player.Character
	if not character then return end
	for _, partName in LIMB_PARTS do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end
end

function ClientTool.extend(className: string)
	local class = setmetatable({}, { __index = ClientTool })
	class.__index = class
	class.ClassName = className
	return class
end

function ClientTool.new(tool: Tool, class: any?)
	return ToolBase.new(tool, class or ClientTool)
end

function ClientTool:Consume(n: number?)
	Delete:FireServer(self.Name, n or 1)
end

function ClientTool:WaitForToolAnimation(animationName: string, timeout: number?): AnimationTrack?
	local humanoid = self.Humanoid
	local animations = self.Tool:FindFirstChild("Animations")
	local animation = animations and animations:FindFirstChild(animationName)
	if not humanoid or not animation then return nil end

	for _, track in humanoid.Animator:GetPlayingAnimationTracks() do
		if track.Animation == animation then return track end
	end

	local thread = coroutine.running()
	local resolved = false
	local found: AnimationTrack? = nil

	local function finish(track: AnimationTrack?)
		if resolved then return end
		resolved = true
		found = track
		task.spawn(thread)
	end

	local connection = humanoid.Animator.AnimationPlayed:Connect(function(track: AnimationTrack)
		if track.Animation == animation then
			finish(track)
		end
	end)
	task.delay(timeout or 2, finish)

	coroutine.yield()
	connection:Disconnect()
	return found
end

function ClientTool:RevealLimbs()
	if self.Revealing then return end
	self.Revealing = startReveal(self.Config.LimbTransparency or DEFAULT_TRANSPARENCY)
end

function ClientTool:ReleaseLimbs()
	if not self.Revealing then return end
	self.Revealing = false
	stopReveal()
end

function ClientTool:_BeforeActivate()
	if self.Config.RevealLimbs then
		self:RevealLimbs()
	end
end

function ClientTool:_AfterActivate()
	self:ReleaseLimbs()
end

function ClientTool:OnDestroy()
	self:ReleaseLimbs()
end

return ClientTool
