local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.StreamingConfig)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MathService = require(ReplicatedStorage.Services.MathService)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)

local HallwayStreamingService = {}

if not Config.Enabled then
	function HallwayStreamingService:PrepareTeleport(player: Player, position: Vector3): boolean
		pcall(function()
			player:RequestStreamAroundAsync(position, Config.TeleportTimeout)
		end)
		return true
	end
	return HallwayStreamingService
end

local MAZE_ROOT_NAME = "Maze15"
local GENERATED_ROOT_NAME = "StreamingChunks"
local FLOOR_TAG = "MazeFloor"
local CONNECTOR_FLOOR_TAG = "HallwayRoomFloor"
local ENEMY_TAG = "Enemy"
local EPSILON = 0.75
local CONNECTOR_MARGIN = 2
local CONNECTOR_ALONG_MARGIN = 20
local CONNECTOR_CROSS_MARGIN = 32
local CONNECTION_VERTICAL_MARGIN = 4
local ASSET_CROSS_LIMIT = 24

type Rect = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfLength: number,
	HalfWidth: number,
	FloorY: number,
}

type Connector = {
	Model: Model,
	Rect: Rect,
}

type Segment = {
	Id: string,
	GroupId: string,
	Span: any,
	StartAlong: number,
	EndAlong: number,
	Model: Model,
}

type Connection = {
	GroupId: string,
	Position: Vector3,
}

type EnemyPlacement = {
	Model: Model,
	Connector: Connector?,
	Segment: Segment?,
	Ignored: boolean,
}

type Group = {
	Id: string,
	Span: any,
	Segments: { Segment },
	Connectors: { Connector },
	Connections: { Connection },
}

type PlayerState = {
	Persistent: { [Model]: boolean },
	Desired: { [Model]: boolean },
	RetryAt: { [Model]: number },
	CurrentGroup: string?,
	Grace: { [string]: number },
	HorizontalSpeed: number,
	TeleportDesired: { [Model]: boolean }?,
	TeleportDesiredExpires: number?,
	LastMissingReport: number,
}

local GeneratedRoot: Folder?
local Groups: { Group } = {}
local GroupsById: { [string]: Group } = {}
local Segments: { Segment } = {}
local Connectors: { Connector } = {}
local ConnectorGroups: { [Model]: { [string]: boolean } } = {}
local GlobalModels: { Model } = {}
local EnemyPlacements: { EnemyPlacement } = {}
local PlayersState: { [Player]: PlayerState } = {}
local ModelsByStreamingId: { [string]: Model } = {}
local Ready = false
local ReadyEvent = Instance.new("BindableEvent")
local PendingTeleports: { [Player]: { Token: number, Done: BindableEvent } } = {}
local TeleportToken = 0
local Accumulator = 0
local Active = false
local ExpectedModelsRemote: RemoteEvent?
local ReportMissingRemote: RemoteEvent?

local horizontal = MathService.Horizontal

local function unitHorizontal(vector: Vector3): Vector3
	local flat = horizontal(vector)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
end

local function getGeneratedRoot(): Folder
	if GeneratedRoot and GeneratedRoot.Parent then return GeneratedRoot end

	local existing = workspace:FindFirstChild(GENERATED_ROOT_NAME)
	if existing and existing:IsA("Folder") then
		GeneratedRoot = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = GENERATED_ROOT_NAME
	folder.Parent = workspace
	GeneratedRoot = folder
	return folder
end

local function setPersistentMode(model: Model): boolean
	local streamingId = model:GetAttribute(Config.ModelIdAttribute)
	if type(streamingId) ~= "string" or (ModelsByStreamingId[streamingId] and ModelsByStreamingId[streamingId] ~= model) then
		streamingId = HttpService:GenerateGUID(false)
		model:SetAttribute(Config.ModelIdAttribute, streamingId)
	end
	if ModelsByStreamingId[streamingId] ~= model then
		model.Destroying:Connect(function()
			if ModelsByStreamingId[streamingId] == model then
				ModelsByStreamingId[streamingId] = nil
			end
		end)
	end
	ModelsByStreamingId[streamingId] = model
	if not model:HasTag(Config.ModelTag) then model:AddTag(Config.ModelTag) end
	if model.ModelStreamingMode == Enum.ModelStreamingMode.PersistentPerPlayer then return true end

	local ok, err = pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	if not ok then
		warn(`[HallwayStreamingService] Could not set PersistentPerPlayer on {model:GetFullName()}: {err}`)
	end
	return ok
