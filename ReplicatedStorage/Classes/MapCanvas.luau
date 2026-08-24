local AssetService = game:GetService("AssetService")

local MapCanvas = {}
MapCanvas.__index = MapCanvas

export type MapCanvas = typeof(setmetatable({} :: {
	Resolution: number,
	Image: EditableImage,
	_pixels: buffer,
	_minX: number,
	_minY: number,
	_maxX: number,
	_maxY: number,
}, MapCanvas))

function MapCanvas.new(resolution: number): MapCanvas
	local self = setmetatable({}, MapCanvas)

	self.Resolution = resolution
	self.Image = AssetService:CreateEditableImage({ Size = Vector2.new(resolution, resolution) })
	self._pixels = buffer.create(resolution * resolution * 4)
	self:ResetDirty()

	return self
end

function MapCanvas:ResetDirty()
	self._minX, self._minY = math.huge, math.huge
	self._maxX, self._maxY = -math.huge, -math.huge
end

function MapCanvas:Clear()
	buffer.fill(self._pixels, 0, 0)
	self._minX, self._minY = 0, 0
	self._maxX, self._maxY = self.Resolution - 1, self.Resolution - 1
	self:Flush()
end

function MapCanvas:Stamp(x: number, y: number, radius: number, color: Color3, alpha: number)
	if alpha <= 0 or radius <= 0 then return end

	local resolution = self.Resolution
	local pixels = self._pixels

	local left = math.max(math.floor(x - radius - 1), 0)
	local right = math.min(math.ceil(x + radius + 1), resolution - 1)
	local top = math.max(math.floor(y - radius - 1), 0)
	local bottom = math.min(math.ceil(y + radius + 1), resolution - 1)
	if left > right or top > bottom then return end

	local red, green, blue = color.R * 255, color.G * 255, color.B * 255

	for pixelY = top, bottom do
		local deltaY = pixelY + 0.5 - y
		local rowOffset = pixelY * resolution * 4

		for pixelX = left, right do
			local deltaX = pixelX + 0.5 - x
			local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
			local coverage = math.clamp(radius - distance + 0.5, 0, 1)
			if coverage <= 0 then continue end

			local sourceAlpha = alpha * coverage * 255
			local offset = rowOffset + pixelX * 4
			if sourceAlpha <= buffer.readu8(pixels, offset + 3) then continue end

			buffer.writeu8(pixels, offset, red)
			buffer.writeu8(pixels, offset + 1, green)
			buffer.writeu8(pixels, offset + 2, blue)
			buffer.writeu8(pixels, offset + 3, sourceAlpha)
		end
	end

	self._minX = math.min(self._minX, left)
	self._maxX = math.max(self._maxX, right)
	self._minY = math.min(self._minY, top)
	self._maxY = math.max(self._maxY, bottom)
end

function MapCanvas:Stroke(points: { Vector2 }, widthAt: (number) -> number, color: Color3, alpha: number)
	if #points < 2 then return end

	local total = 0
	local lengths = {}
	for index = 1, #points - 1 do
		local segment = (points[index + 1] - points[index]).Magnitude
		lengths[index] = segment
		total += segment
	end
	if total <= 0 then return end

	local travelled = 0
	for index = 1, #points - 1 do
		local from, to = points[index], points[index + 1]
		local length = lengths[index]
		if length <= 0 then continue end

		local steps = math.max(math.ceil(length / 0.7), 1)
		for step = 0, steps do
			local along = step / steps
			local progress = (travelled + along * length) / total
			local point = from:Lerp(to, along)
			self:Stamp(point.X, point.Y, widthAt(progress) / 2, color, alpha)
		end
		travelled += length
	end
end

function MapCanvas:Flush()
	if self._minX > self._maxX or self._minY > self._maxY then return end

	local resolution = self.Resolution
	local left = math.clamp(self._minX, 0, resolution - 1)
	local top = math.clamp(self._minY, 0, resolution - 1)
	local width = math.clamp(self._maxX, 0, resolution - 1) - left + 1
	local height = math.clamp(self._maxY, 0, resolution - 1) - top + 1

	local region = buffer.create(width * height * 4)
	for row = 0, height - 1 do
		local source = ((top + row) * resolution + left) * 4
		buffer.copy(region, row * width * 4, self._pixels, source, width * 4)
	end

	self.Image:WritePixelsBuffer(Vector2.new(left, top), Vector2.new(width, height), region)
	self:ResetDirty()
end

function MapCanvas:Destroy()
	self.Image:Destroy()
end

return MapCanvas
