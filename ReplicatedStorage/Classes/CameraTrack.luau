local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathService = require(ReplicatedStorage.Services.MathService)

local CameraTrack = {}
CameraTrack.__index = CameraTrack

export type Keyframe = { [string]: any }

export type HandheldOptions = {
	Yaw: number?,
	Pitch: number?,
	Roll: number?,
	Position: Vector3?,
	Frequencies: { number }?,
	Weights: { number }?,
	BreathPeriod: number?,
	BreathAmount: number?,
	Seed: number?,
}

export type Options = {
	Handheld: HandheldOptions?,
	FocusDistance: number?,
	Anchors: { [string]: any }?,
}

export type EntryState = {
	CFrame: CFrame,
	Fov: number?,
	Velocity: Vector3?,
	AngularVelocity: Vector3?,
}

export type EntryRates = {
	Position: number?,
	Rotation: number?,
	Fov: number?,
}

type Kind = "number" | "Vector3" | "Color3"

type Key = {
	Time: number,
	Value: any,
	Ease: string?,
	Tension: number,
	Velocity: any,
}

type Channel = {
	Kind: Kind,
	Keys: { Key },
	Cursor: number,
}

type Entry = {
	At: number,
	Position: Vector3,
	Velocity: Vector3,
	Rotation: Vector3,
	Spin: Vector3,
	Fov: number,
	PositionRate: number,
	RotationRate: number,
	FovRate: number,
}

type Handheld = {
	Yaw: number,
	Pitch: number,
	Roll: number,
	Position: Vector3,
	Frequencies: { number },
	Weights: { number },
	WeightTotal: number,
	BreathPeriod: number,
	BreathAmount: number,
	Seed: number,
}

export type CameraTrack = typeof(setmetatable({} :: {
	Channels: { [string]: Channel },
	FocusDistance: number,
	Handheld: Handheld,
	Entry: Entry?,
}, CameraTrack))

local RESERVED = { Time = true, Ease = true, Tension = true, Tangents = true }
local STEP = 1 / 240
local EPSILON = 1e-6
local TAU = MathService.TAU
local NOISE_GAIN = 2
local ENTRY_SETTLED = 9
local ENTRY_WINDOW_START = 6
local DEFAULT_FOV = 70
local DEFAULT_RATE = 5
local PUNCH_ATTACK = 0.035
local WHIP_SETTLE = 1.2

local function softStart(alpha: number, attack: number): number
	local total = 1 - attack * (1 - math.exp(-1 / attack))
	return (alpha - attack * (1 - math.exp(-alpha / attack))) / total
end

local Eases: { [string]: (number) -> number } = {
	Punch = function(alpha)
		return MathService.Eases.OutExpo(softStart(alpha, PUNCH_ATTACK))
	end,
	Whip = function(alpha)
		if alpha < 0.5 then
			return 16 * alpha ^ 5
		end
		local settle = 2 * alpha - 1
		local rest = 1 - settle
		return 0.5 + 0.5 * (1 - rest ^ 5 + WHIP_SETTLE * settle * settle * rest * rest)
	end,
}

local function kindOf(value: any): Kind?
	local valueType = typeof(value)
	if valueType == "number" or valueType == "Vector3" or valueType == "Color3" then
		return valueType :: Kind
	end
	return nil
end

local function toMath(value: any): any
	if typeof(value) == "Color3" then
		return Vector3.new(value.R, value.G, value.B)
	end
	return value
end

local function zeroOf(kind: Kind): any
	return if kind == "number" then 0 else Vector3.zero
end

local function isSpline(key: Key): boolean
	return key.Ease == nil
end

local function limitScalar(velocity: number, before: number, after: number): number
	if before * after <= 0 then return 0 end
	local bound = 3 * math.min(math.abs(before), math.abs(after))
	return math.clamp(velocity, -bound, bound)
end

local function computeVelocities(channel: Channel)
	local keys = channel.Keys
	local zero = zeroOf(channel.Kind)
	for index, key in keys do
		if key.Velocity ~= nil then continue end

		local previous, following = keys[index - 1], keys[index + 1]
		if not previous or not following or not isSpline(key) or not isSpline(following) then
			key.Velocity = zero
			continue
		end

		local spanBefore = key.Time - previous.Time
		local spanAfter = following.Time - key.Time
		if spanBefore <= EPSILON or spanAfter <= EPSILON then
			key.Velocity = zero
			continue
		end

		local slopeBefore = (key.Value - previous.Value) / spanBefore
		local slopeAfter = (following.Value - key.Value) / spanAfter
		local velocity = (slopeBefore * spanAfter + slopeAfter * spanBefore) / (spanBefore + spanAfter)
		if channel.Kind == "number" then
			velocity = limitScalar(velocity, slopeBefore, slopeAfter)
		end
		key.Velocity = velocity * (1 - key.Tension)
	end
end

local function hermite(from: Key, to: Key, alpha: number): any
	local span = to.Time - from.Time
	local squared = alpha * alpha
	local cubed = squared * alpha
	local h00 = 2 * cubed - 3 * squared + 1
	local h10 = cubed - 2 * squared + alpha
	local h01 = -2 * cubed + 3 * squared
	local h11 = cubed - squared
	return from.Value * h00 + from.Velocity * (h10 * span) + to.Value * h01 + to.Velocity * (h11 * span)