end

local function rectFromPart(part: BasePart): Rect
	local runsAlongX = part.Size.X >= part.Size.Z
	local axis = unitHorizontal(if runsAlongX then part.CFrame.RightVector else part.CFrame.LookVector)
	return {
		Center = part.Position,
		Axis = axis,
		Across = Vector3.yAxis:Cross(axis).Unit,
		HalfLength = (if runsAlongX then part.Size.X else part.Size.Z) / 2,
		HalfWidth = (if runsAlongX then part.Size.Z else part.Size.X) / 2,
		FloorY = part.Position.Y + part.Size.Y / 2,
	}
end

local function supportHalf(rect: Rect, axis: Vector3): number
	return rect.HalfLength * math.abs(rect.Axis:Dot(axis))
		+ rect.HalfWidth * math.abs(rect.Across:Dot(axis))
end

local function sameSpan(first: any, second: any): boolean
	local sameDirection = (first.Start - second.Start).Magnitude <= EPSILON
		and (first.Finish - second.Finish).Magnitude <= EPSILON
	local oppositeDirection = (first.Start - second.Finish).Magnitude <= EPSILON
		and (first.Finish - second.Start).Magnitude <= EPSILON
	return sameDirection or oppositeDirection
end

local function buildConnectors()
	local seen: { [Model]: boolean } = {}
	for _, instance in CollectionService:GetTagged(CONNECTOR_FLOOR_TAG) do
		if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then continue end
		local model = instance:FindFirstAncestorOfClass("Model")
		if not model or seen[model] then continue end
		seen[model] = true

		local connector: Connector = {
			Model = model,
			Rect = rectFromPart(instance),
		}
		setPersistentMode(model)
		table.insert(Connectors, connector)
		ConnectorGroups[model] = {}
	end
end

local function buildSpans(): { any }
	local spans = {}
	for _, raw in Hallways.StraightSpans() do
		local duplicate = false
		for _, existing in spans do
			if sameSpan(raw, existing) then
				duplicate = true
				break
			end
		end
		if duplicate then continue end

		raw.Axis = unitHorizontal(raw.Finish - raw.Start)
		raw.Across = Vector3.yAxis:Cross(raw.Axis).Unit
		raw.Length = (raw.Finish - raw.Start).Magnitude
		table.insert(spans, raw)
	end

	table.sort(spans, function(first, second)
		return first.Center.X == second.Center.X
			and first.Center.Z < second.Center.Z
			or first.Center.X < second.Center.X
	end)
	return spans
end

local function addCut(cuts: { number }, value: number, length: number)
	if value <= EPSILON or value >= length - EPSILON then return end
	for _, existing in cuts do
		if math.abs(existing - value) <= EPSILON then return end
	end
	table.insert(cuts, value)
end

local function addJunction(junctions: { number }, value: number, length: number)
	if value <= EPSILON or value >= length - EPSILON then return end
	for _, existing in junctions do
		if math.abs(existing - value) <= EPSILON then return end
	end
	table.insert(junctions, value)
end

local function connectorInterval(span: any, connector: Connector): (number?, number?)
	local offset = connector.Rect.Center - span.Start
	local along = offset:Dot(span.Axis)
	local across = math.abs(offset:Dot(span.Across))
	local acrossHalf = supportHalf(connector.Rect, span.Across)
	if across > acrossHalf + CONNECTOR_CROSS_MARGIN then
		return nil, nil
	end

	local half = supportHalf(connector.Rect, span.Axis) + CONNECTOR_ALONG_MARGIN
	return along - half, along + half
end

