-- The closing sting. Corridor A is empty where the Stalker peeked earlier. The
-- camera turns around, slowly, and it is standing right there with its head
-- cocked, eyes flaring as they catch the lens.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EyeGlow = require(ReplicatedStorage.Classes.EyeGlow)
local Lens = require(script.Parent.Parent.Lens)

local FLOOR = -22.632
local CAMERA = Vector3.new(566, FLOOR + 4.95, -610.75)
local STALKER = Vector3.new(569.3, FLOOR, -610.95)

local IDLE = 507766388
local TURN_END = 2.5
local FLARE_AT = 2.2

return {
	Duration = 3.5,
	Warmup = 3,
	Park = CFrame.new(578, -19.6, -610.75),
	Stream = { Vector3.new(540, -19.6, -606), Vector3.new(589, -19.6, -610) },
	Handheld = Lens.Handheld(83, 1),
	Keys = Lens.Unwrap({
		{ Time = 0, Position = CAMERA, Yaw = 90, Pitch = -1.5, Roll = 0, Fov = 62, Handheld = 0.9 },
		{ Time = 0.5, Position = CAMERA, Yaw = 98, Pitch = -1.2 },
		{ Time = TURN_END, Position = CAMERA + Vector3.new(-0.35, -0.05, 0), Yaw = 268, Pitch = 3.5, Roll = -2, Fov = 60, Handheld = 0.8 },
		{ Time = 3.5, Position = CAMERA + Vector3.new(-0.15, -0.05, 0), Yaw = 270, Pitch = 4.5, Roll = -1.2, Fov = 50, Handheld = 0.6 },
	}),

	Setup = function(stage)
		local root = Vector3.new(STALKER.X, STALKER.Y + 3.45, STALKER.Z)
		local rig = stage:Enemy("Stalker", CFrame.lookAt(root, Vector3.new(CAMERA.X, root.Y, CAMERA.Z)))
		rig:Preload({ IDLE }, 6)
		rig:Play(IDLE, { Looped = true, Speed = 0.6, Fade = 0, Priority = Enum.AnimationPriority.Idle })
		rig:Bend("Neck", CFrame.Angles(math.rad(-12), math.rad(4), math.rad(16)))
		rig:Bend("Waist", CFrame.Angles(math.rad(10), 0, 0))

		local effects = ReplicatedStorage:FindFirstChild("Effects")
		local folder = effects and effects:FindFirstChild("IntroCutscene")
		local template = folder and folder:FindFirstChild("EyeGlow")
		local glows = {}
		local head = rig.Model:FindFirstChild("Head")
		for _, name in { "LeftEye", "RightEye" } do
			local eye = head and head:FindFirstChild(name)
			if eye and eye:IsA("BasePart") then
				local glow = EyeGlow.new(template, eye, { Scale = 0.55, TowardCamera = 0.4, Tint = Color3.fromRGB(255, 40, 40) })
				if glow then
					table.insert(glows, glow)
					stage:Add(function()
						glow:Destroy()
					end)
				end
			end
		end
		return { Rig = rig, Glows = glows }
	end,

	Update = function(stage, ctx, time)
		local flare = if time >= FLARE_AT then EyeGlow.Flare(time - FLARE_AT, 0.07, 0.45, 0.6) else 0
		local strength = math.clamp(0.45 + 0.55 * flare, 0, 1)
		for _, glow in ctx.Glows do
			glow:Render(strength, 1 + 0.8 * flare, 1 + 0.6 * flare)
		end
	end,
}
