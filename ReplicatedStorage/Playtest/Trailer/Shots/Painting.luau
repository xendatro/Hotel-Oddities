-- A winter landscape on the corridor wall. The camera leans in, and the
-- Painting Lurker tears out of the canvas with the game's burst, hole art and
-- animations, while the nearest lamps stutter. Staged locally from the same
-- numbers the PaintingDweller oddity uses.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lens = require(script.Parent.Parent.Lens)

local CANVAS = Vector3.new(13.7, -15.9, -90.1)
local OUTWARD = Vector3.new(0, 0, -1)
local ANCHOR = CANVAS - Vector3.new(0, 1.5, 0)
local HIDDEN = CFrame.lookAt(ANCHOR - OUTWARD * 8, ANCHOR + OUTWARD)
local POPPED = HIDDEN + OUTWARD * 7

local START_ANIMATION = 85430848422903
local THRASH_ANIMATION = 133679205168629
local HOLE_IMAGE = 110897645187028

local POP_AT = 1.45
local POP_TIME = 0.3

local EYE = -17.5
local START = Vector3.new(9.2, EYE, -101.2)
local LEAN = Vector3.new(10.3, EYE + 0.05, -99.2)
local FLINCH = Vector3.new(9.6, EYE - 0.15, -100.6)

return {
	Duration = 2.9,
	Warmup = 3,
	Park = CFrame.new(-6, -19.6, -96),
	Stream = { CANVAS },
	Handheld = Lens.Handheld(53, 1.1),
	Keys = Lens.Unwrap({
		Lens.Key(0, START, CANVAS + Vector3.new(-0.4, -0.3, 0), { Fov = 56, Roll = 0, Handheld = 0.8 }),
		Lens.Key(POP_AT, LEAN, CANVAS + Vector3.new(0, -0.2, 0), { Fov = 52, Handheld = 0.7 }),
		Lens.Key(POP_AT + 0.35, FLINCH, ANCHOR + Vector3.new(0, 0.6, -1.5), { Fov = 60, Roll = 2.2, Handheld = 1.6, Ease = "OutCubic" }),
		Lens.Key(2.9, FLINCH + Vector3.new(-0.3, 0, -0.3), ANCHOR + Vector3.new(0, 0.9, -2), { Fov = 58, Roll = 1.2, Handheld = 1.4 }),
	}),

	Setup = function(stage)
		local frame
		for _, model in game:GetService("CollectionService"):GetTagged("PictureFrame") do
			local canvas = model:FindFirstChild("Canvas")
			if canvas and canvas:IsA("BasePart") and (canvas.Position - CANVAS).Magnitude < 0.5 then
				frame = canvas
			end
		end
		assert(frame, "winter painting canvas not streamed in")

		local rig = stage:Enemy("Painting Dweller", HIDDEN)
		rig.Model:ScaleTo(1)
		rig:SetCFrame(HIDDEN)
		rig:Preload({ START_ANIMATION, THRASH_ANIMATION }, 6)

		local decals = {}
		for _, child in frame:GetChildren() do
			if child:IsA("Decal") and child.Face == Enum.NormalId.Front then
				table.insert(decals, child)
			end
		end

		local gui = Instance.new("SurfaceGui")
		gui.Name = "DwellerHole"
		gui.Enabled = false
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 1
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 128
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = `rbxassetid://{HOLE_IMAGE}`
		image.Parent = gui
		gui.Parent = frame
		stage:Add(gui)
		game:GetService("ContentProvider"):PreloadAsync({ image })

		local flicker = stage:Flicker(CANVAS - Vector3.new(14, 10, 10), CANVAS + Vector3.new(14, 10, 10), 3)
		return { Rig = rig, Canvas = frame, Decals = decals, Hole = gui, Flicker = flicker, Popped = false }
	end,

	Update = function(stage, ctx, time)
		if not ctx.Popped then return end
		local alpha = math.clamp((time - POP_AT) / POP_TIME, 0, 1)
		local eased = 1 - (1 - alpha) * (1 - alpha)
		ctx.Rig:SetCFrame(HIDDEN:Lerp(POPPED, eased))
		local stutter = math.clamp(1 - (time - POP_AT) / 1.2, 0, 1)
		ctx.Flicker(time, 0.95 * stutter)
	end,

	Events = {
		{ Time = POP_AT, Run = function(stage, ctx)
			ctx.Popped = true
			for _, decal in ctx.Decals do
				stage:Set(decal, "Transparency", 1)
			end
			ctx.Hole.Enabled = true

			local start = ctx.Rig:Play(START_ANIMATION, { Looped = false, Fade = 0.05 })
			local thrash = ctx.Rig:Load(THRASH_ANIMATION)
			if thrash then
				thrash.Looped = true
			end
			if start and thrash then
				start.Stopped:Once(function()
					thrash:Play(0.1)
				end)
			elseif thrash then
				thrash:Play(0.1)
			end

			stage:Vfx("PaintingBurst", ctx.Canvas.CFrame, { Size = Vector3.new(ctx.Canvas.Size.X, ctx.Canvas.Size.Y, 0.2) })
		end },
	},
}