local function buildGroups(spans: { any })
	for index, span in spans do
		local groupId = `Hallway_{index}`
		local group: Group = {
			Id = groupId,
			Span = span,
			Segments = {},
			Connectors = {},
			Connections = {},
		}
		Groups[index] = group
		GroupsById[groupId] = group

		local cuts = { 0, span.Length }
		local junctions = {}

		for _, node in HallwayGraph:Get() do
			local offset = node.Position - span.Start
			local along = offset:Dot(span.Axis)
			local across = math.abs(offset:Dot(span.Across))
			if across <= 12 and along >= -EPSILON and along <= span.Length + EPSILON
				and HallwayGraph:CountExits(node) >= 3
			then
				addJunction(junctions, along, span.Length)
			end
		end

		for _, connector in Connectors do
			local first, last = connectorInterval(span, connector)
			if not first or not last or last < -EPSILON or first > span.Length + EPSILON then continue end
			first = math.clamp(first, 0, span.Length)
			last = math.clamp(last, 0, span.Length)
			addCut(cuts, first, span.Length)
			addCut(cuts, last, span.Length)
			addJunction(junctions, first, span.Length)
			addJunction(junctions, last, span.Length)
			table.insert(group.Connectors, connector)
			ConnectorGroups[connector.Model][groupId] = true
		end

		for _, junction in junctions do
			addCut(cuts, junction - Config.ApproachLength, span.Length)
			addCut(cuts, junction + Config.ApproachLength, span.Length)
		end

		table.sort(cuts)
		table.sort(junctions)

		for segmentIndex = 1, #cuts - 1 do
			local startAlong = cuts[segmentIndex]
			local endAlong = cuts[segmentIndex + 1]
			if endAlong - startAlong <= EPSILON then continue end

			local isApproach = false
			for _, junction in junctions do
				if endAlong >= junction - Config.ApproachLength - EPSILON
					and startAlong <= junction + Config.ApproachLength + EPSILON
				then
					isApproach = true
					break
				end
			end

			local model = Instance.new("Model")
			model.Name = `HallwayChunk_{index}_{segmentIndex}`
			model:SetAttribute("StreamingChunk", true)
			model:SetAttribute("HallwayId", groupId)
			model:SetAttribute("ChunkId", model.Name)
			model:SetAttribute("ChunkKind", if isApproach then "Approach" else "Hallway")
			model:SetAttribute("StartAlong", startAlong)
			model:SetAttribute("EndAlong", endAlong)
			setPersistentMode(model)
			model.Parent = getGeneratedRoot()

			local segment: Segment = {
				Id = model.Name,
				GroupId = groupId,
				Span = span,
				StartAlong = startAlong,
				EndAlong = endAlong,
				Model = model,
			}
			table.insert(group.Segments, segment)
			table.insert(Segments, segment)
		end
	end

	for firstIndex, first in Groups do
		for secondIndex = firstIndex + 1, #Groups do
			local second = Groups[secondIndex]
			local firstSpan, secondSpan = first.Span, second.Span
			if math.abs(firstSpan.Start.Y - secondSpan.Start.Y) > CONNECTION_VERTICAL_MARGIN then
				continue
			end
			local determinant = firstSpan.Axis.X * secondSpan.Axis.Z
				- firstSpan.Axis.Z * secondSpan.Axis.X
			if math.abs(determinant) <= 1e-4 then continue end

			local difference = secondSpan.Start - firstSpan.Start
			local firstAlong = (difference.X * secondSpan.Axis.Z - difference.Z * secondSpan.Axis.X) / determinant
			local secondAlong = (difference.X * firstSpan.Axis.Z - difference.Z * firstSpan.Axis.X) / determinant
			if firstAlong < -EPSILON or firstAlong > firstSpan.Length + EPSILON
				or secondAlong < -EPSILON or secondAlong > secondSpan.Length + EPSILON
			then
				continue
			end

			local intersection = firstSpan.Start + firstSpan.Axis * firstAlong
			local secondIntersection = secondSpan.Start + secondSpan.Axis * secondAlong
			if horizontal(intersection - secondIntersection).Magnitude <= 16 then
				local position = intersection:Lerp(secondIntersection, 0.5)
				table.insert(first.Connections, { GroupId = second.Id, Position = position })
				table.insert(second.Connections, { GroupId = first.Id, Position = position })
			end
		end
	end
end

local function isIgnored(instance: Instance): boolean
	if instance:HasTag(Config.IgnoreTag) then return true end
	local ancestor = instance.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:HasTag(Config.IgnoreTag) then return true end
		ancestor = ancestor.Parent
	end
	return false
end

local GlobalModel: Model?

local function getGlobalModel(): Model
	if GlobalModel and GlobalModel.Parent then return GlobalModel end

	local model = Instance.new("Model")
	model.Name = "StreamingGlobal"
	model:SetAttribute("StreamingIgnore", true)
	setPersistentMode(model)
	model.Parent = getGeneratedRoot()
	GlobalModel = model
	table.insert(GlobalModels, model)
	return model
end

