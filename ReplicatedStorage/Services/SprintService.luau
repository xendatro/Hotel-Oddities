local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local MathService = require(ReplicatedStorage.Services.MathService)
local SprintConfig = require(ReplicatedStorage.Configs.SprintConfig)

local SprintService = {}

if not RunService:IsClient() then
	return SprintService
end

local STAMINA = SprintConfig.Stamina
local CAMERA = SprintConfig.Camera
local HOLD_ACTION = "SprintHold"
local TOUCH_ACTION = "SprintToggle"
local STEP_JOB = "SprintStep"
local MOVEMENT_THRESHOLD = 0.05
local SPEED_BOOST_SPEED_ATTRIBUTE = "SpeedBoostSpeed"
local SPEED_BOOST_BASE_SPEED_ATTRIBUTE = "SpeedBoostBaseSpeed"

local player = Players.LocalPlayer

type CharacterState = {
	Humanoid: Humanoid,
	BaseSpeed: number,
	LastWritten: number,
	Suppressed: boolean,
	Writing: boolean,
	LastBoostedSpeed: number?,
	Connections: { RBXScriptConnection },
}

local characterState = nil :: CharacterState?
local stamina = STAMINA.Max
local held = false
local toggled = false
local sprinting = false
local exhausted = false
local idleTime = 0
local weight = 0

local speedFactors: { [string]: number } = {}
local sprintBlocks: { [string]: true } = {}

local function externalFactor(): number
	local factor = 1
	for _, value in speedFactors do
		factor *= value
	end
	return factor
end

local function writeSpeed(state: CharacterState, speed: number)
	state.Writing = true
	state.Humanoid.WalkSpeed = speed
	state.Writing = false
	state.LastWritten = speed
end

local function getBoostedSpeed(state: CharacterState): number?
	local value = player:GetAttribute(SPEED_BOOST_SPEED_ATTRIBUTE)
	if type(value) ~= "number" then return nil end

	state.LastBoostedSpeed = value
	return value
end

local function isLastBoostedSpeed(state: CharacterState, speed: number): boolean
	local boosted = state.LastBoostedSpeed
	if not boosted then return false end

	local factor = externalFactor()
	return math.abs(speed - boosted * factor) <= 0.01
		or math.abs(speed - boosted * factor * SprintConfig.SpeedMultiplier) <= 0.01
end

local function applySpeed()
	local state = characterState
	if not state or state.Suppressed or state.BaseSpeed <= 0 then return end

	local desired = state.BaseSpeed * externalFactor()
	local boosted = getBoostedSpeed(state)
	if boosted then
		desired = math.max(desired, boosted)
	end
	if sprinting then
		desired *= SprintConfig.SpeedMultiplier
	end
	if math.abs(state.Humanoid.WalkSpeed - desired) > 0.01 then
		writeSpeed(state, desired)
	end
end

local function onWalkSpeedChanged(state: CharacterState)
	if state.Writing or characterState ~= state then return end

	local speed = state.Humanoid.WalkSpeed
	if speed <= 0 then
		state.Suppressed = true
		return
	end

	if state.Suppressed then
		state.Suppressed = false
		applySpeed()
		return
	end

	if getBoostedSpeed(state) or isLastBoostedSpeed(state, speed) then
		applySpeed()
		return
	end

	if math.abs(speed - state.LastWritten) <= 0.01 then
		return
	else
		state.BaseSpeed = speed
	end

	applySpeed()
end

local function canSprint(state: CharacterState?): boolean
	if not state or state.Suppressed or state.BaseSpeed <= 0 then return false end

	local humanoid = state.Humanoid
	return humanoid.Health > 0 and humanoid.MoveDirection.Magnitude > MOVEMENT_THRESHOLD
end

