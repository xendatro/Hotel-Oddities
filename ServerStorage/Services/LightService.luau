--- Turning the hotel's lights off and on again, for anything that wants a stretch of it dark.
---
--- A light model is a lamp: a `Light`, some particles, and the bright part you actually see from down
--- the corridor. That last one is found by material rather than by name or tag -- anything Neon inside
--- a tagged model is the glowing bit of it, and goes to SmoothPlastic while the lamp is out. Nothing
--- in the map has to be prepared for this, so a lantern built next week goes dark like the rest.
---
--- Which parts were Neon is remembered on the parts themselves, as a tag, rather than only in the
--- state below. A part already carrying it is one this service switched off and has not restored, so
--- a second claim over the same lamp reads SmoothPlastic and still knows what it was: without that,
--- the second disable would record the first one's handiwork as the original and the lamp would come
--- back dead. The tag comes off only when the lamp is genuinely lit again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local Hallways = require(ReplicatedStorage.Modules.Hallways)
local TagService = require(ReplicatedStorage.Services.TagService)

local FLOOR_1_LIGHT_TAG = "Floor1Light"
local ROOM_TAG = "Room"
local NEON_OFF_TAG = "NeonOff" -- on a part: it is Neon, and this service is holding it dark
local AMBIENT_FLICKER_INTERVAL_MIN = 0.6
local AMBIENT_FLICKER_INTERVAL_MAX = 1.2
local AMBIENT_FLICKERS_MIN = 1
local AMBIENT_FLICKERS_MAX = 2
local AMBIENT_FLICKER_DURATION_MIN = 0.2
local AMBIENT_FLICKER_DURATION_MAX = 0.45
local HALLWAY_FLICKER_BATCH_SIZE = 2
local HALLWAY_HEIGHT_WINDOW = 24
local HALLWAY_BELOW_WINDOW = 4
local SPAN_EPSILON = 0.75
local ROOM_CONNECTION_GAP = 1.5

type LightState = {
	Enabled: boolean,
}

type RedLightState = {
	Color: Color3,
}

type RedState = {
	ExpiresAt: number,
	Lights: { [Light]: RedLightState },
}

type FlickerState = {
	ExpiresAt: number,
	Lights: { [Light]: LightState },
	Parts: { [BasePart]: Enum.Material },
	Particles: { [ParticleEmitter]: ParticleState },
	SoundParent: BasePart?,
}

export type FlickerClaim = {
	Released: boolean,
	States: { { Model: Model, State: FlickerState } },
}

type ParticleState = {
	Enabled: boolean,
}

type DisabledState = {
	Claims: number,
	Lights: { [Light]: LightState },
	Parts: { BasePart }, -- every part switched out of Neon; the tag is what remembers it was Neon
	Particles: { [ParticleEmitter]: ParticleState },
}

type Rectangle = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfLength: number,
	HalfWidth: number,
	FloorY: number,
}

type BranchConnection = {
	Span: Hallways.StraightSpan,
	Along: number,
	Hallways: { Hallways.Hallway },
}

export type LightClaim = {
	Models: { Model },
	Released: boolean,
}

local LightService = {}
local DisabledModels: { [Model]: DisabledState } = {}
local RedModels: { [Model]: RedState } = {}
local FlickerModels: { [Model]: FlickerState } = {}
local FlickerHallway: Hallways.Hallway? = nil
local RED_COLOR = Color3.fromRGB(255, 0, 0)

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function sameSpan(first: Hallways.StraightSpan, second: Hallways.StraightSpan): boolean
	local sameDirection = (first.Start - second.Start).Magnitude <= SPAN_EPSILON
		and (first.Finish - second.Finish).Magnitude <= SPAN_EPSILON
	local oppositeDirection = (first.Start - second.Finish).Magnitude <= SPAN_EPSILON
		and (first.Finish - second.Start).Magnitude <= SPAN_EPSILON
	return sameDirection or oppositeDirection
end

local function rectangleFromBounds(cframe: CFrame, size: Vector3, floorY: number): Rectangle
	local runsAlongX = size.X >= size.Z
	local axis = horizontal(if runsAlongX then cframe.RightVector else cframe.LookVector).Unit
	return {
		Center = cframe.Position,
		Axis = axis,
		Across = Vector3.yAxis:Cross(axis).Unit,
		HalfLength = (if runsAlongX then size.X else size.Z) / 2,
		HalfWidth = (if runsAlongX then size.Z else size.X) / 2,
		FloorY = floorY,
	}
end

local function rectangleFromPart(part: BasePart): Rectangle
	return rectangleFromBounds(part.CFrame, part.Size, part.Position.Y + part.Size.Y / 2)