local function moveIgnoredAssets()
	for _, instance in CollectionService:GetTagged(Config.IgnoreTag) do
		if not instance:IsDescendantOf(workspace) or instance:IsDescendantOf(getGeneratedRoot()) then continue end
		if instance:IsA("Folder") or instance:IsA("Model") or instance:IsA("BasePart") then
			instance.Parent = getGlobalModel()
		end
	end
end

local function getAssetPosition(instance: Instance): Vector3
	if instance:IsA("BasePart") then return instance.Position end
	if instance:IsA("Model") then return instance:GetBoundingBox().Position end
	return Vector3.zero
end

local function getAssetExtents(instance: Instance): Vector3
	if instance:IsA("Model") then return instance:GetExtentsSize() end
	if not instance:IsA("BasePart") then return Vector3.zero end

	local cframe, size = instance.CFrame, instance.Size
	local right, up, look = cframe.RightVector, cframe.UpVector, cframe.LookVector
	return Vector3.new(
		math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z,
		math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z,
		math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z
	)
end

local function distanceToSegment(position: Vector3, segment: Segment): number
	local span = segment.Span
	local offset = position - span.Start
	local along = offset:Dot(span.Axis)
	local across = math.abs(offset:Dot(span.Across))
	local segmentOutside = if along < segment.StartAlong
		then segment.StartAlong - along
		elseif along > segment.EndAlong then along - segment.EndAlong else 0
	local vertical = math.abs(position.Y - span.Start.Y)
	return across + segmentOutside + vertical * 0.5
end

local function nearestSegmentInGroup(position: Vector3, group: Group): Segment?
	local segments = group.Segments
	if #segments == 0 then return nil end

	local along = (position - group.Span.Start):Dot(group.Span.Axis)
	local first, last = 1, #segments
	while first < last do
		local middle = math.floor((first + last) / 2)
		if segments[middle].EndAlong >= along then
			last = middle
		else
			first = middle + 1
		end
	end
	return segments[first]
end

local function nearestSegment(
	position: Vector3,
	preferredDirection: Vector3?,
	preferredGroupId: string?
): Segment?
	local nearest: Segment? = nil
	local best = math.huge
	local bestAlignment = -1
	local direction = preferredDirection and horizontal(preferredDirection)
	if direction and direction.Magnitude > 1e-3 then
		direction = direction.Unit
	else
		direction = nil
	end
	local selectionSlack = if direction or preferredGroupId then Config.CorridorSelectionSlack else 1e-3

	for _, group in Groups do
		local segment = nearestSegmentInGroup(position, group)
		if not segment then continue end
		local distance = distanceToSegment(position, segment)
		local alignment = if direction then math.abs(segment.Span.Axis:Dot(direction)) else 0
		local closer = distance < best - selectionSlack
		local tied = math.abs(distance - best) <= selectionSlack
		local preferred = tied and segment.GroupId == preferredGroupId
			and (not nearest or nearest.GroupId ~= preferredGroupId)
		local betterAligned = tied and alignment > bestAlignment + 1e-3
			and (not nearest or nearest.GroupId ~= preferredGroupId)
		if closer or preferred or betterAligned then
			best = distance
			bestAlignment = alignment
			nearest = segment
		end
	end
	return nearest
end

local function chooseOwningSegment(position: Vector3, extents: Vector3): Segment?
	local nearest: Segment? = nil
	local best = math.huge
	for _, group in Groups do
		local segment = nearestSegmentInGroup(position, group)
		if not segment then continue end
		local across = segment.Span.Across
		local halfAcross = (math.abs(across.X) * extents.X + math.abs(across.Z) * extents.Z) / 2
		if halfAcross > ASSET_CROSS_LIMIT then continue end

		local distance = distanceToSegment(position, segment)
		if distance < best then
			best = distance
			nearest = segment
		end
	end
	return nearest
end

local function collectRoots(folder: Instance, roots: { Instance })
	for _, child in folder:GetChildren() do
		if child:HasTag(Config.IgnoreTag) then continue end
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(roots, child)
		elseif child:IsA("Folder") then
			collectRoots(child, roots)
		end
	end
end

