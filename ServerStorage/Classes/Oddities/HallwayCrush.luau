local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local DeathService = require(ServerStorage.Services.DeathService)
local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)
local HallwayRegion = require(ServerStorage.Services.HallwayRegionService)
local HallwayWall = require(ServerStorage.Services.HallwayWallService)
local EnemyService = require(ServerStorage.Services.EnemyService)
local Oddity = require(ServerStorage.Classes.Oddity)

local ODDITY_FOLDER_NAME = "Oddities"
local MINIMUM_PIECE = 0.35
local MINIMUM_SPAN_LENGTH = 18
local FIXTURE_MARGIN = 1.5
local CROSS_FIXTURE_SPAN = 8
local FLAT_FIXTURE_SPAN = 3
local JAMB_THICKNESS = 0.25
local TEXTURE_SIGN = -1
local DOORWAY_GAP = 8
local SEAM_OVERLAP = 0.06
local SEAL_LIFT = 0.02
local ALCOVE_MARGIN = 0.5
local LAYER_NUDGE = {
	Baseboard = { Length = 1, Height = 0.030, Across = 0 },
	ChairRail = { Length = 0.83, Height = 0.042, Across = 0 },
	Crown = { Length = 0.67, Height = 0.012, Across = 0 },
	Wainscot = { Length = 0.42, Height = 0.018, Across = 0.012 },
	Wallpaper = { Length = 0.25, Height = 0, Across = 0 },
}
local HEADER_LIFT = 0.024
local HEADER_RECESS = 0.006
local FAR_SIDE_OVERSHOOT = 0.6

local MapCrush = CommunicationService.Ensure("Oddities", "MapCrush")

local Running: { [number]: any } = {}

type Candidate = {
	Span: HallwayRegion.Span,
	Frame: HallwayWall.Frame,
	Manual: boolean?,
}

type WallEdit = {
	Part: BasePart,
	Parent: Instance?,
	CFrame: CFrame,
	Size: Vector3,
	Clones: { BasePart },
	Textures: { { Texture: Texture, Offset: number } },
}

type Mover = {
	Part: BasePart,
	Sign: number,
	CFrame: CFrame,
	Size: Vector3,
	ThicknessAxis: Vector3,
}

type Shifter = {
	Model: Model,
	Sign: number,
	Pivot: CFrame,
}

type Shrinker = {
	Part: BasePart,
	Size: Vector3,
	Axis: Vector3,
}

type Alcove = {
	Along: number,
	HalfWidth: number,
	Sign: number,
	Inner: number,
	Outer: number,
	Top: number,
}

type Header = {
	Part: BasePart,
	Sign: number,
	CFrame: CFrame,
	Size: Vector3,
	ThicknessAxis: Vector3,
	LengthAxis: Vector3,
}

type Reveal = {
	Origin: CFrame,
	Width: number,
	Height: number,
	Left: BasePart,
	Right: BasePart,
	Soffit: BasePart,
}

local HallwayCrush = HallwayOddity.extend("HallwayCrush", HallwayOddity)

HallwayCrush.RequiresPlayer = false

local ActiveSpans: { HallwayRegion.Span } = {}

local function setting(class: any, name: string, fallback: number): number
	local value = class.Settings and class.Settings[name]
	return if type(value) == "number" then value else fallback
end

local function isActive(span: HallwayRegion.Span): boolean
	for _, activeSpan in ActiveSpans do
		if HallwayRegion.Same(activeSpan, span) then return true end
	end
	return false
end

local function extentAlong(model: Model, direction: Vector3): number
	local cframe, size = model:GetBoundingBox()
	return math.abs(cframe.RightVector:Dot(direction)) * size.X
		+ math.abs(cframe.UpVector:Dot(direction)) * size.Y
		+ math.abs(cframe.LookVector:Dot(direction)) * size.Z
end

local function isSettled(instance: Instance): boolean
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then return false end
	end
	return not (instance:IsA("BasePart") and not (instance :: BasePart).Anchored)
