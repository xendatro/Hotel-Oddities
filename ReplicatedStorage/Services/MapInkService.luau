local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local MapCanvas = require(ReplicatedStorage.Classes.MapCanvas)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)

local Ink = MapConfig.Ink
local PixelScale = MapConfig.Canvas.Resolution / MapConfig.Canvas.Reference
local BOUNDARY_EPSILON = 0.75
local MIN_PIECE = 2.5
local BUDGET = 0.004

local MapInkService = {}

type Wobble = {
	FirstAmplitude: number,
	FirstFrequency: number,
	FirstPhase: number,
	SecondAmplitude: number,
	SecondFrequency: number,
	SecondPhase: number,
	WidthFrequency: number,
	WidthPhase: number,
}

local Canvas: MapCanvas.MapCanvas? = nil
local Shade: MapCanvas.MapCanvas? = nil
local Label: Frame? = nil
local ShadeLabel: Frame? = nil
local Drawn: { [string]: { number } } = {}
local Wobbles: { [string]: Wobble } = {}

local function hash(text: string): number
	local value = 2166136261
	for index = 1, #text do
		value = bit32.bxor(value, string.byte(text, index))
		value = bit32.band(value * 16777619, 0xFFFFFFFF)
	end
	return value
end

local function getWobble(id: string): Wobble
	local existing = Wobbles[id]
	if existing then return existing end

	local random = Random.new(hash(id))
	local wobble: Wobble = {
		FirstAmplitude = Ink.Wobble * random:NextNumber(0.6, 1.15),
		FirstFrequency = Ink.WobbleScale * random:NextNumber(0.7, 1.4),
		FirstPhase = random:NextNumber(0, math.pi * 2),
		SecondAmplitude = Ink.Wobble * random:NextNumber(0.2, 0.5),
		SecondFrequency = Ink.WobbleScale * random:NextNumber(2.1, 3.6),
		SecondPhase = random:NextNumber(0, math.pi * 2),
		WidthFrequency = Ink.WobbleScale * random:NextNumber(1.4, 2.8),
		WidthPhase = random:NextNumber(0, math.pi * 2),
	}

	Wobbles[id] = wobble
	return wobble
end

local function offsetAt(wobble: Wobble, along: number): number
	return wobble.FirstAmplitude * math.sin(along * wobble.FirstFrequency + wobble.FirstPhase)
		+ wobble.SecondAmplitude * math.sin(along * wobble.SecondFrequency + wobble.SecondPhase)
end

type Style = {
	WidthScale: number,
	Opacity: number,
}

local NONE, OPENING, EXTENT = 0, 1, 2

local function classify(value: number, limit: number, openings: { number }): number
	if math.abs(math.abs(value) - limit) <= BOUNDARY_EPSILON then return EXTENT end
	for index = 1, #openings do
		if math.abs(value - openings[index]) <= BOUNDARY_EPSILON then return OPENING end
	end
	return NONE
end

