-- A backward tracking shot down a long corridor: the camera leads a friend who
-- sprints straight at the lens, glancing back once, while the Mad Guest runs
-- them down from a few strides behind, knife in hand. Nobody swings or catches
-- anyone; the threat is the gap closing. The lamps stutter as he passes.
local Lens = require(script.Parent.Parent.Lens)

local FRIEND = "xendatro"
local CORRIDOR = CFrame.lookAt(Vector3.new(-140, -22.547, -174), Vector3.new(-100, -22.547, -174))
local EYE = 4.4

local FRIEND_RUN = 2510198475
local GUEST_RUN = 130456583127042

local CAMERA_SPEED = 17.5
local FRIEND_START, FRIEND_SPEED, FRIEND_SIDE = 10, 18.6, -2.1
local GUEST_START, GUEST_SPEED, GUEST_SIDE = 26, 20.9, 2.7
local FRIEND_RATE = 1.15
local STEP_RATE = 2.7
local DURATION = 3.1

local function at(side: number, along: number, height: number?): Vector3
	return CORRIDOR:PointToWorldSpace(Vector3.new(side, height or 0, -along))
end

local function facing(position: Vector3): CFrame
	return CFrame.lookAt(position, position - CORRIDOR.LookVector)
end

local function bump(time: number, rise: number, peak: number, fall: number): number
	if time <= rise or time >= fall then return 0 end
	if time < peak then
		local alpha = (time - rise) / (peak - rise)
		return alpha * alpha * (3 - 2 * alpha)
	end
	local alpha = (time - peak) / (fall - peak)
	return 1 - alpha * alpha * (3 - 2 * alpha)
end

local function cameraKeys()
	local keys = {}
	local velocity = CORRIDOR:VectorToWorldSpace(Vector3.new(0, 0, CAMERA_SPEED))
	for index = 0, 6 do
		local time = (DURATION + 0.6) * index / 6
		local along = -CAMERA_SPEED * time
		local side = 0.15 * math.sin(time * 1.3)
		table.insert(keys, Lens.Key(time, at(side, along, EYE), at(side * 0.5 - 0.1, along + 30, EYE - 0.35), {
			Fov = 60 + 4 * (index / 6),
			Handheld = 1.0 + 0.3 * (index / 6),
			Tangents = { Position = velocity },
		}))
	end
	return Lens.Unwrap(keys)
end

return {
	Duration = DURATION,
	Warmup = 3,
	Park = CFrame.new(at(0, -20, 3)),
	Stream = { at(0, -40), at(0, 30) },
	Handheld = Lens.Handheld(71, 1.4),
	Keys = cameraKeys(),

	Camera = function(stage, ctx, time, frame, fov)
		local phase = time * STEP_RATE * math.pi * 2
		local bob = CFrame.new(0, 0.07 * math.abs(math.sin(phase / 2)) - 0.035, 0) * CFrame.Angles(0, 0, math.rad(0.5 * math.sin(phase / 2)))
		return frame * bob, fov
	end,

	Setup = function(stage)
		local friend = stage:Avatar(FRIEND, facing(at(FRIEND_SIDE, FRIEND_START, 3)))
		local guest = stage:Enemy("Chaser", facing(at(GUEST_SIDE, GUEST_START, 3)))
		local hairs = guest.Model:FindFirstChild("Hairs")
		if hairs then
			hairs:Destroy()
		end
		friend:Preload({ FRIEND_RUN }, 6)
		guest:Preload({ GUEST_RUN }, 6)

		local friendHeight = friend.Humanoid.HipHeight + friend.Root.Size.Y / 2
		local guestHeight = guest.Humanoid.HipHeight + guest.Root.Size.Y / 2
		local flicker = stage:Flicker(at(-12, -70, -4), at(12, 40, 14), 11)
		return { Friend = friend, Guest = guest, FriendHeight = friendHeight, GuestHeight = guestHeight, Flicker = flicker, Running = false }
	end,

	Warm = function(stage, ctx)
		ctx.Friend:SetCFrame(facing(at(FRIEND_SIDE, FRIEND_START, ctx.FriendHeight)))
		ctx.Guest:SetCFrame(facing(at(GUEST_SIDE, GUEST_START, ctx.GuestHeight)))
	end,

	Update = function(stage, ctx, time)
		if not ctx.Running then
			ctx.Running = true
			ctx.Friend:Play(FRIEND_RUN, { Looped = true, Speed = FRIEND_RATE, Fade = 0, Priority = Enum.AnimationPriority.Movement })
			ctx.Guest:Gait(GUEST_RUN, GUEST_SPEED)
		end

		local friendAlong = FRIEND_START - FRIEND_SPEED * time
		local weave = 0.35 * math.sin(time * 1.9 + 0.4)
		ctx.Friend:SetCFrame(facing(at(FRIEND_SIDE + weave, friendAlong, ctx.FriendHeight)) * CFrame.Angles(0, math.rad(4 * math.sin(time * 1.9)), 0))
		local glance = bump(time, 0.7, 1.0, 1.45)
		ctx.Friend:Bend("Neck", CFrame.Angles(math.rad(6 * glance), math.rad(48 * glance), 0))
		ctx.Friend:Bend("Waist", CFrame.Angles(0, math.rad(14 * glance), 0))

		local guestAlong = GUEST_START - GUEST_SPEED * time
		ctx.Guest:SetCFrame(facing(at(GUEST_SIDE + 0.2 * math.sin(time * 2.3), guestAlong, ctx.GuestHeight)))
		ctx.Flicker(time, 0.7)
	end,
}