end

local function candidateFromSpan(class: any, span: HallwayRegion.Span?, position: Vector3?): Candidate?
	if not span then return nil end

	local frame = HallwayWall.Frame(span)
	if not frame then return nil end

	frame = HallwayWall.Limit(frame, position or span.Center, setting(class, "MaxLength", 130))
	if HallwayWall.Length(frame) < MINIMUM_SPAN_LENGTH then return nil end
	return { Span = span, Frame = frame }
end

local function inIntervals(intervals: { HallwayWall.Interval }, along: number): boolean
	for _, interval in intervals do
		if along >= interval.Minimum and along <= interval.Maximum then return true end
	end
	return false
end

local function pieceIntervals(
	wall: HallwayWall.Wall,
	frame: HallwayWall.Frame,
	cuts: { number },
	closing: { HallwayWall.Interval }
): { { Minimum: number, Maximum: number, Moving: boolean } }
	local boundaries = { wall.Minimum, wall.Maximum }
	for _, cut in cuts do
		if cut > wall.Minimum + MINIMUM_PIECE and cut < wall.Maximum - MINIMUM_PIECE then
			table.insert(boundaries, cut)
		end
	end
	table.sort(boundaries)

	local pieces = {}
	for index = 1, #boundaries - 1 do
		local minimum = boundaries[index]
		local maximum = boundaries[index + 1]
		if maximum - minimum < MINIMUM_PIECE then continue end

		local middle = (minimum + maximum) / 2
		table.insert(pieces, {
			Minimum = minimum,
			Maximum = maximum,
			Moving = middle > frame.Minimum
				and middle < frame.Maximum
				and inIntervals(closing, middle),
		})
	end
	return pieces
end

local function setPiece(
	part: BasePart,
	edit: WallEdit,
	wall: HallwayWall.Wall,
	frame: HallwayWall.Frame,
	piece: { Minimum: number, Maximum: number, Moving: boolean },
	previous: { Moving: boolean }?,
	following: { Moving: boolean }?,
	trimOvershoot: number
)
	local layer = part:GetAttribute("WallLayer")
	local nudge = if piece.Moving and type(layer) == "string" then LAYER_NUDGE[layer] else nil
	local sideScale = if wall.Sign > 0 then 1 else FAR_SIDE_OVERSHOOT
	local overshoot = if nudge then nudge.Length * trimOvershoot * sideScale else 0

	local minimum = piece.Minimum
	local maximum = piece.Maximum
	if previous and previous.Moving == piece.Moving then
		minimum -= SEAM_OVERLAP
	else
		minimum -= overshoot
	end
	if following and following.Moving == piece.Moving then
		maximum += SEAM_OVERLAP
	else
		maximum += overshoot
	end

	local length = maximum - minimum
	local baseLength = wall.Maximum - wall.Minimum
	local shift = (minimum + maximum) / 2 - (wall.Minimum + wall.Maximum) / 2
	local lift = if piece.Moving and wall.Sign > 0 then SEAL_LIFT else 0
	local proud = 0
	if nudge then
		lift += nudge.Height
		proud = nudge.Across
	end

	part.Size = edit.Size
		+ wall.LengthAxis * (length - baseLength)
		+ Vector3.yAxis * lift
		+ wall.ThicknessAxis * proud
	part.CFrame = edit.CFrame + frame.Axis * shift

	local offset = shift * wall.LengthSign * TEXTURE_SIGN
	for _, texture in part:GetChildren() do
		if texture:IsA("Texture") then
			texture.OffsetStudsU += offset
		end
	end
end

local function oddityFolder(): Folder
	local existing = workspace:FindFirstChild(ODDITY_FOLDER_NAME)
	if existing then return existing :: Folder end

	local folder = Instance.new("Folder")
	folder.Name = ODDITY_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function newSlab(parent: Instance, name: string, template: BasePart): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = template.Color
	part.Material = template.Material
	part.Size = Vector3.one
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Parent = parent
	return part