local function strokePiece(
	id: string,
	origin: Vector2,
	direction: Vector2,
	lateral: Vector2,
	from: number,
	to: number,
	fromKind: number,
	toKind: number,
	style: Style?
)
	local canvas = Canvas
	if not canvas or to - from < MIN_PIECE then return end

	local widthScale = if style then style.WidthScale else 1
	local opacity = if style then style.Opacity else Ink.Opacity

	local wobble = getWobble(id)
	local taperFrom, taperTo = fromKind ~= NONE, toKind ~= NONE

	local start = from - (if fromKind == EXTENT then Ink.Overshoot else 0)
	local finish = to + (if toKind == EXTENT then Ink.Overshoot else 0)
	local length = finish - start
	if length <= 0 then return end

	local steps = math.max(math.ceil(length / Ink.SegmentLength), 2)
	local points = table.create(steps + 1)
	for step = 0, steps do
		local along = start + length * (step / steps)
		local world = origin + direction * along + lateral * offsetAt(wobble, along)
		points[step + 1] = MapLayoutService:ToCanvas(world.X, world.Y)
	end

	local taperLength = math.min(Ink.Overshoot * 2.5, length * 0.35)
	local function widthAt(progress: number): number
		local along = start + length * progress
		local variance = 1 + Ink.WidthVariance * 0.5 * math.sin(along * wobble.WidthFrequency + wobble.WidthPhase)
		local width = Ink.Width * PixelScale * variance * widthScale

		if taperLength > 0 then
			local fromEnd = math.huge
			if taperFrom then fromEnd = math.min(fromEnd, along - start) end
			if taperTo then fromEnd = math.min(fromEnd, finish - along) end
			if fromEnd < taperLength then
				width *= math.max(fromEnd / taperLength, 0) ^ 0.6
			end
		end

		return math.max(width, 0.4 * PixelScale)
	end

	local function bleedAt(progress: number): number
		return widthAt(progress) + Ink.BleedOffset * PixelScale
	end

	canvas:Stroke(points, bleedAt, Ink.Color, Ink.BleedOpacity * (opacity / Ink.Opacity))
	canvas:Stroke(points, widthAt, Ink.Color, opacity)
end

local function drawWall(entry: MapLayoutService.Entry, side: number, from: number, to: number, style: Style?)
	local openings = entry.Openings[side]
	local origin = entry.Center + entry.Across * (side * entry.HalfWidth)
	local id = entry.Key .. ":w" .. side

	for _, piece in MapLayoutService:Subtract(from, to, openings) do
		strokePiece(
			id,
			origin,
			entry.Axis,
			entry.Across,
			piece[1],
			piece[2],
			classify(piece[1], entry.HalfLength, openings),
			classify(piece[2], entry.HalfLength, openings),
			style
		)
	end
end

local function drawCap(entry: MapLayoutService.Entry, side: number, style: Style?)
	local openings = entry.CapOpenings[side]
	local origin = entry.Center + entry.Axis * (side * entry.HalfLength)
	local id = entry.Key .. ":c" .. side

	for _, piece in MapLayoutService:Subtract(-entry.HalfWidth, entry.HalfWidth, openings) do
		strokePiece(
			id,
			origin,
			entry.Across,
			entry.Axis,
			piece[1],
			piece[2],
			classify(piece[1], entry.HalfWidth, openings),
			classify(piece[2], entry.HalfWidth, openings),
			style
		)
	end
end

local function insideOpening(value: number, openings: { number }): boolean
	for index = 1, #openings - 1, 2 do
		if value >= openings[index] - BOUNDARY_EPSILON and value <= openings[index + 1] + BOUNDARY_EPSILON then
			return true
		end
	end
	return false
end

local function isFrontier(entry: MapLayoutService.Entry, value: number): boolean
	if math.abs(math.abs(value) - entry.HalfLength) <= BOUNDARY_EPSILON then return false end
	if insideOpening(value, entry.Openings[1]) or insideOpening(value, entry.Openings[-1]) then return false end
	return true
end

