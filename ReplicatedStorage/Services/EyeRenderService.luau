local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Aim = require(ReplicatedStorage.Services.AimService)
local Bob = require(ReplicatedStorage.Services.BobService)
local EyeConfig = require(ReplicatedStorage.Configs.EyeConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local Sightline = require(ReplicatedStorage.Services.SightlineService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local EyeHitEffectService = require(ReplicatedStorage.Services.EyeHitEffectService)
local MathService = require(ReplicatedStorage.Services.MathService)
local TagService = require(ReplicatedStorage.Services.TagService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local EYE_TAG = "Eye"
local STUNNED_ATTRIBUTE = "Stunned"
local MINIMUM_DIRECTION = 1e-3
local RENDER_BIND_NAME = "EyeRender"

local EyeRenderService = {}

if not FLAGS.Enemies then
	return EyeRenderService
end

local localPlayer = Players.LocalPlayer

type Render = {
	Anchor: Vector3,
	Phase: number,
	Aimed: boolean,
}

local Eyes: { [Model]: Render } = {}

TagService:Listen(EYE_TAG, function(model: Instance): Render
	local render: Render = {
		Anchor = (model :: Model):GetPivot().Position,
		Phase = Bob.NewPhase(),
		Aimed = false,
	}
	Eyes[model :: Model] = render
	return render
end, function(model: Instance)
	Eyes[model :: Model] = nil
end, workspace)

RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local character = localPlayer.Character
	local tracking = not Vanished.Is(character)
	local threatened = tracking and CharacterService.GetAliveHumanoid(localPlayer) ~= nil
	local frustum = Sightline.Frustum(camera)

	local clock = os.clock()
	local cameraPosition = camera.CFrame.Position
	local gazeStrength = 0
	for model, render in Eyes do
		local position = render.Anchor
			+ Bob.Offset(clock, render.Phase, EyeConfig.BobHeight, EyeConfig.BobPeriod)
		local rotation = model:GetPivot().Rotation
		local distance = (cameraPosition - position).Magnitude

		if model:GetAttribute(STUNNED_ATTRIBUTE) then
			local goal = CFrame.lookAt(position, position - Vector3.yAxis, Vector3.zAxis).Rotation
			rotation = Aim.Ease(rotation, goal, EyeConfig.StunTurnRate, deltaTime)
			render.Aimed = true
		elseif tracking and distance > MINIMUM_DIRECTION and distance < EyeConfig.TrackRange then
			local goal = Aim.Toward(position, cameraPosition)
			rotation = if render.Aimed
				then Aim.Ease(rotation, goal, EyeConfig.TurnRate, deltaTime)
				else goal
			render.Aimed = true
		end

		model:PivotTo(rotation + position)

		local offset = position - cameraPosition
		local distance = offset.Magnitude
		if threatened
			and frustum
			and distance > MINIMUM_DIRECTION
			and distance <= EyeConfig.GazeRange
			and not model:GetAttribute(STUNNED_ATTRIBUTE)
			and Sightline.CanSee(camera, frustum, character, model)
		then
			local angle = MathService.AngleBetween(offset, camera.CFrame.LookVector)
			local centered = math.clamp(1 - angle / EyeConfig.GazeFalloffAngle, 0, 1)
			local strength = EyeConfig.GazeEdgeIntensity
				+ (1 - EyeConfig.GazeEdgeIntensity) * centered * centered
			gazeStrength = math.max(gazeStrength, strength)
		end
	end
	EyeHitEffectService:UpdateGaze(gazeStrength, deltaTime)
end)

return EyeRenderService
