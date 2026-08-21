local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)
local SprintService = require(ReplicatedStorage.Services.SprintService)

local CrouchService = {}

if not RunService:IsClient() then
	return CrouchService
end

local CAMERA = CrouchConfig.Camera
local BODY = CrouchConfig.Body
local TOUCH = CrouchConfig.Touch
local FACTOR_NAME = "Crouch"
local STEP_JOB = "CrouchStep"

local player = Players.LocalPlayer

local Update = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Crouch")
	:WaitForChild("Update") :: RemoteEvent

type CharacterState = {
	Humanoid: Humanoid,
	Root: BasePart,
	BaseHipHeight: number,
	Idle: AnimationTrack?,
	Walk: AnimationTrack?,
	Connections: { RBXScriptConnection },
}

local characterState = nil :: CharacterState?
local crouched = false
local weight = 0
local touchButton: TextButton? = nil
local touchStroke: UIStroke? = nil

local function canCrouch(): boolean
	local state = characterState
	return state ~= nil and state.Humanoid.Health > 0
end

local function paintTouchButton()
	local button, stroke = touchButton, touchStroke
	if not button or not stroke then return end

	local colors = TOUCH.Colors
	button.BackgroundColor3 = if crouched then colors.ActiveBackground else colors.Background
	button.TextColor3 = if crouched then colors.ActiveText else colors.Text
	button.BackgroundTransparency = if crouched then 0 else TOUCH.Transparency.Background
	stroke.Color = if crouched then colors.ActiveStroke else colors.Stroke
	stroke.Transparency = if crouched then 0 else TOUCH.Transparency.Stroke
end

local function setCrouched(value: boolean)
	if value and not canCrouch() then return end
	if crouched == value then return end

	crouched = value
	Update:FireServer(value)
	SprintService:SetSpeedFactor(FACTOR_NAME, if value then CrouchConfig.SpeedMultiplier else nil)
	if CrouchConfig.BlocksSprint then
		SprintService:SetSprintBlocked(FACTOR_NAME, value)
	end

	local state = characterState
	if state and not value then
		if state.Idle then state.Idle:Stop(BODY.AnimationFadeTime) end
		if state.Walk then state.Walk:Stop(BODY.AnimationFadeTime) end
	end

	paintTouchButton()
end

local function updateAnimation(state: CharacterState)
	local idle, walk = state.Idle, state.Walk
	if not idle and not walk then return end

	local speed = Vector3.new(
		state.Root.AssemblyLinearVelocity.X,
		0,
		state.Root.AssemblyLinearVelocity.Z
	).Magnitude
	local moving = crouched
		and speed > BODY.WalkThreshold
		and state.Humanoid.MoveDirection.Magnitude > 0.05

	local wantIdle = crouched and (not moving or walk == nil)
	local wantWalk = crouched and moving and walk ~= nil

	if idle then
		if wantIdle and not idle.IsPlaying then
			idle:Play(BODY.AnimationFadeTime)
		elseif not wantIdle and idle.IsPlaying then
			idle:Stop(BODY.AnimationFadeTime)
		end
	end

	if walk then
		if wantWalk then
			if not walk.IsPlaying then
				walk:Play(BODY.AnimationFadeTime)
			end
			walk:AdjustSpeed(math.clamp(speed / BODY.WalkCycleSpeed, 0.35, 2.5))
		elseif walk.IsPlaying then
			walk:Stop(BODY.AnimationFadeTime)
		end
	end
end

local function step(deltaTime: number)
	if crouched and not canCrouch() then
		setCrouched(false)
	end

	local target = if crouched then 1 else 0
	weight += (target - weight) * (1 - math.exp(-CAMERA.BlendSpeed * deltaTime))
	if math.abs(target - weight) < 1e-3 then weight = target end

	local state = characterState
	if not state then return end

	updateAnimation(state)

	local humanoid = state.Humanoid
	local animated = state.Idle ~= nil or state.Walk ~= nil
	local cameraDrop = -weight * (if animated then CAMERA.DropAnimated else CAMERA.Drop)
	if math.abs(humanoid.CameraOffset.Y - cameraDrop) > 1e-3 then
		humanoid.CameraOffset = Vector3.new(0, cameraDrop, 0)
	end

	if BODY.HipDrop > 0 then
		local hipHeight = state.BaseHipHeight - weight * BODY.HipDrop
		if math.abs(humanoid.HipHeight - hipHeight) > 1e-3 then
			humanoid.HipHeight = hipHeight
		end
	end
end

function CrouchService:IsCrouching(): boolean
	return crouched
end

function CrouchService:GetWeight(): number
	return weight
end

function CrouchService:Stand()
	setCrouched(false)
end

local function unbindCharacter()
	local state = characterState
	if not state then return end

	characterState = nil
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	if state.Idle then state.Idle:Destroy() end
	if state.Walk then state.Walk:Destroy() end

	setCrouched(false)
	weight = 0
end

local function loadTrack(humanoid: Humanoid, assetId: number?): AnimationTrack?
	if not assetId then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{assetId}`

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(`CrouchService: could not load crouch animation {assetId}`)
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	return track
end

local function bindCharacter(character: Model)
	unbindCharacter()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	if player.Character ~= character then return end

	local state: CharacterState = {
		Humanoid = humanoid,
		Root = root,
		BaseHipHeight = humanoid.HipHeight,
		Idle = loadTrack(humanoid, BODY.IdleAnimationId),
		Walk = loadTrack(humanoid, BODY.WalkAnimationId),
		Connections = {},
	}
	characterState = state

	table.insert(state.Connections, humanoid.Died:Connect(unbindCharacter))
	if CrouchConfig.Input.StandOnJump then
		table.insert(state.Connections, humanoid.StateChanged:Connect(function(_old, new)
			if new == Enum.HumanoidStateType.Jumping then
				setCrouched(false)
			end
		end))
	end
end

local function buildTouchButton(parent: Instance): TextButton
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CrouchGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 9
	screenGui.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "Crouch"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = TOUCH.Position
	button.Size = TOUCH.Size
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = TOUCH.Text
	button.TextSize = TOUCH.TextSize
	button.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	button.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, TOUCH.CornerRadius)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Parent = button

	touchButton = button
	touchStroke = stroke
	paintTouchButton()
	return button
end

local function buildInput()
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
		or player:WaitForChild("PlayerScripts")

	local context = Instance.new("InputContext")
	context.Name = "CrouchContext"
	context.Sink = false

	local action = Instance.new("InputAction")
	action.Name = "Crouch"
	action.Type = Enum.InputActionType.Bool
	action.Parent = context

	for _, keyCode in CrouchConfig.Input.Keys do
		local binding = Instance.new("InputBinding")
		binding.Name = keyCode.Name
		binding.KeyCode = keyCode
		binding.Parent = action
	end

	if UserInputService.TouchEnabled then
		local binding = Instance.new("InputBinding")
		binding.Name = "Touch"
		binding.UIButton = buildTouchButton(player:WaitForChild("PlayerGui"))
		binding.Parent = action
	end

	action.Pressed:Connect(function()
		setCrouched(not crouched)
	end)

	context.Parent = playerScripts
end

buildInput()

player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(unbindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

RunService:BindToRenderStep(STEP_JOB, Enum.RenderPriority.Camera.Value - 1, step)

return CrouchService
