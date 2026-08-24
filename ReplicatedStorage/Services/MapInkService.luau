local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local MapCanvas = require(ReplicatedStorage.Classes.MapCanvas)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)

local Ink = MapConfig.Ink
local BOUNDARY_EPSILON = 0.75
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
local Label: ImageLabel? = nil
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

local function isBoundary(value: number, limit: number, openings: { number }): boolean
	if math.abs(math.abs(value) - limit) <= BOUNDARY_EPSILON then return true end
	for index = 1, #openings do
		if math.abs(value - openings[index]) <= BOUNDARY_EPSILON then return true end
	end
	return false
end

local function strokePiece(
	id: string,
	origin: Vector2,
	direction: Vector2,
	lateral: Vector2,
	from: number,
	to: number,
	taperFrom: boolean,
	taperTo: boolean
)
	local canvas = Canvas
	if not canvas then return end

	local wobble = getWobble(id)

	local start = from - (if taperFrom then Ink.Overshoot else 0)
	local finish = to + (if taperTo then Ink.Overshoot else 0)
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
		local width = Ink.Width * variance

		if taperLength > 0 then
			local fromEnd = math.huge
			if taperFrom then fromEnd = math.min(fromEnd, along - start) end
			if taperTo then fromEnd = math.min(fromEnd, finish - along) end
			if fromEnd < taperLength then
				width *= math.max(fromEnd / taperLength, 0) ^ 0.6
			end
		end

		return math.max(width, 0.4)
	end

	local function bleedAt(progress: number): number
		return widthAt(progress) + Ink.BleedOffset
	end

	canvas:Stroke(points, bleedAt, Ink.Color, Ink.BleedOpacity)
	canvas:Stroke(points, widthAt, Ink.Color, Ink.Opacity)
end

local function drawWall(entry: MapLayoutService.Entry, side: number, from: number, to: number)
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
			isBoundary(piece[1], entry.HalfLength, openings),
			isBoundary(piece[2], entry.HalfLength, openings)
		)
	end
end

local function drawCap(entry: MapLayoutService.Entry, side: number)
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
			isBoundary(piece[1], entry.HalfWidth, openings),
			isBoundary(piece[2], entry.HalfWidth, openings)
		)
	end
end

function MapInkService:Attach(paper: ImageLabel)
	self:Detach()

	local canvas = MapCanvas.new(MapConfig.Canvas.Resolution)
	local label = Instance.new("ImageLabel")
	label.Name = MapConfig.Gui.InkName
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ScaleType = Enum.ScaleType.Stretch
	label.ImageContent = Content.fromObject(canvas.Image)
	label.ZIndex = (paper.ZIndex or 1) + 1
	label.Parent = paper

	Canvas = canvas
	Label = label
	Drawn = {}
	Wobbles = {}
end

function MapInkService:Detach()
	if Label then
		Label:Destroy()
		Label = nil
	end
	if Canvas then
		Canvas:Destroy()
		Canvas = nil
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

	local drawn = Drawn[key] or {}
	local drew = false

	for index = 1, #packed - 1, 2 do
		for _, fresh in MapLayoutService:Subtract(packed[index], packed[index + 1], drawn) do
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

function MapInkService:Flush()
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