local function step(deltaTime: number)
	if exhausted and stamina >= STAMINA.Max then
		exhausted = false
	end

	local wants = held or toggled
	local blocked = next(sprintBlocks) ~= nil
	local shouldSprint = wants and not blocked and not exhausted and stamina > 0 and canSprint(characterState)
	if shouldSprint ~= sprinting then
		sprinting = shouldSprint
		applySpeed()
	end

	if sprinting then
		idleTime = 0
		stamina = math.max(stamina - STAMINA.DrainRate * deltaTime, 0)
		if stamina <= 0 then
			exhausted = true
			toggled = false
			sprinting = false
			applySpeed()
		end
	elseif stamina < STAMINA.Max then
		idleTime += deltaTime
		if idleTime >= STAMINA.RegenDelay then
			stamina = math.min(stamina + STAMINA.RegenRate * deltaTime, STAMINA.Max)
		end
	end

	local target = if sprinting then 1 else 0
	weight += (target - weight) * MathService.ExpAlpha(CAMERA.BlendSpeed, deltaTime)
	if weight < 1e-3 then weight = 0 end
	CameraFovService:SetOffset("Sprint", weight * CAMERA.FovBoost)
end

function SprintService:GetStaminaFraction(): number
	return stamina / STAMINA.Max
end

function SprintService:IsSprinting(): boolean
	return sprinting
end

function SprintService:IsExhausted(): boolean
	return exhausted
end

function SprintService:GetWeight(): number
	return weight
end

function SprintService:SetSpeedFactor(name: string, factor: number?)
	if speedFactors[name] == factor then return end
	speedFactors[name] = factor
	applySpeed()
end

function SprintService:SetSprintBlocked(name: string, blocked: boolean)
	sprintBlocks[name] = if blocked then true else nil
	if blocked then
		held = false
		toggled = false
	end
end

local function unbindCharacter()
	local state = characterState
	if not state then return end

	characterState = nil
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	sprinting = false
	toggled = false
	weight = 0
	CameraFovService:SetOffset("Sprint", 0)
end

local function bindCharacter(character: Model)
	unbindCharacter()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if player.Character ~= character then return end

	local baseSpeedAttribute = player:GetAttribute(SPEED_BOOST_BASE_SPEED_ATTRIBUTE)
	local boostedSpeedAttribute = player:GetAttribute(SPEED_BOOST_SPEED_ATTRIBUTE)
	local state: CharacterState = {
		Humanoid = humanoid,
		BaseSpeed = if type(baseSpeedAttribute) == "number"
			then baseSpeedAttribute
			else humanoid.WalkSpeed,
		LastWritten = humanoid.WalkSpeed,
		Suppressed = humanoid.WalkSpeed <= 0,
		Writing = false,
		LastBoostedSpeed = if type(boostedSpeedAttribute) == "number" then boostedSpeedAttribute else nil,
		Connections = {},
	}
	characterState = state
	stamina = STAMINA.Max
	exhausted = false
	idleTime = 0

	table.insert(state.Connections, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		onWalkSpeedChanged(state)
	end))
	table.insert(state.Connections, player:GetAttributeChangedSignal(SPEED_BOOST_SPEED_ATTRIBUTE):Connect(function()
		if characterState == state then
			applySpeed()
		end
	end))
	table.insert(state.Connections, humanoid.Died:Connect(unbindCharacter))
end

local function onHold(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		if next(sprintBlocks) ~= nil then return Enum.ContextActionResult.Pass end
		held = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		held = false
	end
	return Enum.ContextActionResult.Pass
end

local function onToggle(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		if next(sprintBlocks) ~= nil then return Enum.ContextActionResult.Pass end
		toggled = not toggled
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(HOLD_ACTION, onHold, false, table.unpack(SprintConfig.Input.HoldKeys))

if UserInputService.TouchEnabled then
	local INPUT = SprintConfig.Input
	ContextActionService:BindAction(TOUCH_ACTION, onToggle, true)
	ContextActionService:SetTitle(TOUCH_ACTION, INPUT.TouchButtonTitle)
	ContextActionService:SetPosition(TOUCH_ACTION, INPUT.TouchButtonPosition)

	local button = ContextActionService:GetButton(TOUCH_ACTION)
	if button then
		button.Size = INPUT.TouchButtonSize
	end
end

player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(unbindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

RunService:BindToRenderStep(STEP_JOB, Enum.RenderPriority.Camera.Value - 1, step)

return SprintService
