local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local Hallways = require(ReplicatedStorage.Modules.Hallways)
local TagService = require(ReplicatedStorage.Services.TagService)

local FLOOR_1_LIGHT_TAG = "Floor1Light"
local ROOM_TAG = "Room"
local NEON_OFF_TAG = "NeonOff"
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

type Baseline = {
	Lights: { [Light]: { Enabled: boolean, Color: Color3 } },
	Neon: { [BasePart]: boolean },
	Particles: { [ParticleEmitter]: boolean },
}

type Flicker = {
	Model: Model,
	ExpiresAt: number,
	Dark: boolean,
}

type Red = {
	ExpiresAt: number,
}

type Lamp = {
	Baseline: Baseline,
	OffClaims: number,
	Flicker: Flicker?,
	Red: Red?,
}

export type FlickerClaim = {
	Released: boolean,
	States: { { Model: Model, State: Flicker } },
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
	SpanAlong: number,
	Hallways: { Hallways.Hallway },
}

export type LightClaim = {
	Models: { Model },
	Released: boolean,
}

local LightService = {}
local Lamps: { [Model]: Lamp } = {}
local Watched: { [Model]: boolean } = {}
local FlickerHallway: Hallways.Hallway? = nil
local RED_COLOR = Color3.fromRGB(255, 0, 0)
local RED_ATTRIBUTE = "ChaosRed"
local LightModels: { Model } = {}
local LightModelsDirty = true

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

local function captureBaseline(model: Model): Baseline
	local baseline: Baseline = { Lights = {}, Neon = {}, Particles = {} }

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			baseline.Lights[descendant] = { Enabled = descendant.Enabled, Color = descendant.Color }
		elseif descendant:IsA("BasePart")
			and (descendant.Material == Enum.Material.Neon or descendant:HasTag(NEON_OFF_TAG))
		then
			baseline.Neon[descendant] = true
		elseif descendant:IsA("ParticleEmitter") then
			baseline.Particles[descendant] = descendant.Enabled
		end
	end

	return baseline
end

local function apply(model: Model)
	local lamp = Lamps[model]
	if not lamp then return end

	local flicker = lamp.Flicker
	local dark = lamp.OffClaims > 0 or (flicker ~= nil and flicker.Dark)
	local red = lamp.Red ~= nil

	for light, base in lamp.Baseline.Lights do
		light.Enabled = base.Enabled and not dark
		light.Color = if red then RED_COLOR else base.Color
	end
	for part in lamp.Baseline.Neon do
		if dark then
			part.Material = Enum.Material.SmoothPlastic
			part:AddTag(NEON_OFF_TAG)
		else
			part.Material = Enum.Material.Neon
			part:RemoveTag(NEON_OFF_TAG)
		end
	end
	for emitter, enabled in lamp.Baseline.Particles do
		emitter.Enabled = enabled and not dark
	end
end

local function acquire(model: Model): Lamp
	local existing = Lamps[model]
	if existing then return existing end

	local lamp: Lamp = {
		Baseline = captureBaseline(model),
		OffClaims = 0,
	}
	Lamps[model] = lamp

	if not Watched[model] then
		Watched[model] = true
		model.Destroying:Once(function()
			Watched[model] = nil
			Lamps[model] = nil
		end)
	end

	return lamp
end

local function releaseIfIdle(model: Model)
	local lamp = Lamps[model]
	if not lamp then return end
	if lamp.OffClaims > 0 or lamp.Flicker or lamp.Red then return end
	Lamps[model] = nil
end

local function disable(model: Model)
	local lamp = acquire(model)
	lamp.OffClaims += 1
	apply(model)
end

local function addModel(claim: LightClaim, seen: { [Model]: boolean }, model: Model)
	if seen[model] then return end
	seen[model] = true
	disable(model)
	table.insert(claim.Models, model)
end

local function restore(model: Model)
	local lamp = Lamps[model]
	if not lamp then return end

	lamp.OffClaims = math.max(lamp.OffClaims - 1, 0)
	apply(model)
	releaseIfIdle(model)
end

local function containsHallway(hallway: Hallways.Hallway, position: Vector3): boolean
	local height = position.Y - hallway.FloorY
	if height > HALLWAY_HEIGHT_WINDOW or height < -HALLWAY_BELOW_WINDOW then return false end

	local offset = position - hallway.Center
	return math.abs(offset:Dot(hallway.Axis)) <= hallway.HalfLength
		and math.abs(offset:Dot(hallway.Across)) <= hallway.HalfWidth