local function clearShade(entry: MapLayoutService.Entry, from: number, to: number)
	local shade = Shade
	if not shade then return end

	local settings = MapConfig.Shade
	local wobble = getWobble(entry.Key .. ":shade")
	local scale = MapLayoutService:GetScale()
	local margin = settings.Bleed + settings.SoftEdge

	local startWorld = entry.Center + entry.Axis * (from - margin)
	local finishWorld = entry.Center + entry.Axis * (to + margin)
	local head = MapLayoutService:ToCanvas(startWorld.X, startWorld.Y)
	local tail = MapLayoutService:ToCanvas(finishWorld.X, finishWorld.Y)

	local span = tail - head
	local length = span.Magnitude
	if length < 1 then return end

	local direction = span / length
	local perpendicular = Vector2.new(-direction.Y, direction.X)
	local horizontal = math.abs(perpendicular.X) > math.abs(perpendicular.Y)
	local soft = settings.SoftEdge * scale
	local steps = math.ceil(length)

	local fade = math.min(settings.FrontierFade, (to - from) * 0.35)
	local openStart = isFrontier(entry, from)
	local openFinish = isFrontier(entry, to)

	for step = 0, steps do
		local progress = step / steps
		local along = (from - margin) + (to - from + margin * 2) * progress
		local jitter = offsetAt(wobble, along) * settings.EdgeWobble
		local reach = (entry.HalfWidth + settings.Bleed + jitter) * scale
		local centre = head + direction * (length * progress)

		local residual = 0

		local toEnd = math.huge
		if openStart then toEnd = math.min(toEnd, along - from) end
		if openFinish then toEnd = math.min(toEnd, to - along) end
		if fade > 0 and toEnd < fade then
			local eased = math.clamp(toEnd / fade, 0, 1)
			residual = settings.Opacity * (1 - eased * eased * (3 - 2 * eased))
		end

		local beyond = math.max(from - along, along - to, 0) * scale
		if beyond > 0 then
			local ramp = math.clamp(beyond / soft, 0, 1)
			residual = math.max(residual, settings.Opacity * ramp * ramp * (3 - 2 * ramp))
		end

		shade:ClearSlice(
			horizontal,
			if horizontal then centre.Y else centre.X,
			if horizontal then centre.X else centre.Y,
			reach,
			reach + soft,
			residual,
			settings.Opacity
		)
	end
end

local function roomStyle(entry: MapLayoutService.Entry): Style
	return {
		WidthScale = if entry.Kind == "ComputerRoom" then Ink.ComputerWidthScale else Ink.RoomWidthScale,
		Opacity = Ink.Opacity,
	}
end

local function hatchSteps(entry: MapLayoutService.Entry): { () -> () }
	local style: Style = { WidthScale = Ink.HatchWidthScale, Opacity = Ink.HatchOpacity }
	local direction = (entry.Axis + entry.Across).Unit
	local lateral = (entry.Across - entry.Axis).Unit
	local steps = {}

	local reach = entry.HalfLength + entry.HalfWidth
	local offset = -reach
	local index = 0
	while offset <= reach do
		local low = math.max(-entry.HalfLength, -entry.HalfWidth - offset)
		local high = math.min(entry.HalfLength, entry.HalfWidth - offset)
		if high - low >= MIN_PIECE then
			local start = entry.Center + entry.Axis * low + entry.Across * (low + offset)
			local finish = entry.Center + entry.Axis * high + entry.Across * (high + offset)
			local length = (finish - start).Magnitude
			local id = entry.Key .. ":h" .. index
			table.insert(steps, function()
				strokePiece(id, start, direction, lateral, 0, length, OPENING, OPENING, style)
			end)
		end
		offset += Ink.HatchSpacing
		index += 1
	end
	return steps
end

local function roomSteps(entry: MapLayoutService.Entry): { () -> () }
	local style = roomStyle(entry)
	local steps = {}

	for _, side in { 1, -1 } do
		table.insert(steps, function()
			drawWall(entry, side, -entry.HalfLength, entry.HalfLength, style)
		end)
	end
	for _, side in { 1, -1 } do
		table.insert(steps, function()
			drawCap(entry, side, style)
		end)
	end

	if entry.Kind == "ComputerRoom" then
		for _, step in hatchSteps(entry) do
			table.insert(steps, step)
		end
	end
	return steps
end

