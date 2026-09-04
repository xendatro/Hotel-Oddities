local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local Gaze = require(ServerStorage.Services.GazeService)
local DeathService = require(ServerStorage.Services.DeathService)
local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)
local Oddity = require(ServerStorage.Classes.Oddity)
local HallwayRegion = require(ServerStorage.Services.HallwayRegionService)
local RoomService = require(ServerStorage.Services.RoomService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local FLOOR_TAG = "MazeFloor"
local RUNNER_NAME = "CarpetRunner"
local ODDITY_FOLDER_NAME = "Oddities"
local AXIS_ALIGNMENT = 0.95
local EPSILON = 0.05
local FLOOR_Y_EPSILON = 2
local MINIMUM_SPAN_LENGTH = 4
local MINIMUM_PIECE = 0.05
local WALL_SINK = 0.05
local COMPUTER_ROOM_CONNECTION_GAP = 1.5

type Candidate = {
	Span: HallwayRegion.Span,
	Center: Vector3,
	Axis: Vector3,
	CFrame: CFrame,
	OpeningSize: Vector3,
	FloorY: number,
	Manual: boolean?,
	RequestPosition: Vector3?,
}

type Rect = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
}

type FloorRect = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfLength: number,
	HalfWidth: number,
	FloorY: number,
}

type Cut = {
	Part: BasePart,
	Rect: Rect,
}

type PartEdit = {
	Part: BasePart,
	Parent: Instance?,
	CFrame: CFrame,
	Size: Vector3,
	Anchored: boolean,
	CanCollide: boolean,
	CanQuery: boolean,
	CanTouch: boolean,
	Transparency: number,
	Clones: { BasePart },
}

local HallwayVoid = HallwayOddity.extend("HallwayVoid", HallwayOddity)

HallwayVoid.RequiresPlayer = false

local ActiveSpans: { HallwayRegion.Span } = {}
local CachedRunners: { BasePart }?

local function setting(class: any, name: string, fallback: number): number
	local value = class.Settings and class.Settings[name]
	return if type(value) == "number" then value else fallback
end

local function colorSetting(config: { [string]: any }, name: string, fallback: Color3): Color3
	local value = config[name]
	return if typeof(value) == "Color3" then value else fallback
end

local function materialSetting(config: { [string]: any }, name: string, fallback: Enum.Material): Enum.Material
	local value = config[name]
	return if typeof(value) == "EnumItem" then value else fallback
end