local function assignMapAssets(mazeRoot: Instance)
	local roots = {}
	for _, name in { "Floors", "Walls", "Ceiling", "Stations", "Doors", "CeilingLights", "PictureFrames", "Runners" } do
		local folder = mazeRoot:FindFirstChild(name)
		if folder then collectRoots(folder, roots) end
	end

	local assigned = 0
	local global = 0
	for _, root in roots do
		if not root.Parent or root:IsDescendantOf(getGeneratedRoot()) or isIgnored(root) then continue end

		local extents = getAssetExtents(root)
		if math.max(extents.X, extents.Z) > Config.GlobalAssetSize then
			root.Parent = getGlobalModel()
			global += 1
			continue
		end

		local segment = chooseOwningSegment(getAssetPosition(root), extents)
		if not segment then
			root.Parent = getGlobalModel()
			global += 1
			continue
		end
		root.Parent = segment.Model
		assigned += 1
	end

	print(`[HallwayStreamingService] assigned {assigned} map assets to {#Segments} physical chunks, {global} kept global`)
end

local function prepareMap()
	local mazeRoot = workspace:FindFirstChild(MAZE_ROOT_NAME)
	if not mazeRoot then
		warn("[HallwayStreamingService] Workspace.Maze15 was not found")
		return false
	end

	buildConnectors()
	local spans = buildSpans()
	if #spans == 0 then
		warn("[HallwayStreamingService] no hallway spans were found")
		return false
	end

	buildGroups(spans)
	moveIgnoredAssets()
	assignMapAssets(mazeRoot)

	print(`[HallwayStreamingService] built {#Groups} logical hallways, {#Segments} physical chunks, {#Connectors} connectors`)
	return true
end

local function pointInRect(position: Vector3, rect: Rect): boolean
	if math.abs(position.Y - rect.FloorY) > 24 then return false end
	local offset = position - rect.Center
	return math.abs(offset:Dot(rect.Axis)) <= rect.HalfLength + CONNECTOR_MARGIN
		and math.abs(offset:Dot(rect.Across)) <= rect.HalfWidth + CONNECTOR_MARGIN
end

local function connectorAt(position: Vector3): Connector?
	for _, connector in Connectors do
		if pointInRect(position, connector.Rect) then return connector end
	end
	return nil
end

local function connectorDistance(position: Vector3, connector: Connector): number
	local offset = position - connector.Rect.Center
	local along = math.max(math.abs(offset:Dot(connector.Rect.Axis)) - connector.Rect.HalfLength, 0)
	local across = math.max(math.abs(offset:Dot(connector.Rect.Across)) - connector.Rect.HalfWidth, 0)
	return along + across
end

local function promoteGroup(state: PlayerState, groupId: string)
	if state.CurrentGroup == groupId then return end
	if state.CurrentGroup then
		state.Grace[state.CurrentGroup] = os.clock() + Config.HysteresisTime
	end
	state.CurrentGroup = groupId
end

local function chooseCurrentGroup(
	state: PlayerState,
	position: Vector3,
	direction: Vector3?,
	force: boolean?
)
	local preferredGroupId = if force then nil else state.CurrentGroup
	local segment = nearestSegment(position, direction, preferredGroupId)
	if not segment then return end
	promoteGroup(state, segment.GroupId)
end

local function branchWarmDistance(player: Player, state: PlayerState): number
	local ping = 0
	local ok, result = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and type(result) == "number" then
		ping = math.clamp(result, 0, Config.MaxPingLeadTime)
	end

	local speed = math.min(state.HorizontalSpeed, Config.PredictionSpeedCap)
	return Config.BranchWarmDistance + speed * (ping + Config.ReplicationLeadTime)
end

local function addWholeGroup(desired: { [Model]: boolean }, group: Group)
	for _, segment in group.Segments do desired[segment.Model] = true end
	for _, connector in group.Connectors do desired[connector.Model] = true end
end

local function addJunctionCap(desired: { [Model]: boolean }, group: Group, position: Vector3)
	local along = (position - group.Span.Start):Dot(group.Span.Axis)
	local first, last = along - Config.CapLength, along + Config.CapLength
	for _, segment in group.Segments do
		if segment.EndAlong >= first and segment.StartAlong <= last then
			desired[segment.Model] = true
		end
	end
	for _, connector in group.Connectors do
		if connectorDistance(position, connector) <= Config.CapLength then
			desired[connector.Model] = true
		end
	end
end

