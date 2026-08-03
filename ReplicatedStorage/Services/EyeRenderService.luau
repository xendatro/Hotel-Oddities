--- Client-only presentation for `Eye`: the stare and the float it hangs on. Every viewer turns each
--- Eye to look back at their own camera, so the thing that charges you for looking at it is always
--- looking at you, and drifts a little either side of where the server put it while it does.
---
--- Nothing here is trusted with anything and nothing here replicates. The model's parts are anchored
--- and server-owned, so a CFrame written on this machine goes no further than this screen -- which is
--- what makes a per-viewer stare possible at all: four players in a corridor are each stared at, and
--- no two of them have to agree about where it is pointing. A client that lied to itself about the
--- angle would see an Eye looking somewhere it is not, and would be billed for looking at it on
--- precisely the same terms either way. The server neither knows nor cares which way it faces.
---
--- It is aimed at the camera rather than at the character because the camera is what the damage is
--- scored off in `Eye:GetViewAngle` -- pointing it anywhere else would be an Eye that avoids your eye
--- while it bills you for meeting its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bob = require(ReplicatedStorage.Modules.Bob)
local EyeConfig = require(ReplicatedStorage.Configs.EyeConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)

local EYE_TAG = "Eye"
local IGNORE_TAG = "Ignore" -- on your character: nothing in the hotel can see you (the spell book)
local MINIMUM_DIRECTION = 1e-3
local RENDER_BIND_NAME = "EyeRender"

local EyeRenderService = {}

if not FLAGS.Enemies then
	return EyeRenderService
end

local localPlayer = Players.LocalPlayer

type Render = {
	Anchor: Vector3, -- where the server put it, which the bob is measured either side of
	Phase: number,
	Aimed: boolean, -- whether it has been pointed at this camera yet, which the first aim skips ahead
}

local Eyes: { [Model]: Render } = {}

TagService:Listen(EYE_TAG, function(model: Instance): Render
	-- The true position is read once and kept. Every frame after this writes a bobbed one, so asking
	-- the model where it is would be asking it where this service last drew it -- and a bob measured
	-- from that would climb the corridor a third of a stud at a time. An Eye never moves, so the one
	-- reading stays good for as long as the model is alive.
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

	-- Hidden by the spell book means hidden from this too. It keeps whatever angle it had rather than
	-- looking away, and it keeps floating -- an Eye that lost you is still an Eye. What the book buys
	-- is that it stops following, in the one place a player can stand and watch it stop.
	local character = localPlayer.Character
	local tracking = not (character and character:HasTag(IGNORE_TAG))

	local clock = os.clock()
	local cameraPosition = camera.CFrame.Position
	for model, render in Eyes do
		local position = render.Anchor
			+ Bob.Offset(clock, render.Phase, EyeConfig.BobHeight, EyeConfig.BobPeriod)
		local rotation = model:GetPivot().Rotation
		local distance = (cameraPosition - position).Magnitude

		if tracking and distance > MINIMUM_DIRECTION and distance < EyeConfig.TrackRange then
			-- The mesh's pupil sits on the model's own LookVector, so aiming it is the whole of this.
			local goal = CFrame.lookAt(position, cameraPosition).Rotation
			rotation = if render.Aimed
				-- Framerate independent: the same fraction of the angle left per second of real time
				-- rather than per frame, so it does not turn faster on a better machine.
				then rotation:Lerp(goal, 1 - math.exp(-EyeConfig.TurnRate * deltaTime))
				-- The first aim is instant, and unseen. An Eye spawns out of everybody's sight and
				-- facing away from whoever it was drawn for, so easing from that would spend its
				-- first second sweeping around from wherever the server happened to leave it.
				else goal
			render.Aimed = true
		end

		model:PivotTo(rotation + position)
	end
end)

return EyeRenderService