local function horizontal(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
end

local function floorRect(part: BasePart): FloorRect
	local runsAlongX = part.Size.X >= part.Size.Z
	local axis = horizontal(if runsAlongX then part.CFrame.RightVector else part.CFrame.LookVector)
	return {
		Center = part.Position,
		Axis = axis,
		Across = Vector3.yAxis:Cross(axis).Unit,
		HalfLength = (if runsAlongX then part.Size.X else part.Size.Z) / 2,
		HalfWidth = (if runsAlongX then part.Size.Z else part.Size.X) / 2,
		FloorY = part.Position.Y + part.Size.Y / 2,
	}
end

local function rectanglesTouch(first: FloorRect, second: FloorRect, gap: number): boolean
	if math.abs(first.FloorY - second.FloorY) > FLOOR_Y_EPSILON then return false end

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

local function spanRect(span: HallwayRegion.Span): FloorRect?
	local hallway = Hallways.Nearest(span.Center)
	if not hallway then return nil end
	local _, boxSize = HallwayRegion.Box(span)

	return {
		Center = span.Center,
		Axis = span.Axis,
		Across = Vector3.yAxis:Cross(span.Axis).Unit,
		HalfLength = span.Length / 2,
		HalfWidth = boxSize.X / 2,
		FloorY = hallway.FloorY,
	}
end

local function hasComputerRoom(span: HallwayRegion.Span): boolean
	local hallwayRect = spanRect(span)
	if not hallwayRect then return false end

	for _, instance in CollectionService:GetTagged(MapConfig.Rooms.ComputerTag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace)
			and rectanglesTouch(hallwayRect, floorRect(instance), COMPUTER_ROOM_CONNECTION_GAP)
		then
			return true
		end
	end
	return false
end

local function getFloors(): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(FLOOR_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(floors, instance :: BasePart)
		end
	end
	return floors
end

local function getRunners(): { BasePart }
	if CachedRunners then return CachedRunners end

	local runners = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and instance.Name == RUNNER_NAME then
			table.insert(runners, instance :: BasePart)
		end
	end
	CachedRunners = runners
	return runners
end

local function isBoundaryNode(node: any, axis: Vector3): boolean
	local neighbors = {}
	for neighbor in node.Neighbors do table.insert(neighbors, neighbor) end
	if #neighbors >= 3 then return true end
	if #neighbors ~= 2 then return false end

	local firstDirection = horizontal(neighbors[1].Position - node.Position)
	local secondDirection = horizontal(neighbors[2].Position - node.Position)
	local firstAlignment = math.abs(firstDirection:Dot(axis))
	local secondAlignment = math.abs(secondDirection:Dot(axis))
	if firstAlignment < AXIS_ALIGNMENT or secondAlignment < AXIS_ALIGNMENT then return true end
	return firstDirection:Dot(axis) * secondDirection:Dot(axis) >= 0
end

local function crossingHalfDepth(position: Vector3, axis: Vector3, floorY: number, reach: number): number
	local deepest = 0
	for _, hallway in Hallways.All() do
		if math.abs(hallway.Axis:Dot(axis)) >= AXIS_ALIGNMENT then continue end
		if math.abs(hallway.FloorY - floorY) > FLOOR_Y_EPSILON then continue end

		local offset = position - hallway.Center
		if math.abs(offset:Dot(hallway.Axis)) > hallway.HalfLength + reach then continue end

		local across = math.abs(offset:Dot(hallway.Across))
		if across > hallway.HalfWidth + EPSILON then continue end
		deepest = math.max(deepest, hallway.HalfWidth + across)
	end
	return deepest
end

local function trimSpanAtJunctions(
	class: any,
	span: HallwayRegion.Span,
	position: Vector3
): HallwayRegion.Span
	local _, boxSize = HallwayRegion.Box(span)
	local source = Hallways.Nearest(span.Center)
	local floorY = if source then source.FloorY else span.Center.Y
	local reach = (if source then source.HalfWidth else boxSize.X / 2) + 1
	local across = horizontal(Vector3.yAxis:Cross(span.Axis))
	local requestedAlong = (position - span.Center):Dot(span.Axis)
	local minimum = -span.Length / 2
	local maximum = span.Length / 2
	local clearance = math.max(setting(class, "IntersectionInset", 0.5), 0)

	for _, node in HallwayGraph:Get() do
		if not isBoundaryNode(node, span.Axis) then continue end

		local offset = node.Position - span.Center
		local along = offset:Dot(span.Axis)
		local offsetAcross = math.abs(offset:Dot(across))
		if math.abs(along) > span.Length / 2 + EPSILON
			or offsetAcross > boxSize.X / 2 + EPSILON
		then
			continue
		end

		local inset = crossingHalfDepth(node.Position, span.Axis, floorY, reach) + clearance
		if along < requestedAlong - EPSILON then
			minimum = math.max(minimum, along + inset)
		elseif along > requestedAlong + EPSILON then
			maximum = math.min(maximum, along - inset)
		elseif requestedAlong >= 0 then
			maximum = math.min(maximum, along - inset)
		else
			minimum = math.max(minimum, along + inset)
		end
	end

	if maximum - minimum < MINIMUM_SPAN_LENGTH then return span end

	local start = span.Center + span.Axis * minimum
	local finish = span.Center + span.Axis * maximum
	return {
		Start = start,
		Finish = finish,
		Center = start:Lerp(finish, 0.5),
		Axis = span.Axis,
		Length = maximum - minimum,
	}
end

local function candidateFromSpan(
	class: any,
	span: HallwayRegion.Span,
	position: Vector3?
): Candidate?
	local trimmedSpan = trimSpanAtJunctions(class, span, position or span.Center)
	local hallway = Hallways.Nearest(trimmedSpan.Center)
	if not hallway then return nil end

	local padding = math.max(setting(class, "SpanPadding", 0), 0)
	local widthPadding = math.max(setting(class, "WidthPadding", 0.25), 0)
	local center = Vector3.new(trimmedSpan.Center.X, hallway.FloorY, trimmedSpan.Center.Z)
	local axis = horizontal(trimmedSpan.Axis)
	local cframe = CFrame.lookAt(center, center + axis, Vector3.yAxis)
	return {
		Span = trimmedSpan,
		Center = center,
		Axis = axis,
		CFrame = cframe,
		OpeningSize = Vector3.new(
			hallway.HalfWidth * 2 + widthPadding * 2,
			1,
			trimmedSpan.Length + padding * 2
		),
		FloorY = hallway.FloorY,
	}
end

local function buildCandidateAt(
	class: any,
	position: Vector3,
	preferredSpan: HallwayRegion.Span?
): Candidate?
	local span = preferredSpan or HallwayRegion.At(position)
	return span and candidateFromSpan(class, span, position) or nil
end

local function openingRect(part: BasePart, candidate: Candidate): Rect?
	local topY = part.Position.Y + part.Size.Y / 2
	if math.abs(topY - candidate.FloorY) > FLOOR_Y_EPSILON then return nil end

	local right = horizontal(part.CFrame.RightVector)
	local look = horizontal(part.CFrame.LookVector)
	local across = candidate.CFrame.RightVector
	local along = candidate.Axis
	local acrossOnRight = math.abs(across:Dot(right))
	local alongOnRight = math.abs(along:Dot(right))
	if math.max(acrossOnRight, alongOnRight) < AXIS_ALIGNMENT then return nil end

	local halfAcross = candidate.OpeningSize.X / 2
	local halfAlong = candidate.OpeningSize.Z / 2
	local localCenter = part.CFrame:PointToObjectSpace(candidate.Center)
	local extentX = acrossOnRight * halfAcross + alongOnRight * halfAlong
	local extentZ = math.abs(across:Dot(look)) * halfAcross + math.abs(along:Dot(look)) * halfAlong

	local halfX = part.Size.X / 2
	local halfZ = part.Size.Z / 2
	local rect: Rect = {
		MinX = localCenter.X - extentX,
		MaxX = localCenter.X + extentX,
		MinZ = localCenter.Z - extentZ,
		MaxZ = localCenter.Z + extentZ,
	}
	if rect.MinX >= halfX - EPSILON or rect.MaxX <= -halfX + EPSILON then return nil end
	if rect.MinZ >= halfZ - EPSILON or rect.MaxZ <= -halfZ + EPSILON then return nil end
	return rect
end

local function remainderPieces(part: BasePart, rect: Rect): { Rect }
	local halfX = part.Size.X / 2
	local halfZ = part.Size.Z / 2
	local pieces = {}

	if rect.MinX + halfX > MINIMUM_PIECE then
		table.insert(pieces, { MinX = -halfX, MaxX = rect.MinX, MinZ = -halfZ, MaxZ = halfZ })
	end
	if halfX - rect.MaxX > MINIMUM_PIECE then
		table.insert(pieces, { MinX = rect.MaxX, MaxX = halfX, MinZ = -halfZ, MaxZ = halfZ })
	end

	local innerMinX = math.max(rect.MinX, -halfX)
	local innerMaxX = math.min(rect.MaxX, halfX)
	if innerMaxX - innerMinX > MINIMUM_PIECE then
		if rect.MinZ + halfZ > MINIMUM_PIECE then
			table.insert(pieces, { MinX = innerMinX, MaxX = innerMaxX, MinZ = -halfZ, MaxZ = rect.MinZ })
		end
		if halfZ - rect.MaxZ > MINIMUM_PIECE then
			table.insert(pieces, { MinX = innerMinX, MaxX = innerMaxX, MinZ = rect.MaxZ, MaxZ = halfZ })
		end
	end
	return pieces
end

local function geometryFor(candidate: Candidate): { Cut }?
	local cuts = {}
	for _, floor in getFloors() do
		local rect = openingRect(floor, candidate)
		if rect then table.insert(cuts, { Part = floor, Rect = rect }) end
	end
	if #cuts == 0 then return nil end

	for _, runner in getRunners() do
		local rect = openingRect(runner, candidate)
		if rect then table.insert(cuts, { Part = runner, Rect = rect }) end
	end
	return cuts
end

local function isActive(span: HallwayRegion.Span): boolean
	for _, activeSpan in ActiveSpans do
		if HallwayRegion.Same(activeSpan, span) then return true end
	end
	return false
end

local function roomDoorPosition(room: Model): Vector3?
	local doorway = RoomService:GetDoorway(room)
	if not doorway then return nil end

	local threshold = doorway:FindFirstChild("Threshold", true)
	if threshold and threshold:IsA("BasePart") then return threshold.Position end
	return doorway:GetPivot().Position
end

local function isRoomAttached(room: Model, span: HallwayRegion.Span): boolean
	local position = roomDoorPosition(room)
	if not position then return false end

	local boxCFrame, boxSize = HallwayRegion.Box(span)
	local localPosition = boxCFrame:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= boxSize.X / 2 + EPSILON
		and math.abs(localPosition.Z) <= span.Length / 2 + EPSILON
end

local function isOccupied(span: HallwayRegion.Span): boolean
	local boxCFrame, boxSize = HallwayRegion.Box(span)
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if not root then continue end

		local localPosition = boxCFrame:PointToObjectSpace(root.Position)
		if math.abs(localPosition.X) <= boxSize.X / 2 + EPSILON
			and math.abs(localPosition.Z) <= span.Length / 2 + EPSILON
		then
			return true
		end

		if RoomService:IsInRoom(player) then
			local room = RoomService:GetRoom(player)
			if room and isRoomAttached(room, span) then return true end
		end
	end
	return false
end

local function isLookedAt(class: any, candidate: Candidate): boolean
	return Gaze.IsLookedAt(candidate.Center, {
		Cone = math.clamp(setting(class, "GazeCone", 120), 1, 360),
		MaxDistance = math.max(setting(class, "GazeDistance", 1000000), 1),
	})
end

local function isUsable(class: any, candidate: Candidate): boolean
	if isActive(candidate.Span) then return false end
	if hasComputerRoom(candidate.Span) then return false end
	if isOccupied(candidate.Span) then return false end
	if isLookedAt(class, candidate) then return false end
	return geometryFor(candidate) ~= nil
end

local function oddityFolder(): Folder
	local existing = workspace:FindFirstChild(ODDITY_FOLDER_NAME)
	if existing then return existing :: Folder end

	local folder = Instance.new("Folder")
	folder.Name = ODDITY_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function setPiece(part: BasePart, origin: CFrame, size: Vector3, piece: Rect)
	part.Size = Vector3.new(piece.MaxX - piece.MinX, size.Y, piece.MaxZ - piece.MinZ)
	part.CFrame = origin * CFrame.new((piece.MinX + piece.MaxX) / 2, 0, (piece.MinZ + piece.MaxZ) / 2)
end

local function applyCut(self: any, cut: Cut)
	local part = cut.Part
	local edit: PartEdit = {
		Part = part,
		Parent = part.Parent,
		CFrame = part.CFrame,
		Size = part.Size,
		Anchored = part.Anchored,
		CanCollide = part.CanCollide,
		CanQuery = part.CanQuery,
		CanTouch = part.CanTouch,
		Transparency = part.Transparency,
		Clones = {},
	}
	table.insert(self.Edits, edit)

	local pieces = remainderPieces(part, cut.Rect)
	if #pieces == 0 then
		part.Parent = nil
		return
	end

	for _ = 2, #pieces do
		local clone = part:Clone() :: BasePart
		if part.Name ~= RUNNER_NAME then
			clone.Name = `{part.Name}_HallwayVoidPiece`
		end
		if part:HasTag(FLOOR_TAG) then clone:AddTag(FLOOR_TAG) end
		table.insert(edit.Clones, clone)
	end

	setPiece(part, edit.CFrame, edit.Size, pieces[1])
	for index, clone in edit.Clones do
		setPiece(clone, edit.CFrame, edit.Size, pieces[index + 1])
		clone.Parent = edit.Parent
	end
end

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	material: Enum.Material,
	color: Color3,
	transparency: number,
	canCollide: boolean,
	canQuery: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanQuery = canQuery
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function HallwayVoid.new(config: { [string]: any }?)
	local self = HallwayOddity.new(config, HallwayVoid)
	self.Candidate = nil :: Candidate?
	self.Edits = {} :: { PartEdit }
	self.Structure = nil :: Model?
	self.KillConnection = nil :: RBXScriptConnection?
	return self
end

function HallwayVoid.Resolve(class: any, position: Vector3): Candidate?
	local span = HallwayOddity.Resolve(class, position)
	if not span then return nil end

	local candidate = candidateFromSpan(class, span, position)
	if candidate then
		candidate.Manual = true
		candidate.RequestPosition = position
	end
	return candidate
end

function HallwayVoid.Pick(class: any): Candidate?
	local spans = Hallways.StraightSpans()
	if #spans == 0 then return nil end

	local attempts = math.max(math.floor(setting(class, "PickAttempts", 96)), #spans)
	for _ = 1, attempts do
		local span = spans[math.random(1, #spans)]
		local candidate = candidateFromSpan(class, span, span.Center)
		if candidate and isUsable(class, candidate) then return candidate end
	end
	return nil
end

function HallwayVoid:CanStart(context: any): (boolean, string?)
	local candidate = if type(context) == "table" and context.OpeningSize
		then context :: Candidate
		else if type(context) == "table" then buildCandidateAt(self.Config, context.Center, context) else nil
	if not candidate then return false, "that position does not contain a usable hallway gap" end
	if isActive(candidate.Span) then return false, "that hallway already has a void gap" end
	if hasComputerRoom(candidate.Span) then return false, "that hallway has a computer room" end
	if not candidate.Manual and isOccupied(candidate.Span) then
		return false, "that hallway or an attached room is occupied"
	end
	if not candidate.Manual and isLookedAt(self.Config, candidate) then
		return false, "a player can see that hallway"
	end
	if not geometryFor(candidate) then return false, "the hallway floor cannot be split cleanly there" end
	return true, nil
end

function HallwayVoid:Start(context: any, duration: number?): boolean
	local candidate = if type(context) == "table" and context.OpeningSize
		then context :: Candidate
		else if type(context) == "table" then buildCandidateAt(self.Config, context.Center, context) else nil
	if not candidate then return false end

	self.Candidate = candidate
	self.Span = candidate.Span
	self.BoxCFrame, self.BoxSize = HallwayRegion.Box(candidate.Span)
	return Oddity.Start(self, candidate, duration)
end

function HallwayVoid:OnStart(): boolean
	local candidate = self.Candidate :: Candidate
	local cuts = geometryFor(candidate)
	if not cuts then return false end

	local surfaceBottom = candidate.FloorY
	for _, cut in cuts do
		surfaceBottom = math.min(surfaceBottom, cut.Part.Position.Y - cut.Part.Size.Y / 2)
	end

	for _, cut in cuts do applyCut(self, cut) end
	CachedRunners = nil
	Hallways.Invalidate()
	HallwayGraph:Invalidate()

	local structure = Instance.new("Model")
	structure.Name = `HallwayVoid_{self.Token}`
	structure.Parent = oddityFolder()
	self.Structure = structure

	local openingWidth = candidate.OpeningSize.X
	local openingLength = candidate.OpeningSize.Z
	local wallThickness = math.max(self:Setting("WallThickness", 0.8), 0.1)
	local wallDepth = math.max(self:Setting("VoidDepth", 36), 8)
	local wallColor = colorSetting(self.Config, "WallColor", Color3.fromRGB(18, 18, 18))
	local wallMaterial = materialSetting(self.Config, "WallMaterial", Enum.Material.Slate)

	local endWallOffset = openingLength / 2 + wallThickness / 2
	local sideWallOffset = openingWidth / 2 + wallThickness / 2
	local wallTop = math.min(surfaceBottom, candidate.FloorY) - WALL_SINK
	local wallCFrame = candidate.CFrame * CFrame.new(0, wallTop - candidate.FloorY - wallDepth / 2, 0)
	newPart(
		structure,
		"NearWall",
		Vector3.new(openingWidth + wallThickness * 2, wallDepth, wallThickness),
		wallCFrame * CFrame.new(0, 0, -endWallOffset),
		wallMaterial,
		wallColor,
		self:Setting("WallTransparency", 0),
		true,
		true
	)
	newPart(
		structure,
		"FarWall",
		Vector3.new(openingWidth + wallThickness * 2, wallDepth, wallThickness),
		wallCFrame * CFrame.new(0, 0, endWallOffset),
		wallMaterial,
		wallColor,
		self:Setting("WallTransparency", 0),
		true,
		true
	)
	newPart(
		structure,
		"LeftWall",
		Vector3.new(wallThickness, wallDepth, openingLength),
		wallCFrame * CFrame.new(-sideWallOffset, 0, 0),
		wallMaterial,
		wallColor,
		self:Setting("WallTransparency", 0),
		true,
		true
	)
	newPart(
		structure,
		"RightWall",
		Vector3.new(wallThickness, wallDepth, openingLength),
		wallCFrame * CFrame.new(sideWallOffset, 0, 0),
		wallMaterial,
		wallColor,
		self:Setting("WallTransparency", 0),
		true,
		true
	)

	local plankThickness = math.max(self:Setting("PlankThickness", 0.35), 0.05)
	local plankWidth = math.max(self:Setting("PlankWidth", 1.2), 0.2)
	local plankOverhang = math.max(self:Setting("PlankOverhang", 0), 0)
	local plankAngle = math.rad(self:Setting("PlankAngle", 8))
	local widthPadding = math.max(self:Setting("WidthPadding", 0.25), 0)
	local halfReach = math.max(openingLength / 2 + plankOverhang, 0.5)
	local maximumOffset = math.max(openingWidth / 2 - widthPadding - plankWidth / 2, 0)
	local endOffset = math.clamp(halfReach * math.tan(plankAngle), -maximumOffset, maximumOffset)
	plankAngle = math.atan2(endOffset, halfReach)
	local plankLength = math.max(2 * math.sqrt(halfReach ^ 2 + endOffset ^ 2), 1)
	local plankColor = colorSetting(self.Config, "PlankColor", Color3.fromRGB(111, 70, 38))
	local plankMaterial = materialSetting(self.Config, "PlankMaterial", Enum.Material.Wood)
	newPart(
		structure,
		"Plank",
		Vector3.new(plankWidth, plankThickness, plankLength),
		candidate.CFrame
			* CFrame.new(0, self:Setting("PlankLift", 0.04) + plankThickness / 2, 0)
			* CFrame.Angles(0, plankAngle, 0),
		plankMaterial,
		plankColor,
		0,
		true,
		true
	)

	local layerCount = math.max(math.floor(self:Setting("VoidLayerCount", 12)), 1)
	local layerThickness = math.max(self:Setting("VoidLayerThickness", 0.3), 0.05)
	local layerGap = math.max(self:Setting("VoidLayerGap", 2.5), 0.1)
	local layerTopOffset = math.max(self:Setting("VoidTopOffset", 3), layerThickness + 0.25)
	local layerSpacing = layerThickness + layerGap
	local edgeInset = math.max(self:Setting("VoidEdgeInset", 0), 0)
	local voidWidth = math.max(openingWidth + wallThickness * 2 - edgeInset * 2, 1)
	local voidLength = math.max(openingLength + wallThickness * 2 - edgeInset * 2, 1)
	local topTransparency = math.clamp(self:Setting("VoidTopTransparency", 0.82), 0, 0.98)
	local bottomTransparency = math.clamp(self:Setting("VoidBottomTransparency", 0.08), 0, 0.98)

	for index = 1, layerCount do
		local alpha = if layerCount == 1 then 1 else (index - 1) / (layerCount - 1)
		local transparency = topTransparency + (bottomTransparency - topTransparency) * alpha
		newPart(
			structure,
			`VoidLayer_{index}`,
			Vector3.new(voidWidth, layerThickness, voidLength),
			candidate.CFrame * CFrame.new(0, -(layerTopOffset + (index - 1) * layerSpacing), 0),
			Enum.Material.SmoothPlastic,
			Color3.new(0, 0, 0),
			transparency,
			false,
			false
		)
	end

	local killDepth = math.max(self:Setting("KillDepth", 7), 1)
	local killHalfWidth = math.max(openingWidth / 2, 0.5)
	local killHalfLength = math.max(openingLength / 2, 0.5)
	self.KillConnection = RunService.Heartbeat:Connect(function()
		if not self.Active then return end

		for _, player in Players:GetPlayers() do
			local root = CharacterService.GetAliveRoot(player)
			if not root or root.Position.Y >= candidate.FloorY - killDepth then continue end

			local localPosition = candidate.CFrame:PointToObjectSpace(root.Position)
			if math.abs(localPosition.X) > killHalfWidth or math.abs(localPosition.Z) > killHalfLength then continue end

			local humanoid = CharacterService.GetHumanoid(root.Parent :: Model)
			if humanoid and not Vanished.Is(root.Parent) then
				DeathService:RecordCause(player, "HallwayVoid")
				humanoid.Health = 0
			end
		end
	end)

	table.insert(ActiveSpans, candidate.Span)
	return true
end

function HallwayVoid:OnStop()
	if self.KillConnection then
		self.KillConnection:Disconnect()
		self.KillConnection = nil
	end

	if self.Structure then
		self.Structure:Destroy()
		self.Structure = nil
	end

	for index = #self.Edits, 1, -1 do
		local edit = self.Edits[index]
		for _, clone in edit.Clones do clone:Destroy() end
		edit.Part.Parent = edit.Parent
		edit.Part.CFrame = edit.CFrame
		edit.Part.Size = edit.Size
		edit.Part.Anchored = edit.Anchored
		edit.Part.CanCollide = edit.CanCollide
		edit.Part.CanQuery = edit.CanQuery
		edit.Part.CanTouch = edit.CanTouch
		edit.Part.Transparency = edit.Transparency
	end
	table.clear(self.Edits)

	local span = self.Span
	if span then
		local index = table.find(ActiveSpans, span)
		if index then table.remove(ActiveSpans, index) end
	end

	Hallways.Invalidate()
	HallwayGraph:Invalidate()
	self.Candidate = nil
	CachedRunners = nil
end

return HallwayVoid
