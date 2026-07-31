local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolBase = require(ReplicatedStorage.Classes.ToolBase)

local Delete = ReplicatedStorage.Communication.Backpack.Delete

--- @class ClientTool
--- A tool's client half. Adds spending -- which from here is a request, since the client cannot
--- change its own inventory -- and the first-person limb reveal.
local ClientTool = ToolBase.extend("ClientTool")

--- Every R15 limb part. Head and torso are deliberately absent: the camera sits inside the head in
--- first person, so revealing either puts geometry across the player's view.
local LIMB_PARTS = {
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local DEFAULT_TRANSPARENCY = 0.5
local BIND_NAME = "ToolLimbReveal"

local player = Players.LocalPlayer

-- One render binding shared by every tool, reference-counted. Two tools revealing at once would
-- otherwise bind the same name twice and the second would silently replace the first.
local revealers = 0
local transparency = DEFAULT_TRANSPARENCY

--- Whether the player is in first person, asked of the engine rather than measured.
---
--- The obvious test -- is the camera close to the head -- is wrong here, because the animations
--- this reveal exists for are exactly the ones that move the head. A dig bends the character over
--- and swings its head up to 2.7 studs from the locked camera, so a distance check passes and fails
--- several times a second and the limbs strobe. The engine's own decision does not wobble: it hides
--- the head in first person and shows it otherwise.
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

-- Returns whether the reveal actually started, so a caller that was declined does not later release
-- a count it never took.
local function startReveal(value: number): boolean
	local character = player.Character
	if not character then return false end

	-- Decided once, at the start, and held for the whole action. In third person the limbs are
	-- already solid and there is nothing to reveal.
	if revealers == 0 and not isFirstPerson(character) then return false end

	transparency = value
	revealers += 1
	if revealers > 1 then return true end

	-- After the camera, not before. The first-person transparency pass runs during the camera
	-- update, so anything written earlier in the frame is overwritten before it ever renders.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, applyReveal)
	return true
end

local function stopReveal()
	if revealers <= 0 then return end
	revealers -= 1
	if revealers > 0 then return end

	RunService:UnbindFromRenderStep(BIND_NAME)

	-- Hand the limbs back to the engine, which re-decides their transparency next frame.
	local character = player.Character
	if not character then return end
	for _, partName in LIMB_PARTS do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end
end

--- Creates a subclass of ClientTool.
function ClientTool.extend(className: string)
	local class = setmetatable({}, { __index = ClientTool })
	class.__index = class
	class.ClassName = className
	return class
end

function ClientTool.new(tool: Tool, class: any?)
	return ToolBase.new(tool, class or ClientTool)
end

--- Asks the server to spend `n` from the stack. The server re-checks the amount, so this is a
--- request rather than an instruction.
function ClientTool:Consume(n: number?)
	Delete:FireServer(self.Name, n or 1)
end

--- Waits for one of this tool's own animations to start playing, and returns its track.
---
--- Needed because a tool's animation may be played by its SERVER half -- the spell book's is --
--- in which case the client never loaded the track and can only observe it arriving. Matching is by
--- Animation instance identity, so another tool's animation cannot be mistaken for this one's.
function ClientTool:WaitForToolAnimation(animationName: string, timeout: number?): AnimationTrack?
	local humanoid = self.Humanoid
	local animations = self.Tool:FindFirstChild("Animations")
	local animation = animations and animations:FindFirstChild(animationName)
	if not humanoid or not animation then return nil end

	-- It may already be running by the time we look.
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

--- Limb reveal ------------------------------------------------------------------------------------

--- Fades this player's own limbs in so they can see the animation they are playing. Local only --
--- `LocalTransparencyModifier` never replicates, so nobody else's view changes.
function ClientTool:RevealLimbs()
	if self.Revealing then return end
	self.Revealing = startReveal(self.Config.LimbTransparency or DEFAULT_TRANSPARENCY)
end

--- Hands the limbs back to the engine. Safe to call when not revealing.
function ClientTool:ReleaseLimbs()
	if not self.Revealing then return end
	self.Revealing = false
	stopReveal()
end

-- Tools with `RevealLimbs` in their config get this for the whole activation automatically. Because
-- it is bracketed by the chassis rather than written into each tool, it releases even when the
-- action errors, times out on a missing animation marker, or the player dies mid-swing.
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