end

local function rectangleFromHallway(hallway: Hallways.Hallway): Rectangle
	return {
		Center = hallway.Center,
		Axis = hallway.Axis,
		Across = hallway.Across,
		HalfLength = hallway.HalfLength,
		HalfWidth = hallway.HalfWidth,
		FloorY = hallway.FloorY,
	}
end

local function rectanglesTouch(first: Rectangle, second: Rectangle, gap: number): boolean
	if math.abs(first.FloorY - second.FloorY) > 4 then return false end

	for _, axis in { first.Axis, first.Across, second.Axis, second.Across } do
		local offset = math.abs((second.Center - first.Center):Dot(axis))
		local firstRadius = first.HalfLength * math.abs(first.Axis:Dot(axis))
			+ first.HalfWidth * math.abs(first.Across:Dot(axis))
		local secondRadius = second.HalfLength * math.abs(second.Axis:Dot(axis))
			+ second.HalfWidth * math.abs(second.Across:Dot(axis))
		if offset > firstRadius + secondRadius + gap then return false end
	end
	return true
end

local function segmentIntersection(first: Hallways.StraightSpan, second: Hallways.StraightSpan): Vector3?
	local firstDirection = first.Finish - first.Start
	local secondDirection = second.Finish - second.Start
	local determinant = firstDirection.X * secondDirection.Z - firstDirection.Z * secondDirection.X
	if math.abs(determinant) < 1e-4 then return nil end

	local between = second.Start - first.Start
	local firstAlpha = (between.X * secondDirection.Z - between.Z * secondDirection.X) / determinant
	local secondAlpha = (between.X * firstDirection.Z - between.Z * firstDirection.X) / determinant
	if firstAlpha < -0.01 or firstAlpha > 1.01 or secondAlpha < -0.01 or secondAlpha > 1.01 then
		return nil
	end
	return first.Start:Lerp(first.Finish, math.clamp(firstAlpha, 0, 1))
end