local function buildDesired(player: Player, state: PlayerState, position: Vector3): { [Model]: boolean }
	local desired: { [Model]: boolean } = {}
	for _, model in GlobalModels do desired[model] = true end

	local fullGroups: { [string]: boolean } = {}
	if state.CurrentGroup then fullGroups[state.CurrentGroup] = true end
	local now = os.clock()
	for groupId, expiresAt in state.Grace do
		if expiresAt > now then
			fullGroups[groupId] = true
		else
			state.Grace[groupId] = nil
		end
	end

	local warmDistance = branchWarmDistance(player, state)
	local seeds = {}
	for groupId in fullGroups do table.insert(seeds, groupId) end
	for _, groupId in seeds do
		local group = GroupsById[groupId]
		if not group then continue end

		for _, connection in group.Connections do
			if horizontal(position - connection.Position).Magnitude <= warmDistance then
				fullGroups[connection.GroupId] = true
			end
		end

		for _, connector in group.Connectors do
			if connectorDistance(position, connector) <= warmDistance then
				for otherId in ConnectorGroups[connector.Model] or {} do
					fullGroups[otherId] = true
				end
			end
		end
	end

	for groupId in fullGroups do
		local group = GroupsById[groupId]
		if group then addWholeGroup(desired, group) end
	end

	for groupId in fullGroups do
		local group = GroupsById[groupId]
		if not group then continue end
		for _, connection in group.Connections do
			if fullGroups[connection.GroupId] then continue end
			local neighbor = GroupsById[connection.GroupId]
			if neighbor then addJunctionCap(desired, neighbor, connection.Position) end
		end
	end

	return desired
end

local function refreshEnemyPlacements()
	table.clear(EnemyPlacements)
	for _, instance in CollectionService:GetTagged(ENEMY_TAG) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then continue end
		local model = instance :: Model
		local position = model:GetPivot().Position
		table.insert(EnemyPlacements, {
			Model = model,
			Connector = connectorAt(position),
			Segment = nearestSegment(position, nil, nil),
			Ignored = isIgnored(model),
		})
	end
end

local function addEnemyModels(desired: { [Model]: boolean })
	for _, placement in EnemyPlacements do
		local connector = placement.Connector
		local segment = placement.Segment
		if placement.Ignored
			or (connector ~= nil and desired[connector.Model] == true)
			or (segment ~= nil and desired[segment.Model] == true)
		then
			setPersistentMode(placement.Model)
			desired[placement.Model] = true
		end
	end
end

local function desiredChanged(first: { [Model]: boolean }, second: { [Model]: boolean }): boolean
	for model in first do
		if not second[model] then return true end
	end
	for model in second do
		if not first[model] then return true end
	end
	return false
end

local function getStreamingIds(desired: { [Model]: boolean }): { string }
	local ids = {}
	for model in desired do
		local streamingId = model:GetAttribute(Config.ModelIdAttribute)
		if type(streamingId) == "string" and model:IsDescendantOf(workspace) then
			table.insert(ids, streamingId)
		end
	end
	table.sort(ids)
	return ids
end

local function sendExpectedModels(player: Player, state: PlayerState)
	if ExpectedModelsRemote then
		ExpectedModelsRemote:FireClient(player, getStreamingIds(state.Desired))
	end
end

local function applyDesired(player: Player, state: PlayerState, desired: { [Model]: boolean })
	local changed = desiredChanged(state.Desired, desired)
	local now = os.clock()
	if changed then
		state.Desired = table.clone(desired)
	else
		local retryDue = false
		for _, retryAt in state.RetryAt do
			if retryAt <= now then
				retryDue = true
				break
			end
		end
		if not retryDue then return end
	end

	for model in state.Persistent do
		if desired[model] then
			state.RetryAt[model] = nil
			continue
		end
		if not model.Parent then
			state.Persistent[model] = nil
			state.RetryAt[model] = nil
			continue
		end
		if (state.RetryAt[model] or 0) > now then continue end

		local ok, err = pcall(function() model:RemovePersistentPlayer(player) end)
		if ok then
			state.Persistent[model] = nil
			state.RetryAt[model] = nil
		else
			state.RetryAt[model] = now + Config.PersistenceRetryInterval
			warn(`[HallwayStreamingService] Could not remove {model:GetFullName()} for {player.Name}: {err}`)
		end
	end

	for model in state.RetryAt do
		if not desired[model] and not state.Persistent[model] then state.RetryAt[model] = nil end
	end

	for model in desired do
		if state.Persistent[model] then continue end
		if (state.RetryAt[model] or 0) > now then continue end
		if not setPersistentMode(model) then
			state.RetryAt[model] = now + Config.PersistenceRetryInterval
			continue
		end

		local ok, err = pcall(function() model:AddPersistentPlayer(player) end)
		if ok then
			state.Persistent[model] = true
			state.RetryAt[model] = nil
		else
			state.RetryAt[model] = now + Config.PersistenceRetryInterval
			warn(`[HallwayStreamingService] Could not persist {model:GetFullName()} for {player.Name}: {err}`)
		end
	end

	if changed then sendExpectedModels(player, state) end