end

local function evaluateChannel(channel: Channel, time: number): any
	local keys = channel.Keys
	local count = #keys
	if count == 1 or time <= keys[1].Time then
		return keys[1].Value
	end
	if time >= keys[count].Time then
		return keys[count].Value
	end

	local cursor = math.clamp(channel.Cursor, 1, count - 1)
	while cursor > 1 and time < keys[cursor].Time do
		cursor -= 1
	end
	while cursor < count - 1 and time >= keys[cursor + 1].Time do
		cursor += 1
	end
	channel.Cursor = cursor

	local from, to = keys[cursor], keys[cursor + 1]
	local span = to.Time - from.Time
	if span <= EPSILON then
		return to.Value
	end

	local ease = to.Ease
	if ease == "Step" then
		return from.Value
	end

	local alpha = math.clamp((time - from.Time) / span, 0, 1)
	if ease == nil then
		return hermite(from, to, alpha)
	end

	local easing = Eases[ease] or MathService.Eases[ease] or MathService.Eases.InOutSine
	return from.Value + (to.Value - from.Value) * easing(alpha)
end

local function resolve(value: any, anchors: { [string]: any }?): any
	if type(value) ~= "string" then return value end
	local resolved = anchors and anchors[value]
	if resolved == nil then
		warn(`CameraTrack: no anchor named "{value}"; the keyframe value is ignored`)
	end
	return resolved
end

local function buildChannels(keyframes: { Keyframe }, anchors: { [string]: any }?): { [string]: Channel }
	local channels: { [string]: Channel } = {}

	for _, keyframe in keyframes do
		local time = keyframe.Time
		if type(time) ~= "number" then continue end

		local tangents = keyframe.Tangents
		for name, raw in keyframe do
			if RESERVED[name] or type(name) ~= "string" then continue end

			local value = resolve(raw, anchors)
			local kind = kindOf(value)
			if not kind then continue end

			local channel = channels[name]
			if not channel then
				channel = { Kind = kind, Keys = {}, Cursor = 1 }
				channels[name] = channel
			elseif channel.Kind ~= kind then
				warn(`CameraTrack: channel "{name}" mixes {channel.Kind} and {kind}; the key at {time} is ignored`)
				continue
			end

			local tangent = if type(tangents) == "table" then resolve(tangents[name], anchors) else nil
			table.insert(channel.Keys, {
				Time = time,
				Value = toMath(value),
				Ease = keyframe.Ease,
				Tension = if type(keyframe.Tension) == "number" then keyframe.Tension else 0,
				Velocity = if tangent ~= nil and kindOf(tangent) == kind then toMath(tangent) else nil,
			})
		end
	end

	for _, channel in channels do
		table.sort(channel.Keys, function(a: Key, b: Key)
			return a.Time < b.Time
		end)
		computeVelocities(channel)
	end

	return channels
end

local function buildHandheld(options: HandheldOptions?): Handheld
	local source = options or {}
	local frequencies = source.Frequencies or { 0.2, 0.55, 1.5 }
	local weights = source.Weights or { 1, 0.4, 0.15 }
	local total = 0
	for index in frequencies do
		total += weights[index] or 0
	end

	return {
		Yaw = source.Yaw or 0.5,
		Pitch = source.Pitch or 0.35,
		Roll = source.Roll or 0.3,
		Position = source.Position or Vector3.new(0.03, 0.02, 0.02),
		Frequencies = frequencies,
		Weights = weights,
		WeightTotal = math.max(total, EPSILON),
		BreathPeriod = math.max(source.BreathPeriod or 4, EPSILON),
		BreathAmount = source.BreathAmount or 0,
		Seed = source.Seed or Random.new():NextNumber(0, 500),
	}
end

local function layeredNoise(handheld: Handheld, time: number, lane: number): number
	local sum = 0
	for index, frequency in handheld.Frequencies do
		local weight = handheld.Weights[index] or 0
		if weight == 0 then continue end
		sum += math.noise(time * frequency + lane * 3.71, handheld.Seed + lane * 11.3 + index * 5.17, 0.5) * weight
	end
	return math.clamp(sum / handheld.WeightTotal * NOISE_GAIN, -1, 1)
end

local function spring(offset: any, velocity: any, rate: number, elapsed: number): (any, boolean)
	local phase = rate * elapsed
	if phase >= ENTRY_SETTLED then
		return offset * 0, false
	end
	local window = 1
	if phase > ENTRY_WINDOW_START then
		window = 1 - MathService.Smoothstep((phase - ENTRY_WINDOW_START) / (ENTRY_SETTLED - ENTRY_WINDOW_START))
	end
	return (offset + (velocity + offset * rate) * elapsed) * (math.exp(-phase) * window), true
end

function CameraTrack.new(keyframes: { Keyframe }, options: Options?): CameraTrack
	return setmetatable({
		Channels = buildChannels(keyframes, options and options.Anchors),
		FocusDistance = (options and options.FocusDistance) or 8,
		Handheld = buildHandheld(options and options.Handheld),
		Entry = nil :: Entry?,
	}, CameraTrack)