end

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
				SpanAlong = (intersection - span.Center):Dot(span.Axis),
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

function LightService:DisableHallway(
	position: Vector3,
	preferredDirection: Vector3?,
	connectedDistance: number?,
	spanDistance: number?
): LightClaim
	local claim: LightClaim = {
		Models = {},
		Released = false,
	}
	local span = Hallways.StraightSpanAt(position, preferredDirection)
	if not span then return claim end

	local seen: { [Model]: boolean } = {}
	local spanHallways = hallwaysInSpan(span)
	local origin = (position - span.Center):Dot(span.Axis)
	local reach = if spanDistance and spanDistance > 0 then spanDistance else nil

	local nearHallways = spanHallways
	if reach then
		nearHallways = {}
		for _, hallway in spanHallways do
			local hallwayAlong = (hallway.Center - span.Center):Dot(span.Axis)
			if math.abs(hallwayAlong - origin) <= reach + hallway.HalfLength then
				table.insert(nearHallways, hallway)
			end
		end
	end

	local rooms = connectedRooms(nearHallways)
	local branches = branchConnections(span)
	local branchRange = math.max(connectedDistance or 0, 0)

	for _, model in LightService:GetModels() do
		local modelPosition = model:GetPivot().Position
		local isConnected = containsAnyHallway(spanHallways, modelPosition)
			and (not reach or math.abs((modelPosition - span.Center):Dot(span.Axis) - origin) <= reach)
		if not isConnected and branchRange > 0 then
			for _, connection in branches do
				if reach and math.abs(connection.SpanAlong - origin) > reach then continue end
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

function LightService:DisableModel(model: Model): LightClaim
	local claim: LightClaim = {
		Models = { model },
		Released = false,
	}
	disable(model)
	return claim
end

function LightService:Release(claim: LightClaim)
	if claim.Released then return end
	claim.Released = true

	for _, model in claim.Models do
		restore(model)
	end
end

function LightService:GetModels(): { Model }
	if not LightModelsDirty then return LightModels end

	table.clear(LightModels)
	local seen: { [Model]: boolean } = {}
	for _, instance in TagService:GetTaggedOfPredicate(FLOOR_1_LIGHT_TAG, function(tagged: Instance)
		return tagged:IsDescendantOf(workspace)
	end) do
		local model = if instance:IsA("Model")
			then instance
			else instance:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			table.insert(LightModels, model)
		end
	end
	LightModelsDirty = false
	return LightModels
end

function LightService:WarnRed(model: Model, duration: number)
	if duration <= 0 then return end

	local lamp = acquire(model)
	local existing = lamp.Red
	if existing then
		existing.ExpiresAt = math.max(existing.ExpiresAt, os.clock() + duration)
		return
	end

	local red: Red = { ExpiresAt = os.clock() + duration }
	lamp.Red = red
	model:SetAttribute(RED_ATTRIBUTE, true)
	apply(model)

	task.spawn(function()
		while true do
			local remaining = red.ExpiresAt - os.clock()
			if remaining <= 0 then break end
			task.wait(remaining)
		end

		local current = Lamps[model]
		if not current or current.Red ~= red then return end
		current.Red = nil
		model:SetAttribute(RED_ATTRIBUTE, nil)
		apply(model)
		releaseIfIdle(model)
	end)
end

local function beginFlicker(model: Model, duration: number, playSound: boolean?): Flicker?
	local lamp = acquire(model)
	local existing = lamp.Flicker
	if existing then
		existing.ExpiresAt = math.max(existing.ExpiresAt, os.clock() + duration)
		return nil
	end

	local flicker: Flicker = {
		Model = model,
		ExpiresAt = os.clock() + duration,
		Dark = false,
	}
	lamp.Flicker = flicker

	if playSound ~= false then
		local soundParent = getSoundParent(model)
		if soundParent then
			AudioService:Play3DSound("Flicker", soundParent, false, "SFX")
		end
	end
	return flicker
end

local function flickerActive(flicker: Flicker): boolean
	local lamp = Lamps[flicker.Model]
	return lamp ~= nil and lamp.Flicker == flicker