end

local function addHeldTeleportModels(state: PlayerState, desired: { [Model]: boolean })
	local held = state.TeleportDesired
	if not held then return end
	local expires = state.TeleportDesiredExpires
	if expires and expires <= os.clock() then
		state.TeleportDesired = nil
		state.TeleportDesiredExpires = nil
		return
	end
	for model in held do
		desired[model] = true
	end
end

local function updatePlayer(
	player: Player,
	position: Vector3,
	direction: Vector3?,
	horizontalSpeed: number?,
	force: boolean?
)
	local state = PlayersState[player]
	if not state then return end
	state.HorizontalSpeed = horizontalSpeed or 0
	chooseCurrentGroup(state, position, direction, force)
	local desired = buildDesired(player, state, position)
	addEnemyModels(desired)
	addHeldTeleportModels(state, desired)
	applyDesired(player, state, desired)
end

local function getModelNames(desired: { [Model]: boolean }): { string }
	local names = {}
	for model in desired do
		if model:IsDescendantOf(workspace) then table.insert(names, model.Name) end
	end
	table.sort(names)
	return names
end

local PrepareTeleportRemote = CommunicationService.Ensure("Streaming", "PrepareTeleport") :: RemoteEvent
local ClientReadyRemote = CommunicationService.Ensure("Streaming", "ClientReady") :: RemoteEvent
local TeleportFailedRemote = CommunicationService.Ensure("Streaming", "TeleportFailed") :: RemoteEvent
ExpectedModelsRemote = CommunicationService.Ensure("Streaming", "ExpectedModels") :: RemoteEvent
ReportMissingRemote = CommunicationService.Ensure("Streaming", "ReportMissing") :: RemoteEvent

ClientReadyRemote.OnServerEvent:Connect(function(player: Player, token: any, ready: any)
	local pending = PendingTeleports[player]
	if not pending or pending.Token ~= token then return end
	pending.Done:Fire(ready == true)
end)