end

function CameraTrack:Sample(name: string, time: number): any
	local channel = self.Channels[name]
	if not channel then return nil end

	local value = evaluateChannel(channel, time)
	if channel.Kind == "Color3" then
		return Color3.new(math.clamp(value.X, 0, 1), math.clamp(value.Y, 0, 1), math.clamp(value.Z, 0, 1))
	end
	return value
end

function CameraTrack:EvaluateBase(time: number): (CFrame, number)
	local position = self:Sample("Position", time) or Vector3.zero
	local focus = self:Sample("Focus", time)
	local roll = self:Sample("Roll", time) or 0
	local fov = self:Sample("Fov", time) or DEFAULT_FOV

	local frame = CFrame.new(position)
	if focus and (focus - position).Magnitude > EPSILON then
		frame = CFrame.lookAt(position, focus)
	end
	if roll ~= 0 then
		frame *= CFrame.Angles(0, 0, math.rad(roll))
	end
	return frame, fov
end

function CameraTrack:_handheld(time: number, noiseTime: number): CFrame
	local amount = self:Sample("Handheld", time) or 0
	if amount <= EPSILON then return CFrame.identity end

	local handheld = self.Handheld
	local drift = handheld.Position
	local breath = math.sin(noiseTime * TAU / handheld.BreathPeriod) * handheld.BreathAmount
	local offset = Vector3.new(
		layeredNoise(handheld, noiseTime, 1) * drift.X,
		layeredNoise(handheld, noiseTime, 2) * drift.Y + breath,
		layeredNoise(handheld, noiseTime, 3) * drift.Z
	) * amount

	local pitch = math.rad(layeredNoise(handheld, noiseTime, 4) * handheld.Pitch * amount)
	local yaw = math.rad(layeredNoise(handheld, noiseTime, 5) * handheld.Yaw * amount)
	local roll = math.rad(layeredNoise(handheld, noiseTime, 6) * handheld.Roll * amount)
	return CFrame.new(offset) * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)
end

function CameraTrack:_compose(time: number, noiseTime: number): (CFrame, number)
	local frame, fov = self:EvaluateBase(time)
	return frame * self:_handheld(time, noiseTime), fov
end

function CameraTrack:SetEntry(state: EntryState, at: number, rates: EntryRates?, noiseTime: number?)
	local noise = noiseTime or at
	local frame, fov = self:_compose(at, noise)
	local ahead = self:_compose(at + STEP, noise + STEP)

	local baseVelocity = (ahead.Position - frame.Position) / STEP
	local baseSpin = frame.Rotation:VectorToWorldSpace(MathService.RotationVector(frame.Rotation:ToObjectSpace(ahead.Rotation))) / STEP
	local spin = (state.AngularVelocity or baseSpin) - baseSpin

	self.Entry = {
		At = at,
		Position = state.CFrame.Position - frame.Position,
		Velocity = (state.Velocity or baseVelocity) - baseVelocity,
		Rotation = MathService.RotationVector(frame.Rotation:ToObjectSpace(state.CFrame.Rotation)),
		Spin = frame.Rotation:VectorToObjectSpace(spin),
		Fov = (state.Fov or fov) - fov,
		PositionRate = math.max((rates and rates.Position) or DEFAULT_RATE, EPSILON),
		RotationRate = math.max((rates and rates.Rotation) or DEFAULT_RATE, EPSILON),
		FovRate = math.max((rates and rates.Fov) or DEFAULT_RATE, EPSILON),
	}
end

function CameraTrack:ClearEntry()
	self.Entry = nil
end

function CameraTrack:Evaluate(time: number, noiseTime: number?): (CFrame, number)
	local frame, fov = self:_compose(time, noiseTime or time)
	local entry = self.Entry
	if not entry then return frame, fov end

	local elapsed = time - entry.At
	if elapsed < 0 then return frame, fov end

	local position, movingPosition = spring(entry.Position, entry.Velocity, entry.PositionRate, elapsed)
	local rotation, movingRotation = spring(entry.Rotation, entry.Spin, entry.RotationRate, elapsed)
	local fovOffset, movingFov = spring(entry.Fov, 0, entry.FovRate, elapsed)
	if not (movingPosition or movingRotation or movingFov) then
		self.Entry = nil
		return frame, fov
	end

	return CFrame.new(frame.Position + position) * frame.Rotation * MathService.FromRotationVector(rotation), fov + fovOffset
end

function CameraTrack:GetAngularSpeed(time: number): number
	local from = self:EvaluateBase(time)
	local to = self:EvaluateBase(time + STEP)
	local _, angle = from.Rotation:ToObjectSpace(to.Rotation):ToAxisAngle()
	return math.deg(angle) / STEP
end

function CameraTrack:GetFocus(frame: CFrame): CFrame
	return CFrame.new(frame.Position + frame.LookVector * self.FocusDistance)
end

function CameraTrack:Destroy()
	table.clear(self.Channels)
	self.Entry = nil
end

return CameraTrack
