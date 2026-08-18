--- Sprinting, and the stamina it costs. Held on Shift or the gamepad's left trigger, toggled from a
--- screen button on touch. Stamina only drains while the player is actually moving, and starts
--- filling again a moment after they stop sprinting; running it dry locks sprinting out until the
--- bar has filled completely, which stopping short of empty never costs.
---
--- Speed is multiplied rather than assigned, so this stacks with a drink instead of replacing it.
--- The multiplier is written on top of whatever base speed something else last chose, and the base
--- is re-read whenever anyone else changes it -- including the rooting a shovel or a spell book
--- does, which is left alone rather than treated as a new walking speed.
---
--- Nothing here is authoritative. Sprint speed is a client's own walk speed, which the client
--- already owns; the server is told nothing because nothing on the server asks.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
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

local player = Players.LocalPlayer

type CharacterState = {
	Humanoid: Humanoid,
	BaseSpeed: number,
	LastWritten: number,
	--- Something else is holding the player at zero -- a shovel dig, a spell book cast. Their write
	--- owns the speed until they give it back, and the value they restore is ours, not a new base.
	Suppressed: boolean,
	Writing: boolean,
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

--- Speed ----------------------------------------------------------------------------------------

local function writeSpeed(state: CharacterState, speed: number)
	state.Writing = true
	state.Humanoid.WalkSpeed = speed
	state.Writing = false
	state.LastWritten = speed
end

local function applySpeed()
	local state = characterState
	if not state or state.Suppressed or state.BaseSpeed <= 0 then return end

	local desired = if sprinting then state.BaseSpeed * SprintConfig.SpeedMultiplier else state.BaseSpeed
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
		-- Rooting code restores the value it read before it rooted the player. If that was our own
		-- sprint speed, keep the base we already had instead of promoting a boosted number.
		if math.abs(speed - state.LastWritten) > 0.01 then
			state.BaseSpeed = speed
		end
	elseif math.abs(speed - state.LastWritten) <= 0.01 then
		-- Our own write coming back around.
		return
	else
		state.BaseSpeed = speed
	end

	applySpeed()
end

--- Stamina --------------------------------------------------------------------------------------

local function canSprint(state: CharacterState?): boolean
	if not state or state.Suppressed or state.BaseSpeed <= 0 then return false end

	local humanoid = state.Humanoid
	return humanoid.Health > 0 and humanoid.MoveDirection.Magnitude > MOVEMENT_THRESHOLD
end

local function step(deltaTime: number)
	-- Spending the bar down to nothing costs the whole recharge, not part of it: nothing lifts the
	-- lockout short of a full bar. Stopping before it empties is free.
	if exhausted and stamina >= STAMINA.Max then
		exhausted = false
	end

	local wants = held or toggled
	local shouldSprint = wants and not exhausted and stamina > 0 and canSprint(characterState)
	if shouldSprint ~= sprinting then
		sprinting = shouldSprint
		applySpeed()
	end

	if sprinting then
		idleTime = 0
		stamina = math.max(stamina - STAMINA.DrainRate * deltaTime, 0)
		if stamina <= 0 then
			exhausted = true
			-- A toggle the player can no longer act on should not survive the recharge and start
			-- them sprinting again the moment the bar fills.
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
	weight += (target - weight) * (1 - math.exp(-CAMERA.BlendSpeed * deltaTime))
	if weight < 1e-3 then weight = 0 end
	CameraFovService:SetOffset("Sprint", weight * CAMERA.FovBoost)
end

--- Reading the state ----------------------------------------------------------------------------

--- Stamina left, from 0 to 1. What the bar draws.
function SprintService:GetStaminaFraction(): number
	return stamina / STAMINA.Max
end

--- Whether the player is sprinting right now, rather than merely asking to.
function SprintService:IsSprinting(): boolean
	return sprinting
end

--- True while the bar has been run dry and sprinting is locked out. Ends only once it is full.
function SprintService:IsExhausted(): boolean
	return exhausted
end

--- How far the sprint's camera work has blended in, from 0 to 1. Shared so the step motion and the
--- field of view swell together instead of each easing on its own clock.
function SprintService:GetWeight(): number
	return weight
end

--- The character --------------------------------------------------------------------------------

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

	local state: CharacterState = {
		Humanoid = humanoid,
		BaseSpeed = humanoid.WalkSpeed,
		LastWritten = humanoid.WalkSpeed,
		Suppressed = humanoid.WalkSpeed <= 0,
		Writing = false,
		Connections = {},
	}
	characterState = state
	stamina = STAMINA.Max
	exhausted = false
	idleTime = 0

	table.insert(state.Connections, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		onWalkSpeedChanged(state)
	end))
	table.insert(state.Connections, humanoid.Died:Connect(unbindCharacter))
end

--- Input ----------------------------------------------------------------------------------------

local function onHold(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		held = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		held = false
	end
	return Enum.ContextActionResult.Pass
end

local function onToggle(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
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