local reportMissingRemote = ReportMissingRemote :: RemoteEvent
reportMissingRemote.OnServerEvent:Connect(function(player: Player, missing: any)
	local state = PlayersState[player]
	if not state or type(missing) ~= "table" then return end
	local now = os.clock()
	if now - state.LastMissingReport < Config.MissingReportCooldown then return end
	state.LastMissingReport = now
	if #missing == 0 then
		sendExpectedModels(player, state)
		return
	end

	local seen = {}
	for index = 1, math.min(#missing, Config.MaxMissingReport) do
		local streamingId = missing[index]
		if type(streamingId) ~= "string" or seen[streamingId] then continue end
		seen[streamingId] = true

		local model = ModelsByStreamingId[streamingId]
		if not model or not state.Desired[model] or not model:IsDescendantOf(workspace) then continue end

		local removed, removeError = pcall(function() model:RemovePersistentPlayer(player) end)
		if not removed then
			state.RetryAt[model] = now + Config.PersistenceRetryInterval
			warn(`[HallwayStreamingService] Could not reset {model:GetFullName()} for {player.Name}: {removeError}`)
			continue
		end

		state.Persistent[model] = nil
		state.RetryAt[model] = nil
		if not setPersistentMode(model) then
			state.RetryAt[model] = now + Config.PersistenceRetryInterval
			continue
		end

		local added, addError = pcall(function() model:AddPersistentPlayer(player) end)
		if added then
			state.Persistent[model] = true
		else
			state.RetryAt[model] = now + Config.PersistenceRetryInterval
			warn(`[HallwayStreamingService] Could not restore {model:GetFullName()} for {player.Name}: {addError}`)
		end
	end
	sendExpectedModels(player, state)
end)

local function waitForClient(player: Player, token: number, names: { string }): boolean
	local done = Instance.new("BindableEvent")
	PendingTeleports[player] = { Token = token, Done = done }
	PrepareTeleportRemote:FireClient(player, token, names, Config.ClientReadyTimeout)

	local result = false
	local finished = false
	local connection = done.Event:Connect(function(ready: boolean)
		result = ready
		finished = true
	end)
	local deadline = os.clock() + Config.ClientReadyTimeout
	while not finished and os.clock() < deadline do
		task.wait()
	end
	connection:Disconnect()
	done:Destroy()
	if PendingTeleports[player] and PendingTeleports[player].Token == token then
		PendingTeleports[player] = nil
	end
	return result
end

function HallwayStreamingService:PrepareTeleport(player: Player, position: Vector3): boolean
	if not Ready then ReadyEvent.Event:Wait() end
	if not Active then return true end
	local state = PlayersState[player]
	if not state then return false end

	local targetState: PlayerState = {
		Persistent = {},
		Desired = {},
		RetryAt = {},
		CurrentGroup = nil,
		Grace = {},
		HorizontalSpeed = 0,
		TeleportDesired = nil,
		TeleportDesiredExpires = nil,
		LastMissingReport = 0,
	}
	chooseCurrentGroup(targetState, position, nil, true)
	local targetDesired = buildDesired(player, targetState, position)
	local names = getModelNames(targetDesired)
	refreshEnemyPlacements()
	addEnemyModels(targetDesired)

	state.TeleportDesired = targetDesired
	state.TeleportDesiredExpires = math.huge
	local combined = table.clone(targetDesired)
	for model in state.Persistent do combined[model] = true end
	applyDesired(player, state, combined)

	TeleportToken += 1
	local token = TeleportToken

	local streamDone = false
	local streamSuccess = false
	task.spawn(function()
		streamSuccess = pcall(function()
			player:RequestStreamAroundAsync(position, Config.TeleportTimeout)
		end)
		streamDone = true
	end)

	local clientReady = waitForClient(player, token, names)
	local deadline = os.clock() + Config.TeleportTimeout
	while not streamDone and os.clock() < deadline do
		task.wait()
	end

	local success = streamDone and streamSuccess and clientReady
	if success then
		state.TeleportDesiredExpires = os.clock() + Config.HysteresisTime
	else
		state.TeleportDesired = nil
		state.TeleportDesiredExpires = nil
		TeleportFailedRemote:FireClient(player, Config.FailureMessage)
	end
	return success
end

local function removePlayer(player: Player)
	local state = PlayersState[player]
	if not state then return end
	for model in state.Persistent do
		pcall(function() model:RemovePersistentPlayer(player) end)
	end
	PlayersState[player] = nil
	PendingTeleports[player] = nil
end

local function addPlayer(player: Player)
	PlayersState[player] = {
		Persistent = {},
		Desired = {},
		RetryAt = {},
		CurrentGroup = nil,
		Grace = {},
		HorizontalSpeed = 0,
		TeleportDesired = nil,
		TeleportDesiredExpires = nil,
		LastMissingReport = 0,
	}
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				updatePlayer(
					player,
					root.Position,
					root.CFrame.LookVector,
					horizontal(root.AssemblyLinearVelocity).Magnitude,
					true
				)
			end
		end)
	end)
	if player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			updatePlayer(
				player,
				root.Position,
				root.CFrame.LookVector,
				horizontal(root.AssemblyLinearVelocity).Magnitude,
				true
			)
		end
	end
end

local function start()
	if not workspace.StreamingEnabled then
		warn("[HallwayStreamingService] Workspace.StreamingEnabled is false; custom persistence is inactive")
		Ready = true
		ReadyEvent:Fire()
		return
	end

	if not prepareMap() then
		Ready = true
		ReadyEvent:Fire()
		return
	end
	Active = true

	for _, player in Players:GetPlayers() do addPlayer(player) end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	Ready = true
	ReadyEvent:Fire()
end

RunService.Heartbeat:Connect(function(deltaTime)
	if not Active then return end
	Accumulator += deltaTime
	if Accumulator < Config.UpdateInterval then return end
	Accumulator = 0

	refreshEnemyPlacements()
	for player, _ in PlayersState do
		local root = CharacterService.GetAliveRoot(player)
		if root then
			local velocity = horizontal(root.AssemblyLinearVelocity)
			local direction = if velocity.Magnitude > 1 then velocity.Unit else root.CFrame.LookVector
			updatePlayer(player, root.Position, direction, velocity.Magnitude)
		end
	end
end)

task.defer(start)

return HallwayStreamingService
