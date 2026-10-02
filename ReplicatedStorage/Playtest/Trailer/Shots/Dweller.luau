-- A ceiling vent ahead bangs open, grit sifts down, and the Ceiling Dweller
-- drops through it, lands in a ring of dust and comes straight at the lens.
-- The vent is a local clone of the game's template, hung the way
-- ProgrammaticVentService hangs one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lens = require(script.Parent.Parent.Lens)

local VENT = CFrame.new(40, -11.289, -96) * CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.yAxis, Vector3.new(-1, 0, 0))
local FLOOR = Vector3.new(40, -22.547, -96)
local OPEN_ANGLE = math.rad(-100)
local STANDING = 3.45

local WALK = 131708679301818
local ATTACK = 79774778049507

local OPEN_AT = 0.4
local OPEN_TIME = 0.65
local DROP_AT = 0.95
local LUNGE_AT = 1.45
local ATTACK_AT = 1.35
local RUN_SPEED = 14
local LUNGE_DISTANCE = 3

local CAMERA = Vector3.new(53.5, -18.6, -94.9)

local function bounce(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	if alpha < 1 / 2.75 then
		return 7.5625 * alpha * alpha
	elseif alpha < 2 / 2.75 then
		alpha -= 1.5 / 2.75
		return 7.5625 * alpha * alpha + 0.75
	elseif alpha < 2.5 / 2.75 then
		alpha -= 2.25 / 2.75
		return 7.5625 * alpha * alpha + 0.9375
	end
	alpha -= 2.625 / 2.75
	return 7.5625 * alpha * alpha + 0.984375
end

return {
	Duration = 2.5,
	Warmup = 3,
	Park = CFrame.new(10, -19.6, -96),
	Stream = { FLOOR, VENT.Position },
	Handheld = Lens.Handheld(61, 1.1),
	Keys = Lens.Unwrap({
		Lens.Key(0, CAMERA, Vector3.new(40, -13.2, -96), { Fov = 50, Roll = 0, Handheld = 0.8 }),
		Lens.Key(DROP_AT, CAMERA + Vector3.new(-0.7, 0, 0), Vector3.new(40, -13.8, -96), { Fov = 48, Handheld = 0.9 }),
		Lens.Key(DROP_AT + 0.45, CAMERA + Vector3.new(-0.85, -0.08, 0), Vector3.new(40, -17.2, -96), { Fov = 47, Roll = 1, Handheld = 1.3 }),
		Lens.Key(2.5, CAMERA + Vector3.new(-0.3, -0.2, 0.1), Vector3.new(42, -17.3, -95.8), { Fov = 52, Roll = -1.5, Handheld = 1.6 }),
	}),

	Setup = function(stage)
		local vent = ReplicatedStorage.Props.Other.Vent:Clone()
		for _, item in vent:GetDescendants() do
			if item:IsA("BasePart") then
				item.CanCollide = false
				item.CanQuery = false
				item.CanTouch = false
			end
		end
		game:GetService("CollectionService"):RemoveTag(vent, "CeilingVent")
		vent:PivotTo(VENT)
		vent.Parent = stage.Folder
		local door = vent:FindFirstChild("Door", true) :: BasePart
		local doorPivot = door:GetPivot()

		local rig = stage:Enemy("Ceiling Dweller", CFrame.new(0, -500, 0))
		rig:Preload({ WALK, ATTACK }, 6)
		for _, part in rig.Model:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			end
		end

		local facing = Vector3.new(CAMERA.X, 0, CAMERA.Z) - Vector3.new(FLOOR.X, 0, FLOOR.Z)
		local spawn = CFrame.lookAt(door.Position, door.Position + facing)
		local landed = CFrame.lookAt(FLOOR + Vector3.yAxis * STANDING, FLOOR + Vector3.yAxis * STANDING + facing)
		return { Vent = vent, Door = door, DoorPivot = doorPivot, Rig = rig, Spawn = spawn, Landed = landed, Facing = facing.Unit, Visible = false }
	end,

	Update = function(stage, ctx, time)
		local open = bounce((time - OPEN_AT) / OPEN_TIME)
		ctx.Door:PivotTo(ctx.DoorPivot * CFrame.Angles(OPEN_ANGLE * open, 0, 0))

		if time < DROP_AT then return end
		if not ctx.Visible then
			ctx.Visible = true
			for _, part in ctx.Rig.Model:GetDescendants() do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = 0
				end
			end
		end

		local dropTime = math.clamp((ctx.Spawn.Position - ctx.Landed.Position).Magnitude / 22, 0.2, 1.25)
		local fall = math.clamp((time - DROP_AT) / dropTime, 0, 1)
		local frame = ctx.Spawn:Lerp(ctx.Landed, fall * fall)
		if time >= LUNGE_AT then
			local run = (time - LUNGE_AT)
			local distance = RUN_SPEED * run * math.clamp(run / 0.15, 0, 1)
			frame = ctx.Landed + ctx.Facing * math.min(distance, LUNGE_DISTANCE)
		end
		ctx.Rig:SetCFrame(frame)
	end,

	Events = {
		{ Time = OPEN_AT, Run = function(stage, ctx)
			local position = ctx.DoorPivot.Position
			stage:Vfx("VentDust", CFrame.lookAt(position, position - Vector3.yAxis, Vector3.zAxis), {
				Size = Vector3.new(5, 5, 0.2),
				Duration = 0.9,
			})
		end },
		{ Time = DROP_AT + 0.34, Run = function(stage)
			stage:Vfx("DwellerLanding", CFrame.lookAt(FLOOR, FLOOR + Vector3.yAxis))
		end },
		{ Time = LUNGE_AT, Run = function(stage, ctx)
			ctx.Rig:Gait(WALK, RUN_SPEED, 1.5)
		end },
		{ Time = ATTACK_AT, Run = function(stage, ctx)
			ctx.Rig:Play(ATTACK, { Looped = false, Speed = 1.2, Fade = 0.05 })
		end },
	},
}