end

function HallwayCrush.new(config: { [string]: any }?)
	local self = HallwayOddity.new(config, HallwayCrush)
	self.Candidate = nil :: Candidate?
	self.Edits = {} :: { WallEdit }
	self.Movers = {} :: { Mover }
	self.Coverage = { {}, {} } :: { { HallwayWall.Interval } }
	self.Closing = {} :: { HallwayWall.Interval }
	self.Headers = {} :: { Header }
	self.Lethal = {} :: { HallwayWall.Interval }
	self.Alcoves = {} :: { Alcove }
	self.SealedAt = nil :: number?
	self.Shifters = {} :: { Shifter }
	self.Shrinkers = {} :: { Shrinker }
	self.Reveals = {} :: { Reveal }
	self.Structure = nil :: Model?
	self.StepConnection = nil :: RBXScriptConnection?
	self.ClearHalfWidth = 0
	self.MaximumOffset = 0
	self.Offset = 0
	self.Killed = {} :: { [Player]: true }
	return self
end

function HallwayCrush.Resolve(class: any, position: Vector3): Candidate?
	local candidate = candidateFromSpan(class, HallwayOddity.Resolve(class, position), position)
	if candidate then candidate.Manual = true end
	return candidate
end

function HallwayCrush.Pick(class: any): Candidate?
	local spans = Hallways.StraightSpans()
	if #spans == 0 then return nil end

	local attempts = math.max(math.floor(setting(class, "PickAttempts", 64)), 1)
	local occupiedChance = setting(class, "OccupiedChance", 0.4)
	for _ = 1, attempts do
		local span = if math.random() <= occupiedChance
			then HallwayRegion.RandomOccupied() or spans[math.random(1, #spans)]
			else spans[math.random(1, #spans)]
		local candidate = candidateFromSpan(class, span)
		if candidate and not isActive(candidate.Span) then return candidate end
	end
	return nil
end

function HallwayCrush:_collectWalls(frame: HallwayWall.Frame)
	local cuts = HallwayWall.CutPoints(frame)
	local trimOvershoot = math.max(self:Setting("TrimOvershoot", 0.12), 0)
	self.Closing = HallwayWall.Closing(frame)
	for _, wall in HallwayWall.Walls(frame) do
		local pieces = pieceIntervals(wall, frame, cuts, self.Closing)
		if #pieces == 0 then continue end

		local part = wall.Part
		local edit: WallEdit = {
			Part = part,
			Parent = part.Parent,
			CFrame = part.CFrame,
			Size = part.Size,
			Clones = {},
			Textures = {},
		}
		for _, child in part:GetChildren() do
			if child:IsA("Texture") then
				table.insert(edit.Textures, { Texture = child, Offset = child.OffsetStudsU })
			end
		end
		table.insert(self.Edits, edit)

		for index, piece in pieces do
			local target = part
			if index > 1 then
				target = part:Clone()
				target.Name = `{part.Name}_HallwayCrushPiece`
				table.insert(edit.Clones, target)
			end

			setPiece(
				target,
				edit,
				wall,
				frame,
				piece,
				pieces[index - 1],
				pieces[index + 1],
				trimOvershoot
			)
			if index > 1 then target.Parent = edit.Parent end
			if not piece.Moving then continue end

			table.insert(self.Movers, {
				Part = target,
				Sign = wall.Sign,
				CFrame = target.CFrame,
				Size = target.Size,
				ThicknessAxis = wall.ThicknessAxis,
			})
			local side = if wall.Sign > 0 then self.Coverage[1] else self.Coverage[2]
			table.insert(side, { Minimum = piece.Minimum, Maximum = piece.Maximum })
			self.ClearHalfWidth = math.min(
				self.ClearHalfWidth,
				math.abs(wall.Offset) - wall.Thickness / 2
			)
		end
	end
end

function HallwayCrush:_collectStations(frame: HallwayWall.Frame)
	for _, instance in HallwayWall.Fixtures(frame, "HallwayStation", FIXTURE_MARGIN) do
		local station = instance :: Model
		if extentAlong(station, frame.Across) < CROSS_FIXTURE_SPAN then continue end

		for _, child in station:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(self.Shrinkers, {
					Part = child,
					Size = child.Size,
					Axis = if math.abs(child.CFrame.RightVector:Dot(frame.Across)) >= 0.95
						then Vector3.xAxis
						else Vector3.zAxis,
				})
			elseif child:IsA("Model") and isSettled(child) then
				local pivot = child:GetPivot()
				local across = (pivot.Position - frame.Center):Dot(frame.Across)
				if math.abs(across) < 1 then continue end
				table.insert(self.Shifters, {
					Model = child,
					Sign = if across >= 0 then 1 else -1,
					Pivot = pivot,
				})
			end
		end
	end
end

function HallwayCrush:_collectFlat(frame: HallwayWall.Frame, tag: string)
	for _, instance in HallwayWall.Fixtures(frame, tag, FIXTURE_MARGIN) do
		local model = instance :: Model
		if not model:IsA("Model") then continue end
		if extentAlong(model, frame.Across) > FLAT_FIXTURE_SPAN then continue end
		if not isSettled(model) then continue end

		local pivot = model:GetPivot()
		local across = (pivot.Position - frame.Center):Dot(frame.Across)
		if math.abs(across) < 1 then continue end
		table.insert(self.Shifters, {
			Model = model,
			Sign = if across >= 0 then 1 else -1,
			Pivot = pivot,
		})
	end
end

function HallwayCrush:_collectReveals(frame: HallwayWall.Frame, structure: Model)
	for _, instance in HallwayWall.Fixtures(frame, "Doorway", FIXTURE_MARGIN) do
		local doorway = instance :: Model
		if not doorway:IsA("Model") then continue end
		if extentAlong(doorway, frame.Across) > FLAT_FIXTURE_SPAN then continue end

		local header = doorway:FindFirstChild("DoorHeader")
		if not header or not header:IsA("BasePart") then continue end

		local offset = header.Position - frame.Center
		local across = offset:Dot(frame.Across)
		if math.abs(across) < 1 then continue end

		local sign = if across >= 0 then 1 else -1
		local headerRight = header.CFrame.RightVector
		local headerLook = header.CFrame.LookVector
		if math.abs(headerRight:Dot(frame.Axis)) >= 0.95 then
			table.insert(self.Headers, {
				Part = header,
				Sign = sign,
				CFrame = header.CFrame,
				Size = header.Size,
				ThicknessAxis = Vector3.zAxis,
				LengthAxis = Vector3.xAxis,
			})
		elseif math.abs(headerLook:Dot(frame.Axis)) >= 0.95 then
			table.insert(self.Headers, {
				Part = header,
				Sign = sign,
				CFrame = header.CFrame,
				Size = header.Size,
				ThicknessAxis = Vector3.xAxis,
				LengthAxis = Vector3.zAxis,
			})
		end

		local outward = math.abs(across) + extentAlong(doorway, frame.Across) / 2
		local width = extentAlong(doorway, frame.Axis)
		local top = header.Position.Y - header.Size.Y / 2
		local height = top - frame.FloorY
		if width <= 0 or height <= 0 then continue end

		table.insert(self.Alcoves, {
			Along = offset:Dot(frame.Axis),
			HalfWidth = width / 2,
			Sign = sign,
			Inner = math.abs(across) - extentAlong(doorway, frame.Across) / 2,
			Outer = outward,
			Top = top,
		})

		local base = frame.Center + frame.Axis * offset:Dot(frame.Axis) + frame.Across * (sign * outward)
		local middle = Vector3.new(base.X, frame.FloorY + height / 2, base.Z)
		table.insert(self.Reveals, {
			Origin = CFrame.lookAt(middle, middle + frame.Across * sign, Vector3.yAxis),
			Width = width,
			Height = height,
			Left = newSlab(structure, "RevealLeft", header),
			Right = newSlab(structure, "RevealRight", header),
			Soffit = newSlab(structure, "RevealSoffit", header),
		})
	end
end

function HallwayCrush:_apply(offset: number)
	self.Offset = offset
	local frame = (self.Candidate :: Candidate).Frame

	for _, mover in self.Movers do
		mover.Part.Size = mover.Size + mover.ThicknessAxis * offset
		mover.Part.CFrame = mover.CFrame + frame.Across * (-mover.Sign * offset / 2)
	end

	for _, shifter in self.Shifters do
		shifter.Model:PivotTo(shifter.Pivot + frame.Across * (-shifter.Sign * offset))
	end

	for _, header in self.Headers do
		local thickness = math.max(offset - HEADER_RECESS, 0)
		header.Part.Size = header.Size
			+ header.ThicknessAxis * thickness
			+ header.LengthAxis * (SEAM_OVERLAP * 2)
			+ Vector3.yAxis * HEADER_LIFT
		header.Part.CFrame = header.CFrame + frame.Across * (-header.Sign * thickness / 2)
	end

	for _, shrinker in self.Shrinkers do
		local base = shrinker.Size:Dot(shrinker.Axis)
		local width = math.max(base - offset * 2, 0.05)
		shrinker.Part.Size = shrinker.Size + shrinker.Axis * (width - base)
	end

	local depth = math.max(offset, 0.01)
	local transparency = if offset > 0.05 then 0 else 1
	for _, reveal in self.Reveals do
		local half = reveal.Width / 2 + JAMB_THICKNESS / 2
		reveal.Left.Size = Vector3.new(JAMB_THICKNESS, reveal.Height, depth)
		reveal.Left.CFrame = reveal.Origin * CFrame.new(-half, 0, depth / 2)
		reveal.Right.Size = Vector3.new(JAMB_THICKNESS, reveal.Height, depth)
		reveal.Right.CFrame = reveal.Origin * CFrame.new(half, 0, depth / 2)
		reveal.Soffit.Size = Vector3.new(reveal.Width + JAMB_THICKNESS * 2, JAMB_THICKNESS, depth)
		reveal.Soffit.CFrame = reveal.Origin
			* CFrame.new(0, (reveal.Height + JAMB_THICKNESS) / 2, depth / 2)
		reveal.Left.Transparency = transparency
		reveal.Right.Transparency = transparency
		reveal.Soffit.Transparency = transparency
	end
end

function HallwayCrush:_buildLethal()
	local positive = HallwayWall.Merge(self.Coverage[1], DOORWAY_GAP)
	local negative = HallwayWall.Merge(self.Coverage[2], DOORWAY_GAP)
	local both = HallwayWall.Merge(HallwayWall.Intersect(positive, negative), 0)
	self.Lethal = HallwayWall.Inset(both, math.max(self:Setting("SafeMargin", 2), 0))
end

function HallwayCrush:_clearWidth(): number
	return (self.ClearHalfWidth - self.Offset) * 2
end

function HallwayCrush:_inAlcove(position: Vector3): boolean
	local frame = (self.Candidate :: Candidate).Frame
	local offset = position - frame.Center
	local along = offset:Dot(frame.Axis)
	local across = offset:Dot(frame.Across)

	local alongMargin = math.max(self:Setting("DoorwayMargin", 2), 0)
	for _, alcove in self.Alcoves do
		if math.abs(along - alcove.Along) > alcove.HalfWidth + alongMargin then continue end
		if position.Y > alcove.Top or position.Y < frame.FloorY - ALCOVE_MARGIN then continue end

		local depth = across * alcove.Sign
		local inner = math.max(alcove.Inner - self.Offset, 0)
		if depth >= inner and depth <= alcove.Outer + ALCOVE_MARGIN then
			return true
		end
	end
	return false
end

function HallwayCrush:_isCaught(position: Vector3, slack: number): boolean
	local frame = (self.Candidate :: Candidate).Frame
	if not HallwayWall.Contains(frame, position) then return false end
	if self:_inAlcove(position) then return false end

	local along = (position - frame.Center):Dot(frame.Axis)
	for _, interval in self.Lethal do
		if along >= interval.Minimum - slack and along <= interval.Maximum + slack then return true end
	end
	return false
end

function HallwayCrush:_crushEnemies()
	EnemyService:ForEachActive(function(enemy: any)
		if not enemy.Active then return end

		local model = enemy.Model
		if not model or not model.Parent then return end
		if not self:_isCaught(model:GetPivot().Position, 0) then return end
		enemy:Despawn()
	end)
end

function HallwayCrush:Crush(player: Player, slack: number): boolean
	if not self.Active or self.Killed[player] then return false end

	local tolerance = math.max(self:Setting("KillTolerance", 0.75), 0)
	if self:_clearWidth() > math.max(self:Setting("KillWidth", 2.2), 0) + tolerance then return false end

	local root = CharacterService.GetAliveRoot(player)
	if not root or not self:_isCaught(root.Position, slack) then return false end

	local humanoid = CharacterService.GetHumanoid(root.Parent :: Model)
	if not humanoid or humanoid.Health <= 0 then return false end

	self.Killed[player] = true
	DeathService:RecordCause(player, "HallwayCrush")
	humanoid.Health = 0
	return true
end

function HallwayCrush:_backstop()
	if self:_clearWidth() > math.max(self:Setting("KillWidth", 2.2), 0) then
		self.SealedAt = nil
		return
	end

	if not self.SealedAt then self:_crushEnemies() end
	self.SealedAt = self.SealedAt or os.clock()
	if os.clock() - self.SealedAt < math.max(self:Setting("BackstopDelay", 1.5), 0) then return end

	for _, player in Players:GetPlayers() do
		self:Crush(player, 0)
	end
end

function HallwayCrush:_broadcast()
	local frame = (self.Candidate :: Candidate).Frame
	MapCrush:FireAllClients("Start", self.Token, {
		Center = frame.Center,
		Axis = frame.Axis,
		Across = frame.Across,
		HalfWidth = frame.HalfWidth,
		FloorY = frame.FloorY,
		HeightWindow = HallwayWall.HeightWindow,
		BelowWindow = HallwayWall.BelowWindow,
		Lethal = self.Lethal,
		Alcoves = self.Alcoves,
		AlcoveMargin = ALCOVE_MARGIN,
		AlongMargin = math.max(self:Setting("DoorwayMargin", 2), 0),
		ClearHalfWidth = self.ClearHalfWidth,
		KillWidth = math.max(self:Setting("KillWidth", 2.2), 0),
		MaximumOffset = self.MaximumOffset,
		CloseTime = math.max(self:Setting("CloseTime", 9), 0.1),
		StartedAt = workspace:GetServerTimeNow(),
	})
end

MapCrush.OnServerEvent:Connect(function(player: Player, action: any, token: any)
	if action ~= "Crushed" or type(token) ~= "number" then return end

	local oddity = Running[token]
	if not oddity then return end
	oddity:Crush(player, math.max(oddity:Setting("SafeMargin", 2), 0))
end)

function HallwayCrush:CanStart(context: any): (boolean, string?)
	local candidate = if type(context) == "table" and context.Frame then context :: Candidate else nil
	if not candidate then return false, "that position is not in a hallway that can close" end
	if isActive(candidate.Span) then return false, "that hallway is already closing" end
	if #HallwayWall.Walls(candidate.Frame) == 0 then
		return false, "that hallway has no walls that can be moved"
	end
	return true, nil
end

function HallwayCrush:Start(context: any, duration: number?): boolean
	local candidate = if type(context) == "table" and context.Frame then context :: Candidate else nil
	if not candidate then return false end

	self.Candidate = candidate
	self.Span = candidate.Span
	self.BoxCFrame, self.BoxSize = HallwayRegion.Box(candidate.Span)
	return Oddity.Start(self, candidate, duration)
end

function HallwayCrush:OnStart(): boolean
	local candidate = self.Candidate :: Candidate
	local frame = candidate.Frame

	local structure = Instance.new("Model")
	structure.Name = `HallwayCrush_{self.Token}`
	structure.Parent = oddityFolder()
	self.Structure = structure

	self.ClearHalfWidth = math.huge
	self:_collectWalls(frame)
	if #self.Movers == 0 then
		self:_restore()
		return false
	end

	self:_collectStations(frame)
	self:_collectFlat(frame, "PictureFrame")
	self:_collectFlat(frame, "Doorway")
	self:_collectReveals(frame, structure)
	self:_apply(0)

	self.MaximumOffset = math.max(self.ClearHalfWidth + math.max(self:Setting("SealOverlap", 0.3), 0), 0)
	self:_buildLethal()
	table.insert(ActiveSpans, candidate.Span)
	Running[self.Token] = self
	self:_broadcast()

	local closeTime = math.max(self:Setting("CloseTime", 9), 0.1)
	local stepInterval = math.max(self:Setting("StepInterval", 1 / 30), 0)
	local elapsed = 0
	local sinceStep = math.huge

	self.StepConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if not self.Active then return end

		elapsed = math.min(elapsed + deltaTime, closeTime)
		sinceStep += deltaTime
		if sinceStep < stepInterval and elapsed < closeTime then return end
		sinceStep = 0

		local alpha = elapsed / closeTime
		self:_apply(self.MaximumOffset * alpha * alpha * (3 - 2 * alpha))
		self:_backstop()
	end)
	return true
end

function HallwayCrush:_restore()
	for index = #self.Edits, 1, -1 do
		local edit = self.Edits[index]
		for _, clone in edit.Clones do clone:Destroy() end
		edit.Part.CFrame = edit.CFrame
		edit.Part.Size = edit.Size
		for _, entry in edit.Textures do
			entry.Texture.OffsetStudsU = entry.Offset
		end
	end
	table.clear(self.Edits)
	table.clear(self.Movers)
	table.clear(self.Closing)
	table.clear(self.Lethal)
	table.clear(self.Alcoves)
	table.clear(self.Coverage[1])
	table.clear(self.Coverage[2])

	for _, shifter in self.Shifters do
		if shifter.Model.Parent then shifter.Model:PivotTo(shifter.Pivot) end
	end
	table.clear(self.Shifters)

	for _, header in self.Headers do
		if header.Part.Parent then
			header.Part.Size = header.Size
			header.Part.CFrame = header.CFrame
		end
	end
	table.clear(self.Headers)

	for _, shrinker in self.Shrinkers do
		if shrinker.Part.Parent then shrinker.Part.Size = shrinker.Size end
	end
	table.clear(self.Shrinkers)
	table.clear(self.Reveals)

	if self.Structure then
		self.Structure:Destroy()
		self.Structure = nil
	end

	local span = self.Span
	if span then
		local index = table.find(ActiveSpans, span)
		if index then table.remove(ActiveSpans, index) end
	end
	self.Candidate = nil
end

function HallwayCrush:OnStop()
	if self.StepConnection then
		self.StepConnection:Disconnect()
		self.StepConnection = nil
	end
	if Running[self.Token] then
		Running[self.Token] = nil
		MapCrush:FireAllClients("Stop", self.Token)
	end
	if not self.Candidate then return end

	local openTime = math.max(self:Setting("OpenTime", 4), 0)
	local start = self.Offset
	task.spawn(function()
		local elapsed = 0
		while elapsed < openTime and self.Candidate do
			elapsed = math.min(elapsed + RunService.Heartbeat:Wait(), openTime)
			self:_apply(start * (1 - elapsed / openTime))
		end
		self:_restore()
	end)
end

return HallwayCrush