function MapInkService:CreatePlaque(width: number, height: number, seed: string): MapCanvas.MapCanvas
	local canvas = MapCanvas.new(math.max(width, height))
	local wobble = getWobble(seed)
	local inset = Ink.Width * 2

	canvas:FillRect(
		Vector2.new(inset * 0.5, inset * 0.5),
		Vector2.new(width - inset * 0.5, height - inset * 0.5),
		MapConfig.Markers.Fill,
		0.9
	)

	local corners = {
		Vector2.new(inset, inset),
		Vector2.new(width - inset, inset),
		Vector2.new(width - inset, height - inset),
		Vector2.new(inset, height - inset),
	}

	for index = 1, 4 do
		local head = corners[index]
		local tail = corners[index % 4 + 1]
		local span = tail - head
		local length = span.Magnitude
		if length < 1 then continue end

		local direction = span / length
		local lateral = Vector2.new(-direction.Y, direction.X)
		local overshoot = Ink.Overshoot * 0.6
		local steps = math.max(math.ceil(length / 6), 2)

		local points = table.create(steps + 1)
		for step = 0, steps do
			local along = -overshoot + (length + overshoot * 2) * (step / steps)
			local drift = offsetAt(wobble, along + index * 37) * 0.5
			points[step + 1] = head + direction * along + lateral * drift
		end

		local function widthAt(progress: number): number
			local along = length * progress
			local variance = 1 + Ink.WidthVariance * 0.5 * math.sin(along * wobble.WidthFrequency + wobble.WidthPhase)
			return math.max(Ink.Width * variance * 0.85, 0.5)
		end

		canvas:Stroke(points, function(progress)
			return widthAt(progress) + Ink.BleedOffset * 0.6
		end, Ink.Color, Ink.BleedOpacity)
		canvas:Stroke(points, widthAt, Ink.Color, Ink.Opacity)
	end

	canvas:Flush()
	return canvas
end

function MapInkService:CreateArrow(resolution: number): MapCanvas.MapCanvas
	local canvas = MapCanvas.new(resolution)
	local wobble = getWobble("arrow")

	local tip = Vector2.new(resolution * 0.5, resolution * 0.07)
	local wings = {
		Vector2.new(resolution * 0.24, resolution * 0.36),
		Vector2.new(resolution * 0.76, resolution * 0.36),
	}
	local weight = resolution * MapConfig.Markers.ArrowWeight

	for index, wing in wings do
		local span = tip - wing
		local length = span.Magnitude
		local direction = span / length
		local lateral = Vector2.new(-direction.Y, direction.X)
		local steps = math.max(math.ceil(length / 6), 3)

		local points = table.create(steps + 1)
		for step = 0, steps do
			local along = length * (step / steps)
			local drift = offsetAt(wobble, along + index * 53) * 0.35
			points[step + 1] = wing + direction * along + lateral * drift
		end

		local function widthAt(progress: number): number
			return math.max(weight * (0.25 + 0.75 * progress), 0.6)
		end

		canvas:Stroke(points, function(progress)
			return widthAt(progress) + weight * 0.25
		end, Ink.Color, Ink.BleedOpacity)
		canvas:Stroke(points, widthAt, Ink.Color, Ink.Opacity)
	end

	canvas:Flush()
	return canvas
end

local function buildLayer(parent: GuiObject, canvas: MapCanvas.MapCanvas, name: string, zIndex: number): Frame
	local layer = Instance.new("Frame")
	layer.Name = name
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = zIndex
	layer.Parent = parent

	local resolution = canvas.Resolution
	for index, tile in canvas.Tiles do
		local label = Instance.new("ImageLabel")
		label.Name = "Tile" .. index
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(tile.X / resolution, tile.Y / resolution)
		label.Size = UDim2.fromScale(tile.Width / resolution, tile.Height / resolution)
		label.ScaleType = Enum.ScaleType.Stretch
		label.ImageContent = tile.Content
		label.ZIndex = zIndex
		label.Parent = layer
	end

	return layer
end

