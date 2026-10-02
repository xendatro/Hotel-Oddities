-- The Stalker leans out of the far corner of corridor A. A slow push, then the
-- camera punches in as its eyes flare, and it dips back out of sight. Uses the
-- intro cutscene's staged rig and corner so the pose is already proven.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StagedStalker = require(ReplicatedStorage.Classes.IntroCutscene.StagedStalker)
local Lens = require(script.Parent.Parent.Lens)

local ROOT = Vector3.new(533.4, -19.18, -602.3)
local FACING = Vector3.new(1, 0, 0)
local MAX_YAW = math.rad(25)
local HIDDEN_SHIFT = 2.84
local HEAD_OFFSET = Vector3.new(-1.863, 0.299, -0.38)
local AIM_OFFSET = Vector3.new(0, -0.55, -1)

local LOOK = Vector3.new(589.45, -18, -610.75)
local PAN = Vector3.new(535.36, -17.9, -596.26)

local NOTICE = 1.7
local DIP = 3.25

local function frames(): (CFrame, CFrame, Vector3)
	local toShot = Vector3.new(LOOK.X - ROOT.X, 0, LOOK.Z - ROOT.Z)
	local yaw = math.clamp(math.atan2(FACING:Cross(toShot).Y, FACING:Dot(toShot)), -MAX_YAW, MAX_YAW)
	local direction = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(FACING)
	local peek = CFrame.lookAt(ROOT, ROOT + direction)
	return peek, peek * CFrame.new(HIDDEN_SHIFT, 0, 0), peek:PointToWorldSpace(HEAD_OFFSET)
end

local PEEK, HIDDEN, HEAD = frames()
local AIM = HEAD + AIM_OFFSET
local TOWARD = (HEAD - LOOK).Unit

return {
	Duration = 4.1,
	Warmup = 3,
	Park = CFrame.new(LOOK.X, -19.6, LOOK.Z + 6),
	Stream = { ROOT, Vector3.new(560, -19.6, -604) },
	Handheld = Lens.Handheld(13, 1.2),
	Keys = Lens.Unwrap({
		Lens.Key(0, LOOK - TOWARD * 0.6, PAN, { Roll = 0.3, Handheld = 0.9 }),
		Lens.Key(NOTICE, LOOK, PAN:Lerp(AIM, 0.5), { Roll = 0, Handheld = 0.8 }),
		Lens.Key(NOTICE + 0.55, LOOK + TOWARD * 1, AIM, { Handheld = 0.3 }),
		Lens.Key(DIP, LOOK + TOWARD * 1.2, AIM),
		Lens.Key(4.1, LOOK + TOWARD * 1.3, AIM + Vector3.new(0.25, 0.1, 0.7), { Roll = 0.4, Handheld = 0.45 }),
		{ Time = 0, Fov = 60 },
		{ Time = NOTICE, Fov = 55 },
		{ Time = NOTICE + 0.55, Fov = 15, Ease = "InOutQuad" },
		{ Time = DIP, Fov = 13.8 },
		{ Time = 4.1, Fov = 16.5 },
	}),

	Setup = function(stage)
		local effects = ReplicatedStorage:FindFirstChild("Effects")
		local stalker = StagedStalker.new({
			Parent = stage.Folder,
			Template = ReplicatedStorage.Enemies.Stalker,
			Effects = effects and effects:FindFirstChild("IntroCutscene"),
			AnimationId = 116106210940082,
			PeekCFrame = PEEK,
			HiddenCFrame = HIDDEN,
			BreathAmplitude = 0.035,
			EyeGlowColor = Color3.fromRGB(255, 40, 40),
		})
		stalker:WaitReady(6)
		stage:Add(function()
			stalker:Destroy()
		end)

		local depth = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if depth then
			stage:Set(depth, "Enabled", true)
			stage:Set(depth, "FocusDistance", (HEAD - LOOK).Magnitude)
			stage:Set(depth, "InFocusRadius", 10)
			stage:Set(depth, "NearIntensity", 0)
			stage:Set(depth, "FarIntensity", 0)
		end
		return { Stalker = stalker, Depth = depth }
	end,

	Update = function(stage, ctx, time, dt)
		ctx.Stalker:Update(dt)
		local depth = ctx.Depth
		if depth then
			local alpha = math.clamp((time - NOTICE) / 0.55, 0, 1)
			alpha = alpha * alpha * (3 - 2 * alpha)
			stage:Set(depth, "NearIntensity", 0.45 * alpha)
			stage:Set(depth, "FarIntensity", 0.25 * alpha)
		end
	end,

	Events = {
		{ Time = NOTICE + 0.05, Run = function(stage, ctx)
			ctx.Stalker:Notice()
		end },
		{ Time = DIP, Run = function(stage, ctx)
			task.spawn(function()
				ctx.Stalker:DipAsync(0.45)
			end)
		end },
	},
}
