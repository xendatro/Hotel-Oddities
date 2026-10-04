-- A Mimic wearing hythe55 stands in the hallway with its back turned.
-- HustleOnPoint walks up behind it and stops; the head wrenches all the way
-- round, the borrowed face gives way to the black eyes and teeth the game puts
-- on a revealed Mimic, and it rises into its hover with the head still
-- twitching, the same reveal MimicService and the Mimic class play in game.
-- The camera follows behind HustleOnPoint's right shoulder, jolts on the
-- crack, punches in on the face, then dolly-zooms toward it so the face holds
-- its size while the hallway stretches away behind it. The lamps around it
-- die outward from the Mimic on the crack and its eyes light the face red.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EyeGlow = require(ReplicatedStorage.Classes.EyeGlow)
local Lens = require(script.Parent.Parent.Lens)

local CORRIDOR = CFrame.lookAt(Vector3.new(-60, -22.547, 201), Vector3.new(-20, -22.547, 201))
local EYE = 4.85

local MIMIC = "hythe55"
local VICTIM = "HustleOnPoint"
local MIMIC_REMOVE = { 5731050224, 5731051458, 5731052645, 5731053584, 5731054790, 103504913551483 }
local TOP_HAT = 4882472012
local VICTIM_REMOVE = { 5731053584 }

local IDLE = 507766388
local FLY = 124677133774216
local WALK = 2510202577
local VICTIM_IDLE = 2510196951

local MIMIC_ALONG, MIMIC_SIDE = 15, 0.8
local WALK_FROM, WALK_TO = Vector2.new(-1.5, 3.2), Vector2.new(-1.0, 10.6)
local CRUISE_UNTIL = 1.15
local WALK_END = 1.55
local WALK_RATE = 0.156
local SNAP_AT = 1.55
local SNAP_TIME = 0.12
local FACE_AT = 1.62
local RISE_AT = 1.7
local RISE_TIME = 0.35
local RISE = 3
local BOB = 0.5
local BOB_PERIOD = 1.6
local TURN_AT, TURN_TIME = 1.78, 0.42
local FLINCH_AT = 1.75
local DOLLY_AT = FACE_AT + 0.32
local GLOOM = 0.55
local FIRST_LAMP_AT = 1.4
local LAMPS_AT = SNAP_AT - 0.04
local LAMP_SPACING = 0.035
local DARK_TIME = 0.22
local RED = Color3.fromRGB(255, 36, 28)
local RED_BRIGHTNESS = 1.6
local END = 3.4

local IMPULSES = Lens.Impulses({
	{ At = SNAP_AT, Shake = 0.5, Decay = 0.22, Fov = 4, Push = -0.3, Attack = 0.02 },
	{ At = FACE_AT, Shake = 0.75, Decay = 0.45 },
	{ At = RISE_AT, Shake = 0.3, Decay = 0.4, Push = 0.15 },
	{ At = DOLLY_AT, Shake = 0.3, Decay = 60, Attack = 0.5 },
}, 41)

local function at(side: number, along: number, height: number?): Vector3
	return CORRIDOR:PointToWorldSpace(Vector3.new(side, height or 0, -along))
end

