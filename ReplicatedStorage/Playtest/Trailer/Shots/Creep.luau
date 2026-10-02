-- Corridor B's lamps die far to near, the one overhead goes last, and a pair of
-- red eyes opens in the dark at the end of the hall. The Creep's distortion is
-- left out on purpose; the edit hard-cuts on the eyes instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StagedCreep = require(ReplicatedStorage.Classes.IntroCutscene.StagedCreep)
local Lens = require(script.Parent.Parent.Lens)

local CAMERA = Vector3.new(589.6, -18.05, -607.9)
local LOOK = Vector3.new(589.6, -17.3, -560)
local ROOT = Vector3.new(589.6, -17.2, -560)
local BACKDROP = Vector3.new(589.6, -17.04, -552)
local BACKDROP_SIZE = Vector3.new(12.6, 11.2, 1)
local JUNCTION = Vector3.new(589.5, -10.9, -609.4)

local STEPS = { 0.35, 0.8, 1.2, 1.55, 1.85, 2.1, 2.3 }
local GROUP_TOLERANCE = 3
local FLICKER = 0.32
local JUNCTION_AT = 2.55
local DARK_AT = 2.9
local OPEN_AT = 3.25
local BLINK_AT = 4.45
local RUSH_AT = 4.8

return {
	Duration = 5.7,
	Warmup = 3,
	Park = CFrame.new(589.6, -19.6, -585),
	Stream = { ROOT, Vector3.new(589.6, -19.6, -540) },
	Handheld = Lens.Handheld(29, 1.3),
	Keys = Lens.Unwrap({
		Lens.Key(0, CAMERA, LOOK, { Roll = 0, Handheld = 0.7, Fov = 54 }),
		Lens.Key(DARK_AT, CAMERA + Vector3.new(0, -0.04, 0.35), LOOK, { Handheld = 0.9, Fov = 51 }),
		Lens.Key(RUSH_AT, CAMERA + Vector3.new(0, -0.07, 1.3), ROOT, { Roll = -0.8, Handheld = 1.1, Fov = 41 }),
		Lens.Key(5.7, CAMERA + Vector3.new(0, -0.09, 1.75), ROOT, { Roll = -1.6, Handheld = 1.3, Fov = 33 }),
	}),

	Setup = function(stage)
		local effects = ReplicatedStorage:FindFirstChild("Effects")
		local creep = StagedCreep.new({
			Parent = stage.Folder,
			Template = ReplicatedStorage.Enemies.Creep,
			Effects = effects and effects:FindFirstChild("IntroCutscene"),
			RootCFrame = CFrame.lookAt(ROOT, Vector3.new(CAMERA.X, ROOT.Y, CAMERA.Z)),
			BackdropCFrame = CFrame.lookAt(BACKDROP, Vector3.new(BACKDROP.X, BACKDROP.Y, CAMERA.Z)),
			BackdropSize = BACKDROP_SIZE,
			EyeColor = Color3.fromRGB(190, 12, 12),
		})
		stage:Add(function()
			creep:Destroy()
		end)

		local sweep = stage:Sweep(Vector3.new(580, -26, -618), Vector3.new(606, -8, -524), { Color3.fromRGB(4, 4, 6), Color3.fromRGB(4, 4, 6) })
		local junction
		local others = {}
		for _, model in sweep:Ordered(CAMERA) do
			local offset = model:GetPivot().Position - JUNCTION
			if not junction and Vector2.new(offset.X, offset.Z).Magnitude <= 4 then
				junction = model
			else
				table.insert(others, model)
			end
		end

		local groups = {}
		local groupDistance = math.huge
		for _, model in others do
			local distance = (model:GetPivot().Position - CAMERA).Magnitude
			local group = groups[#groups]
			if not group or math.abs(distance - groupDistance) > GROUP_TOLERANCE then
				group = {}
				table.insert(groups, group)
				groupDistance = distance
			end
			table.insert(group, model)
		end

		local kills = {}
		for index, group in groups do
			local stepIndex = #STEPS - (#groups - index)
			local at = STEPS[math.max(stepIndex, 1)] - math.max(1 - stepIndex, 0) * 0.15
			for member, model in group do
				table.insert(kills, { Time = math.max(at + (member - 1) * 0.06, 0.05), Model = model })
			end
		end
		table.sort(kills, function(a, b)
			return a.Time < b.Time
		end)
		return { Creep = creep, Sweep = sweep, Junction = junction, Kills = kills, Darkness = 0 }
	end,

	Update = function(stage, ctx, time, dt)
		while ctx.Kills[1] and ctx.Kills[1].Time <= time do
			local kill = table.remove(ctx.Kills, 1)
			ctx.Sweep:Kill(kill.Model, FLICKER)
		end
		local darkness = math.clamp((time - 1.4) / (DARK_AT - 1.4), 0, 1)
		if darkness ~= ctx.Darkness then
			ctx.Darkness = darkness
			ctx.Sweep:SetAmbient(darkness * darkness)
		end
		ctx.Creep:Update(dt, workspace.CurrentCamera.CFrame.Position)
	end,

	Events = {
		{ Time = JUNCTION_AT, Run = function(stage, ctx)
			if ctx.Junction then
				ctx.Sweep:Kill(ctx.Junction, 0.4)
			end
		end },
		{ Time = OPEN_AT, Run = function(stage, ctx)
			ctx.Creep:Open(0.4)
		end },
		{ Time = BLINK_AT, Run = function(stage, ctx)
			ctx.Creep:Blink()
		end },
	},
}