function MapInkService:Attach(paper: ImageLabel)
	self:Detach()

	local shade = MapCanvas.new(MapConfig.Canvas.Resolution)
	local canvas = MapCanvas.new(MapConfig.Canvas.Resolution)

	local base = paper.ZIndex or 1
	ShadeLabel = buildLayer(paper, shade, MapConfig.Gui.ShadeName, base + 1)
	Label = buildLayer(paper, canvas, MapConfig.Gui.InkName, base + 2)

	Canvas = canvas
	Shade = shade
	Drawn = {}
	Wobbles = {}
end

function MapInkService:PrepareShade()
	local shade = Shade
	if not shade then return end

	shade:FillAll(
		MapConfig.Shade.Color,
		MapConfig.Shade.Opacity,
		MapConfig.Shade.Grain,
		MapConfig.Shade.Feather * PixelScale,
		MapConfig.Shade.CornerRadius * PixelScale,
		BUDGET
	)
	shade:Flush()
end

function MapInkService:Detach()
	if Label then
		Label:Destroy()
		Label = nil
	end
	if ShadeLabel then
		ShadeLabel:Destroy()
		ShadeLabel = nil
	end
	if Canvas then
		Canvas:Destroy()
		Canvas = nil
	end
	if Shade then
		Shade:Destroy()
		Shade = nil
	end
	Drawn = {}
end

function MapInkService:IsAttached(): boolean
	return Canvas ~= nil
end

function MapInkService:Reveal(key: string, packed: { number }): boolean
	local canvas = Canvas
	local entry = MapLayoutService:Get(key)
	if not canvas or not entry then return false end

	if MapLayoutService:IsRoomKind(entry) then
		if Drawn[key] or #packed == 0 then return false end
		clearShade(entry, -entry.HalfLength, entry.HalfLength)
		for _, step in roomSteps(entry) do
			step()
		end
		Drawn[key] = table.clone(packed)
		return true
	end

	local drawn = Drawn[key] or {}
	local drew = false

	for index = 1, #packed - 1, 2 do
		for _, fresh in MapLayoutService:Subtract(packed[index], packed[index + 1], drawn) do
			clearShade(entry, fresh[1], fresh[2])
			drawWall(entry, 1, fresh[1], fresh[2])
			drawWall(entry, -1, fresh[1], fresh[2])
			drew = true
		end
	end

	if not drew then return false end

	for _, side in { 1, -1 } do
		local reached = false
		for index = 1, #packed - 1, 2 do
			if side > 0 then
				reached = reached or packed[index + 1] >= entry.HalfLength - BOUNDARY_EPSILON
			else
				reached = reached or packed[index] <= -entry.HalfLength + BOUNDARY_EPSILON
			end
		end
		if reached then drawCap(entry, side) end
	end

	Drawn[key] = table.clone(packed)
	return true
end

function MapInkService:RevealAnimated(key: string, packed: { number }, duration: number): boolean
	local canvas = Canvas
	local entry = MapLayoutService:Get(key)
	if not canvas or not entry or Drawn[key] or #packed == 0 then return false end
	if not MapLayoutService:IsRoomKind(entry) then return self:Reveal(key, packed) end

	Drawn[key] = table.clone(packed)
	clearShade(entry, -entry.HalfLength, entry.HalfLength)
	local steps = roomSteps(entry)

	task.spawn(function()
		local interval = duration / math.max(#steps, 1)
		for _, step in steps do
			if Canvas ~= canvas then return end
			step()
			self:Flush()
			task.wait(interval)
		end
	end)
	return true
end

function MapInkService:IsDrawn(key: string): boolean
	return Drawn[key] ~= nil
end

function MapInkService:Flush()
	if Shade then Shade:Flush() end
	if Canvas then Canvas:Flush() end
end

function MapInkService:LoadDiscovered(store: { [string]: { number } })
	local clock = os.clock()
	for key, packed in store do
		self:Reveal(key, packed)
		if os.clock() - clock > BUDGET then
			self:Flush()
			task.wait()
			clock = os.clock()
		end
	end
	self:Flush()
end

return MapInkService