end

local function setFlickerDark(flicker: Flicker)
	flicker.Dark = true
	apply(flicker.Model)
end

local function setFlickerLit(flicker: Flicker)
	flicker.Dark = false
	apply(flicker.Model)
end

local function restoreFlicker(model: Model, flicker: Flicker)
	local lamp = Lamps[model]
	if not lamp or lamp.Flicker ~= flicker then return end

	lamp.Flicker = nil
	apply(model)
	releaseIfIdle(model)
end

local function flickerModel(model: Model, duration: number)
	local flicker = beginFlicker(model, duration, true)
	if not flicker then return end

	task.spawn(function()
		while flickerActive(flicker) do
			local remaining = flicker.ExpiresAt - os.clock()
			if remaining <= 0 then break end

			if math.random() < 0.5 then
				setFlickerDark(flicker)
			else
				setFlickerLit(flicker)
			end

			task.wait(0.1 + math.random() * 0.1)
		end

		restoreFlicker(model, flicker)
	end)
end

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
			local flicker = beginFlicker(model, duration, true)
			if flicker then
				flicker.ExpiresAt = os.clock() + duration
				table.insert(claim.States, { Model = model, State = flicker })
				task.spawn(function()
					task.wait(math.random() * (maximum - minimum) + minimum)
					while not claim.Released and flickerActive(flicker) and flicker.ExpiresAt > os.clock() do
						if math.random() < 0.55 then
							setFlickerDark(flicker)
						else
							setFlickerLit(flicker)
						end
						task.wait(math.random() * (maximum - minimum) + minimum)
					end
					restoreFlicker(model, flicker)
				end)
			end
		end
	end

	return claim
end

function LightService:FlickerHallwayContaining(
	position: Vector3,
	duration: number,
	intervalMin: number?,
	intervalMax: number?
)
	if duration <= 0 then return end
	local hallway = Hallways.At(position)
	if not hallway then return end

	local minimum = math.max(math.min(intervalMin or 0.08, intervalMax or 0.22), 0.02)
	local maximum = math.max(intervalMax or 0.22, minimum)
	for _, model in LightService:GetModels() do
		if containsHallway(hallway, model:GetPivot().Position) then
			local flicker = beginFlicker(model, duration, false)
			if flicker then
				task.spawn(function()
					while flickerActive(flicker) and flicker.ExpiresAt > os.clock() do
						if math.random() < 0.55 then
							setFlickerDark(flicker)
						else
							setFlickerLit(flicker)
						end
						task.wait(math.random() * (maximum - minimum) + minimum)
					end
					restoreFlicker(model, flicker)
				end)
			end
		end
	end
end

function LightService:ReleaseFlicker(claim: FlickerClaim)
	if claim.Released then return end
	claim.Released = true
	for _, entry in claim.States do
		restoreFlicker(entry.Model, entry.State)
	end
end

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
		local states = {} :: { { Model: Model, State: Flicker } }
		for index, model in models do
			local flicker = beginFlicker(model, duration, false)
			if flicker then
				flicker.ExpiresAt = os.clock() + duration
				setFlickerDark(flicker)
				table.insert(states, { Model = model, State = flicker })
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
			if flickerCount > 0 then
				local firstIndex = math.random(#models)
				flickerModel(models[firstIndex], AMBIENT_FLICKER_DURATION_MIN
					+ math.random() * (AMBIENT_FLICKER_DURATION_MAX - AMBIENT_FLICKER_DURATION_MIN))

				if flickerCount > 1 then
					local secondIndex = math.random(#models - 1)
					if secondIndex >= firstIndex then secondIndex += 1 end
					flickerModel(models[secondIndex], AMBIENT_FLICKER_DURATION_MIN
						+ math.random() * (AMBIENT_FLICKER_DURATION_MAX - AMBIENT_FLICKER_DURATION_MIN))
				end
			end
		end
	end)
end

CollectionService:GetInstanceAddedSignal(FLOOR_1_LIGHT_TAG):Connect(function()
	LightModelsDirty = true
end)
CollectionService:GetInstanceRemovedSignal(FLOOR_1_LIGHT_TAG):Connect(function()
	LightModelsDirty = true
end)

LightService:GetModels()
startAmbientFlickering()

return LightService