local function getSoundParent(model: Model): BasePart?
	local parents = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			local parent = descendant:FindFirstAncestorWhichIsA("BasePart")
			if parent then
				table.insert(parents, parent)
			end
		end
	end

	if #parents == 0 then return nil end
	return parents[math.random(1, #parents)]
end

local function disable(model: Model)
	local state = DisabledModels[model]
	if state then
		state.Claims += 1
		return
	end

	state = {
		Claims = 1,
		Lights = {},
		Parts = {},
		Particles = {},
	}
	DisabledModels[model] = state

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			state.Lights[descendant] = {
				Enabled = descendant.Enabled,
			}
			descendant.Enabled = false
		elseif descendant:IsA("BasePart")
			and (descendant.Material == Enum.Material.Neon or descendant:HasTag(NEON_OFF_TAG))
		then
			table.insert(state.Parts, descendant)
			descendant.Material = Enum.Material.SmoothPlastic
			descendant:AddTag(NEON_OFF_TAG)
		elseif descendant:IsA("ParticleEmitter") then
			state.Particles[descendant] = {
				Enabled = descendant.Enabled,
			}
			descendant.Enabled = false
		end
	end
end

local function addModel(claim: LightClaim, seen: { [Model]: boolean }, model: Model)
	if seen[model] then return end
	seen[model] = true
	disable(model)
	table.insert(claim.Models, model)
end

local function restore(model: Model)
	local state = DisabledModels[model]
	if not state then return end

	state.Claims -= 1
	if state.Claims > 0 then return end

	for light, lightState in state.Lights do
		light.Enabled = lightState.Enabled
	end
	for _, part in state.Parts do
		part.Material = Enum.Material.Neon
		part:RemoveTag(NEON_OFF_TAG)
	end
	for emitter, particleState in state.Particles do
		emitter.Enabled = particleState.Enabled
	end
	DisabledModels[model] = nil
end

local function containsHallway(hallway: Hallways.Hallway, position: Vector3): boolean
	local height = position.Y - hallway.FloorY
	if height > HALLWAY_HEIGHT_WINDOW or height < -HALLWAY_BELOW_WINDOW then return false end

	local offset = position - hallway.Center
	return math.abs(offset:Dot(hallway.Axis)) <= hallway.HalfLength
		and math.abs(offset:Dot(hallway.Across)) <= hallway.HalfWidth
end

--- Disables every tagged light model whose pivot is within `radius` studs of `position`.
--- Each returned claim must be released; overlapping claims keep a light off until all release it.
function LightService:DisableNear(position: Vector3, radius: number): LightClaim
	local claim: LightClaim = {
		Models = {},
		Released = false,
	}

	for _, model in LightService:GetModels() do
		if (model:GetPivot().Position - position).Magnitude <= radius then
			disable(model)
			table.insert(claim.Models, model)
		end
	end

	return claim
end

--- Disables tagged light models within `distance` studs along the hallway containing `position`.
--- Lights in crossing or nearby hallways are ignored, even when their world-space positions are
--- inside the range. A position outside the tagged hallway network affects no lights.
function LightService:DisableAlongHallway(position: Vector3, distance: number): LightClaim
	local claim: LightClaim = {
		Models = {},
		Released = false,
	}
	local hallway = Hallways.At(position)
	if not hallway then return claim end

	local creepAlong = Hallways.Along(hallway, position)
	for _, model in LightService:GetModels() do
		local modelPosition = model:GetPivot().Position
		if containsHallway(hallway, modelPosition)
			and math.abs(Hallways.Along(hallway, modelPosition) - creepAlong) <= distance
		then
			disable(model)
			table.insert(claim.Models, model)
		end
	end

	return claim
end

local function hallwaysInSpan(span: Hallways.StraightSpan): { Hallways.Hallway }
	local result = {}
	for _, hallway in Hallways.All(true) do
		local axisAlignment = math.abs(hallway.Axis:Dot(span.Axis))
		local offset = hallway.Center - span.Center
		local along = offset:Dot(span.Axis)
		local across = math.abs(offset:Dot(Vector3.yAxis:Cross(span.Axis).Unit))
		local alongOverlap = math.abs(along) <= span.Length / 2 + hallway.HalfLength + SPAN_EPSILON
		local parallel = axisAlignment >= 1 - 1e-4
		local sameNonParallel = false
		if not parallel then
			local candidate = Hallways.StraightSpanAt(hallway.Center, span.Axis)
			sameNonParallel = candidate ~= nil and sameSpan(candidate, span)
		end
		if math.abs(hallway.FloorY - span.Start.Y) <= 4
			and ((parallel and across <= hallway.HalfWidth + ROOM_CONNECTION_GAP and alongOverlap)
				or (not parallel and sameNonParallel))
		then
			table.insert(result, hallway)
		end
	end
	return result
end

local function connectedRooms(spanHallways: { Hallways.Hallway }): { [Model]: boolean }
	local rooms: { [Model]: boolean } = {}
	for _, instance in TagService:GetTaggedOfPredicate(ROOM_TAG, function(tagged: Instance)
		return tagged:IsA("Model") and tagged:IsDescendantOf(workspace)
	end) do
		local room = instance :: Model
		local floor = room:FindFirstChild("Floor", true)
		local roomRectangle
		if floor and floor:IsA("BasePart") then
			roomRectangle = rectangleFromPart(floor)
		else
			local boundsCFrame, boundsSize = room:GetBoundingBox()
			roomRectangle = rectangleFromBounds(boundsCFrame, boundsSize, boundsCFrame.Position.Y - boundsSize.Y / 2)
		end
		for _, hallway in spanHallways do
			if rectanglesTouch(roomRectangle, rectangleFromHallway(hallway), ROOM_CONNECTION_GAP) then
				rooms[room] = true
				break
			end
		end
	end
	return rooms
end

local function branchConnections(span: Hallways.StraightSpan): { BranchConnection }
	local connections = {}
	for _, other in Hallways.StraightSpans() do
		if sameSpan(other, span) then continue end
		local intersection = segmentIntersection(span, other)
		if intersection then
			table.insert(connections, {
				Span = other,
				Along = (intersection - other.Center):Dot(other.Axis),
				Hallways = hallwaysInSpan(other),
			})
		end
	end
	return connections
end

local function containsAnyHallway(hallways: { Hallways.Hallway }, position: Vector3): boolean
	for _, hallway in hallways do
		if containsHallway(hallway, position) then return true end
	end
	return false
end

--- Disables the complete straight hallway containing `position`, using the same span calculation as
--- the Sisters. It also disables every lamp in a room whose floor touches that span and the first
--- `connectedDistance` studs of every straight hallway that intersects it.
---
--- The claim is released in the usual way; overlapping effects keep each lamp dark until all claims
--- are released.
function LightService:DisableHallway(
	position: Vector3,
	preferredDirection: Vector3?,
	connectedDistance: number?
): LightClaim
	local claim: LightClaim = {
		Models = {},
		Released = false,
	}
	local span = Hallways.StraightSpanAt(position, preferredDirection)
	if not span then return claim end

	local seen: { [Model]: boolean } = {}
	local spanHallways = hallwaysInSpan(span)
	local rooms = connectedRooms(spanHallways)
	local branches = branchConnections(span)
	local branchRange = math.max(connectedDistance or 0, 0)

	for _, model in LightService:GetModels() do
		local modelPosition = model:GetPivot().Position
		local isConnected = containsAnyHallway(spanHallways, modelPosition)
		if not isConnected and branchRange > 0 then
			for _, connection in branches do
				local modelAlong = (modelPosition - connection.Span.Center):Dot(connection.Span.Axis)
				if containsAnyHallway(connection.Hallways, modelPosition)
					and math.abs(modelAlong - connection.Along) <= branchRange
				then
					isConnected = true
					break
				end
			end
		end

		if not isConnected then
			for room in rooms do
				if model:IsDescendantOf(room) then
					isConnected = true
					break
				end
			end
		end

		if isConnected then addModel(claim, seen, model) end
	end

	return claim
end

function LightService:Release(claim: LightClaim)
	if claim.Released then return end
	claim.Released = true

	for _, model in claim.Models do
		restore(model)
	end
end

--- Every owning model referenced by a `Floor1Light` tag. Map assets tag both lamp models and some of
--- their child light parts, so child tags collapse onto one model instead of being missed or claimed
--- twice.
function LightService:GetModels(): { Model }
	local models = {}
	local seen: { [Model]: boolean } = {}
	for _, instance in TagService:GetTaggedOfPredicate(FLOOR_1_LIGHT_TAG, function(tagged: Instance)
		return tagged:IsDescendantOf(workspace)
	end) do
		local model = if instance:IsA("Model")
			then instance
			else instance:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			table.insert(models, model)
		end
	end
	return models
end

--- Turns every light in one floor-light model red for `duration`, restoring its original color
--- afterward. A concurrent warning extends the existing red effect.
function LightService:WarnRed(model: Model, duration: number)
	if duration <= 0 then return end

	local existing = RedModels[model]
	if existing then
		existing.ExpiresAt = math.max(existing.ExpiresAt, os.clock() + duration)
		return
	end

	local state: RedState = {
		ExpiresAt = os.clock() + duration,
		Lights = {},
	}
	RedModels[model] = state
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			state.Lights[descendant] = {
				Color = descendant.Color,
			}
			descendant.Color = RED_COLOR
		end
	end

	task.spawn(function()
		while true do
			local remaining = state.ExpiresAt - os.clock()
			if remaining <= 0 then break end
			task.wait(remaining)
		end

		if RedModels[model] ~= state then return end
		for light, lightState in state.Lights do
			light.Color = lightState.Color
		end
		RedModels[model] = nil
	end)
end

local function beginFlicker(model: Model, duration: number, playSound: boolean?): FlickerState?
	local existing = FlickerModels[model]
	if existing then
		existing.ExpiresAt = math.max(existing.ExpiresAt, os.clock() + duration)
		return nil
	end

	local state: FlickerState = {
		ExpiresAt = os.clock() + duration,
		Lights = {},
		Parts = {},
		Particles = {},
		SoundParent = if playSound ~= false then getSoundParent(model) else nil,
	}
	FlickerModels[model] = state

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			state.Lights[descendant] = {
				Enabled = descendant.Enabled,
			}
		elseif descendant:IsA("BasePart")
			and (descendant.Material == Enum.Material.Neon or descendant:HasTag(NEON_OFF_TAG))
		then
			state.Parts[descendant] = descendant.Material
		elseif descendant:IsA("ParticleEmitter") then
			state.Particles[descendant] = {
				Enabled = descendant.Enabled,
			}
		end
	end

	if playSound ~= false and state.SoundParent then
		AudioService:Play3DSound("Flicker", state.SoundParent, false, "SFX")
	end
	return state
end

local function setFlickerDark(state: FlickerState)
	for light in state.Lights do
		light.Enabled = false
	end
	for part in state.Parts do
		part.Material = Enum.Material.SmoothPlastic
	end
	for emitter in state.Particles do
		emitter.Enabled = false
	end
end

local function setFlickerLit(state: FlickerState)
	for light, lightState in state.Lights do
		light.Enabled = lightState.Enabled
	end
	for part, material in state.Parts do
		part.Material = material
	end
	for emitter, particleState in state.Particles do
		emitter.Enabled = particleState.Enabled
	end
end

local function restoreFlicker(model: Model, state: FlickerState)
	if FlickerModels[model] ~= state then return end
	for light, lightState in state.Lights do
		light.Enabled = lightState.Enabled
	end
	for part, material in state.Parts do
		part.Material = material
	end
	for emitter, particleState in state.Particles do
		emitter.Enabled = particleState.Enabled
	end
	FlickerModels[model] = nil
end

local function flickerModel(model: Model, duration: number)
	local state = beginFlicker(model, duration, true)
	if not state then return end

	task.spawn(function()
		while true do
			local remaining = state.ExpiresAt - os.clock()
			if remaining <= 0 then break end

			if math.random() < 0.5 then
				setFlickerDark(state)
			else
				setFlickerLit(state)
			end

			task.wait(0.1 + math.random() * 0.1)
		end

		restoreFlicker(model, state)
	end)
end

--- Flickers every lamp in a straight hallway with independent, rapid timings. The returned claim
--- lets a caller stop the effect early without leaving a lamp dark.
function LightService:FlickerChaosAlongHallway(
	position: Vector3,
	duration: number,
	intervalMin: number,
	intervalMax: number
): FlickerClaim
	local claim: FlickerClaim = {
		Released = duration <= 0,
		States = {},
	}
	if claim.Released then return claim end

	local span = Hallways.StraightSpanAt(position)
	if not span then
		claim.Released = true
		return claim
	end
	local spanHallways = hallwaysInSpan(span)

	local minimum = math.max(math.min(intervalMin, intervalMax), 0.02)
	local maximum = math.max(math.max(intervalMin, intervalMax), minimum)
	for _, model in LightService:GetModels() do
		if containsAnyHallway(spanHallways, model:GetPivot().Position) then
			local state = beginFlicker(model, duration, true)
			if state then
				state.ExpiresAt = os.clock() + duration
				table.insert(claim.States, { Model = model, State = state })
				task.spawn(function()
					task.wait(math.random() * (maximum - minimum) + minimum)
					while not claim.Released and state.ExpiresAt > os.clock() do
						if math.random() < 0.55 then
							setFlickerDark(state)
						else
							setFlickerLit(state)
						end
						task.wait(math.random() * (maximum - minimum) + minimum)
					end
					restoreFlicker(model, state)
				end)
			end
		end
	end

	return claim
end

function LightService:ReleaseFlicker(claim: FlickerClaim)
	if claim.Released then return end
	claim.Released = true
	for _, entry in claim.States do
		restoreFlicker(entry.Model, entry.State)
	end
end

--- Flickers every light model in the hallway containing `position` for `duration`. Lights turn on and
--- off randomly, creating an unsettling effect without spilling into crossing hallways.
function LightService:FlickerAlongHallway(position: Vector3, duration: number)
	if duration <= 0 then return end
	local hallway = FlickerHallway
	if not hallway or not containsHallway(hallway, position) then
		hallway = Hallways.At(position)
		FlickerHallway = hallway
	end
	if not hallway then return end

	local models = {} :: { Model }
	for _, model in LightService:GetModels() do
		if containsHallway(hallway, model:GetPivot().Position) then
			table.insert(models, model)
		end
	end
	if #models == 0 then return end

	task.spawn(function()
		local states = {} :: { { Model: Model, State: FlickerState } }
		for index, model in models do
			local state = beginFlicker(model, duration, false)
			if state then
				state.ExpiresAt = os.clock() + duration
				setFlickerDark(state)
				table.insert(states, { Model = model, State = state })
			end
			if index % HALLWAY_FLICKER_BATCH_SIZE == 0 then
				RunService.Heartbeat:Wait()
			end
		end

		local remaining = 0
		for _, entry in states do
			remaining = math.max(remaining, entry.State.ExpiresAt - os.clock())
		end
		if remaining > 0 then task.wait(remaining) end

		for index, entry in states do
			restoreFlicker(entry.Model, entry.State)
			if index % HALLWAY_FLICKER_BATCH_SIZE == 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

local function startAmbientFlickering()
	task.spawn(function()
		while true do
			task.wait(AMBIENT_FLICKER_INTERVAL_MIN
				+ math.random() * (AMBIENT_FLICKER_INTERVAL_MAX - AMBIENT_FLICKER_INTERVAL_MIN))

			local models = LightService:GetModels()
			local flickerCount = math.min(
				math.random(AMBIENT_FLICKERS_MIN, AMBIENT_FLICKERS_MAX),
				#models
			)
			for _ = 1, flickerCount do
				local model = table.remove(models, math.random(1, #models))
				flickerModel(model, AMBIENT_FLICKER_DURATION_MIN
					+ math.random() * (AMBIENT_FLICKER_DURATION_MAX - AMBIENT_FLICKER_DURATION_MIN))
			end
		end
	end)
end

startAmbientFlickering()

return LightService