local function smooth(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function easeOut(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return 1 - (1 - alpha) * (1 - alpha)
end

local MIMIC_HEAD = at(MIMIC_SIDE, MIMIC_ALONG, 5.3)
local MIMIC_HEAD_RISEN = at(MIMIC_SIDE, MIMIC_ALONG, 5.3 + RISE - BOB)

local function buildFace(head: BasePart): (Model, { BasePart })
	local scale = head.Size.Y / 1.2
	local front = -head.Size.Z / 2
	local face = Instance.new("Model")
	face.Name = "MimicFace"

	local function addPart(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, className: string?)
		local part = Instance.new(className or "Part") :: Part
		part.Name = name
		part.Size = size * scale
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.CFrame = head.CFrame * offset
		part.Parent = face
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = part
		weld.Parent = part
		return part
	end

	local eyes = {}
	for _, side in { -1, 1 } do
		addPart("EyeLining", Vector3.new(0.34, 0.4, 0.06), CFrame.new(side * 0.22 * scale, 0.14 * scale, front - 0.015 * scale), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
		table.insert(eyes, addPart("Eye", Vector3.new(0.2, 0.26, 0.08), CFrame.new(side * 0.22 * scale, 0.14 * scale, front - 0.045 * scale), Color3.fromRGB(255, 20, 20), Enum.Material.Neon))
	end
	local mouthY = -0.3 * scale
	addPart("Mouth", Vector3.new(0.7, 0.32, 0.06), CFrame.new(0, mouthY, front - 0.015 * scale), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	local toothColor = Color3.fromRGB(235, 235, 220)
	for index = 0, 3 do
		local x = (-0.24 + index * 0.16) * scale
		for _, pointDown in { true, false } do
			local y = mouthY + (if pointDown then 0.085 else -0.085) * scale
			for _, side in { -1, 1 } do
				local yaw = side * math.pi / 2 * (if pointDown then 1 else -1)
				local roll = if pointDown then math.pi else 0
				addPart("Tooth", Vector3.new(0.05, 0.15, 0.045), CFrame.new(x + side * 0.0225 * scale, y, front - 0.04 * scale) * CFrame.Angles(0, 0, roll) * CFrame.Angles(0, yaw, 0), toothColor, Enum.Material.SmoothPlastic, "WedgePart")
			end
		end
	end
	return face, eyes
end

local function twitchSchedule(seed: number): { { At: number, Until: number, Offset: CFrame } }
	local random = Random.new(seed)
	local schedule = {}
	local time = SNAP_AT + SNAP_TIME + 0.05
	while time < 3.6 do
		local snaps = random:NextInteger(2, 4)
		for _ = 1, snaps do
			local length = random:NextNumber(0.025, 0.055)
			table.insert(schedule, {
				At = time,
				Until = time + length,
				Offset = CFrame.Angles(random:NextNumber(-0.26, 0.26), random:NextNumber(-0.5, 0.5), random:NextNumber(-0.26, 0.26)),
			})
			time += length
		end
		schedule[#schedule].Until += random:NextNumber(0.08, 0.16)
		time = schedule[#schedule].Until + random:NextNumber(0.25, 0.6)
	end
	return schedule
end

local function lookYaw(torso: CFrame, target: Vector3): (number, number)
	local direction = torso:VectorToObjectSpace((target - torso.Position).Unit)
	local yaw = math.atan2(-direction.X, -direction.Z)
	local pitch = math.asin(math.clamp(direction.Y, -1, 1))
	return yaw, pitch
end

return {
	Duration = 3.0,
	Warmup = 3,
	Park = CFrame.new(at(0, -18, 3)),
	Stream = { at(0, 15), at(0, 40) },
	Handheld = Lens.Handheld(97, 1.2),
	Keys = Lens.Unwrap({
		Lens.Key(0, at(0.9, -0.6, EYE), at(0, 15, 4.4), { Fov = 58, Roll = -0.6, Handheld = 0.8 }),
		Lens.Key(WALK_END, at(1.0, 6.4, EYE - 0.05), at(0.7, 15, 4.8), { Fov = 55, Roll = 0, Handheld = 0.8 }),
		Lens.Key(DOLLY_AT, at(1.05, 6.8, EYE - 0.1), MIMIC_HEAD:Lerp(MIMIC_HEAD_RISEN, 0.8), { Roll = 1.2, Handheld = 1.2 }),
		Lens.Key(END, at(1.0, 11.4, EYE + 0.6), MIMIC_HEAD_RISEN + Vector3.new(0, 0.1, 0), { Roll = 2.8, Handheld = 1.5 }),
		{ Time = FACE_AT, Fov = 54 },
		{ Time = DOLLY_AT, Fov = 33, Ease = "InOutQuad" },
		{ Time = END, Fov = 33 },
	}),

	Camera = function(stage, ctx, time, frame, fov)
		if time >= DOLLY_AT then
			local distance = (frame.Position - ctx.Head.Position).Magnitude
			ctx.Vertigo = ctx.Vertigo or distance * math.tan(math.rad(fov) / 2)
			fov = math.deg(2 * math.atan(ctx.Vertigo / distance))
		end
		local offset, kick = IMPULSES(time)
		return frame * offset, fov + kick
	end,

	Setup = function(stage)
		local awayFacing = CFrame.lookAt(at(MIMIC_SIDE, MIMIC_ALONG, 3), at(MIMIC_SIDE, MIMIC_ALONG + 5, 3))
		local mimic = stage:Avatar(MIMIC, awayFacing, {
			Remove = MIMIC_REMOVE,
			Adjust = { [TOP_HAT] = { Position = Vector3.zero, Rotation = Vector3.zero, Scale = Vector3.one } },
		})
		local victim = stage:Avatar(VICTIM, CFrame.lookAt(at(WALK_FROM.X, WALK_FROM.Y, 3), at(WALK_TO.X, WALK_TO.Y, 3)), { Remove = VICTIM_REMOVE })
		mimic:Preload({ IDLE, FLY }, 6)
		victim:Preload({ WALK, VICTIM_IDLE }, 6)

		local mimicHeight = mimic.Humanoid.HipHeight + mimic.Root.Size.Y / 2
		local victimHeight = victim.Humanoid.HipHeight + victim.Root.Size.Y / 2
		local head = mimic.Model:FindFirstChild("Head") :: BasePart
		local faceItems = {}
		for _, item in mimic.Model:GetDescendants() do
			if item:IsA("Decal") and item.Parent == head then
				table.insert(faceItems, item)
			elseif item:IsA("Attachment") and (item.Name == "FaceFrontAttachment" or item.Name == "FaceCenterAttachment") and item.Parent and item.Parent.Name == "Handle" then
				table.insert(faceItems, item.Parent)
			end
		end

		local effects = ReplicatedStorage:FindFirstChild("Effects")
		local folder = effects and effects:FindFirstChild("IntroCutscene")
		local sweep = stage:Sweep(at(-8, -12, -6), at(8, 30, 16), { Color3.fromRGB(7, 5, 5), Color3.fromRGB(7, 5, 5) })
		local kills = {}
		for index, model in sweep:Ordered(at(MIMIC_SIDE, MIMIC_ALONG, 4)) do
			table.insert(kills, {
				Model = model,
				Time = if index == 1 then FIRST_LAMP_AT else LAMPS_AT + (index - 2) * LAMP_SPACING,
				Flicker = if index == 1 then 0.2 else 0.08,
			})
		end
		return {
			Mimic = mimic,
			Victim = victim,
			MimicHeight = mimicHeight,
			VictimHeight = victimHeight,
			Head = head,
			FaceItems = faceItems,
			GlowTemplate = folder and folder:FindFirstChild("EyeGlow"),
			Glows = {},
			Twitches = twitchSchedule(7),
			Sweep = sweep,
			Kills = kills,
		}
	end,

	Warm = function(stage, ctx)
		ctx.Sweep:SetAmbient(GLOOM)
		ctx.Mimic:SetCFrame(CFrame.lookAt(at(MIMIC_SIDE, MIMIC_ALONG, ctx.MimicHeight), at(MIMIC_SIDE, MIMIC_ALONG + 5, ctx.MimicHeight)))
		ctx.Victim:SetCFrame(CFrame.lookAt(at(WALK_FROM.X, WALK_FROM.Y, ctx.VictimHeight), at(WALK_TO.X, WALK_TO.Y, ctx.VictimHeight)))
		if not ctx.Idling then
			ctx.Idling = true
			ctx.Mimic:Play(IDLE, { Looped = true, Speed = 0.45, Fade = 0, Priority = Enum.AnimationPriority.Idle })
			ctx.Walk = ctx.Victim:Play(WALK, { Looped = true, Speed = 0.9, Fade = 0, Priority = Enum.AnimationPriority.Movement })
			ctx.Idle = ctx.Victim:Play(VICTIM_IDLE, { Looped = true, Speed = 1, Fade = 0, Weight = 0.01, Priority = Enum.AnimationPriority.Idle })
		end
	end,

	Update = function(stage, ctx, time)
		local distance = (WALK_TO - WALK_FROM).Magnitude
		local cruise = distance / (CRUISE_UNTIL + (WALK_END - CRUISE_UNTIL) / 2)
		local travelled, speed
		if time <= CRUISE_UNTIL then
			travelled, speed = cruise * time, cruise
		else
			local braking = math.min(time - CRUISE_UNTIL, WALK_END - CRUISE_UNTIL)
			local span = WALK_END - CRUISE_UNTIL
			speed = cruise * (1 - braking / span)
			travelled = cruise * CRUISE_UNTIL + cruise * (braking - braking * braking / (2 * span))
		end
		local back = math.clamp((time - FLINCH_AT) / 0.45, 0, 1)
		local retreat = smooth(back) * 1.1
		if back > 0 and back < 1 then
			speed = -1.1 / 0.45 * 6 * back * (1 - back)
		end

		local moving = math.clamp(math.abs(speed) / 2.5, 0, 1)
		if ctx.Walk then
			ctx.Walk:AdjustWeight(math.max(moving, 0.001), 0.1)
			ctx.Walk:AdjustSpeed(if math.abs(speed) > 0.05 then speed * WALK_RATE else 0)
		end
		if ctx.Idle then
			ctx.Idle:AdjustWeight(math.max(1 - moving, 0.001), 0.1)
		end

		local direction = (WALK_TO - WALK_FROM).Unit
		local spot = WALK_FROM + direction * (travelled - retreat)
		local victimPosition = at(spot.X, spot.Y, ctx.VictimHeight)
		local walkingHeading = CFrame.lookAt(victimPosition, victimPosition + (at(direction.X, direction.Y) - at(0, 0)))
		local facingMimic = CFrame.lookAt(victimPosition, Vector3.new(MIMIC_HEAD.X, victimPosition.Y, MIMIC_HEAD.Z))
		local settle = smooth((time - (WALK_END - 0.35)) / 0.55)
		ctx.Victim:SetCFrame(walkingHeading:Lerp(facingMimic, settle))
		local flinch = smooth((time - FLINCH_AT) / 0.25)
		ctx.Victim:Bend("Waist", CFrame.Angles(math.rad(-12 * flinch), math.rad(-6 * flinch), 0))
		ctx.Victim:Bend("Neck", CFrame.Angles(math.rad(22 * smooth((time - RISE_AT) / 0.5)), 0, 0))

		local rise = easeOut((time - RISE_AT) / RISE_TIME)
		local bobTime = time - RISE_AT - RISE_TIME
		local height = ctx.MimicHeight + (RISE - BOB) * rise + (if bobTime > 0 then BOB * math.sin(bobTime * math.pi * 2 / BOB_PERIOD) else 0)
		local base = at(MIMIC_SIDE, MIMIC_ALONG, 0)
		local awayYaw = CFrame.lookAt(base, at(MIMIC_SIDE, MIMIC_ALONG + 5, 0)).Rotation
		local toVictim = CFrame.lookAt(base, Vector3.new(victimPosition.X, base.Y, victimPosition.Z)).Rotation
		local turn = smooth((time - TURN_AT) / TURN_TIME)
		local body = CFrame.new(at(MIMIC_SIDE, MIMIC_ALONG, height)) * awayYaw:Lerp(toVictim, turn)
		ctx.Mimic:SetCFrame(body)

		local camera = workspace.CurrentCamera.CFrame.Position
		local torso = body * CFrame.new(0, 1.2, 0)
		local yaw, pitch = lookYaw(torso, camera)
		local snap = smooth((time - SNAP_AT) / SNAP_TIME)
		local offset = CFrame.identity
		for _, twitch in ctx.Twitches do
			if time >= twitch.At and time < twitch.Until then
				offset = twitch.Offset
				break
			end
		end
		ctx.Mimic:Bend("Neck", CFrame.Angles(math.clamp(pitch, -0.6, 0.6) * snap, yaw * snap, 0) * (if time > SNAP_AT + SNAP_TIME then offset else CFrame.identity))

		if time >= FACE_AT then
			local flare = EyeGlow.Flare(time - FACE_AT, 0.06, 0.5, 0.8)
			for _, glow in ctx.Glows do
				glow:Render(math.clamp(0.55 + 0.45 * flare, 0, 1), 1 + 0.7 * flare, 1 + 0.5 * flare)
			end
			if ctx.Red then
				ctx.Red.Brightness = RED_BRIGHTNESS * math.clamp((time - FACE_AT) / 0.06, 0, 1) * (0.75 + 0.25 * flare)
			end
		end

		while ctx.Kills[1] and ctx.Kills[1].Time <= time do
			local kill = table.remove(ctx.Kills, 1)
			ctx.Sweep:Kill(kill.Model, kill.Flicker)
		end
		ctx.Sweep:SetAmbient(GLOOM + (1 - GLOOM) * smooth((time - FACE_AT + 0.04) / DARK_TIME))
	end,

	Events = {
		{ Time = FACE_AT, Run = function(stage, ctx)
			for _, item in ctx.FaceItems do
				if item:IsA("Decal") then
					item.Transparency = 1
				elseif item:IsA("BasePart") then
					item.LocalTransparencyModifier = 1
				end
			end
			local face, eyes = buildFace(ctx.Head)
			face.Parent = ctx.Mimic.Model
			local glow = Instance.new("Attachment")
			glow.Position = Vector3.new(0, -0.9, -ctx.Head.Size.Z / 2 - 0.9)
			glow.Parent = ctx.Head
			local red = Instance.new("PointLight")
			red.Color = RED
			red.Range = 9
			red.Brightness = 0
			red.Shadows = true
			red.Parent = glow
			ctx.Red = red
			stage:Add(glow)
			for _, eye in eyes do
				local glow = EyeGlow.new(ctx.GlowTemplate, eye, { Scale = 0.6, TowardCamera = 0.4, Tint = Color3.fromRGB(255, 30, 30) })
				if glow then
					table.insert(ctx.Glows, glow)
					stage:Add(function()
						glow:Destroy()
					end)
				end
			end
		end },
		{ Time = RISE_AT, Run = function(stage, ctx)
			ctx.Mimic:Stop(IDLE, 0.15)
			ctx.Mimic:Play(FLY, { Looped = true, Fade = 0.2, Priority = Enum.AnimationPriority.Action })
		end },
	},
}
