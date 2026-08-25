local AssetService = game:GetService("AssetService")

local MapCanvas = {}
MapCanvas.__index = MapCanvas

export type MapCanvas = typeof(setmetatable({} :: {
	Resolution: number,
	Image: EditableImage,
	Content: Content,
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
	self.Content = Content.fromObject(self.Image)
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

function MapCanvas:FillAll(color: Color3, alpha: number, grain: number?, feather: number?, radius: number?)
	local resolution = self.Resolution
	local pixels = self._pixels
	local red, green, blue = color.R * 255, color.G * 255, color.B * 255
	local base = math.clamp(alpha, 0, 1) * 255
	local spread = (grain or 0) * 255
	local edge = feather or 0
	local random = Random.new(20260824)

	for row = 0, resolution - 1 do
		local rowOffset = row * resolution * 4
		for column = 0, resolution - 1 do
			local value = base
			if spread > 0 then
				value += random:NextNumber(-spread, spread)
			end

			if edge > 0 then
				local half = (resolution - 1) / 2
				local corner = radius or 0
				local offsetX = math.abs(column - half) - (half - corner)
				local offsetY = math.abs(row - half) - (half - corner)
				local outsideX, outsideY = math.max(offsetX, 0), math.max(offsetY, 0)
				local outside = math.sqrt(outsideX * outsideX + outsideY * outsideY)
					+ math.min(math.max(offsetX, offsetY), 0)
					- corner
				local distance = -outside

				local angle = math.atan2(row - half, column - half)
				local wander = 1
					+ 0.22 * math.sin(angle * 3 + 0.7)
					+ 0.13 * math.sin(angle * 7 + 2.3)
					+ 0.20 * math.sin(column * 0.021 + 1.1)
					+ 0.20 * math.sin(row * 0.019 + 3.4)
					+ 0.10 * math.sin((column + row) * 0.033 + 5.2)
					+ 0.08 * math.sin((column - row) * 0.027 + 0.4)
				local ragged = edge * math.max(wander, 0.55) + random:NextNumber(-edge * 0.08, edge * 0.08)

				if ragged > 0 and distance < ragged then
					local fade = math.clamp(distance / ragged, 0, 1)
					value *= fade * fade * (3 - 2 * fade)
				end
			end

			local index = rowOffset + column * 4
			buffer.writeu8(pixels, index, red)
			buffer.writeu8(pixels, index + 1, green)
			buffer.writeu8(pixels, index + 2, blue)
			buffer.writeu8(pixels, index + 3, math.clamp(value, 0, 255))
		end
	end

	self._minX, self._minY = 0, 0
	self._maxX, self._maxY = resolution - 1, resolution - 1
end

function MapCanvas:FillRect(minimum: Vector2, maximum: Vector2, color: Color3, alpha: number)
	local resolution = self.Resolution
	local pixels = self._pixels

	local left = math.max(math.floor(minimum.X), 0)
	local right = math.min(math.ceil(maximum.X), resolution - 1)
	local top = math.max(math.floor(minimum.Y), 0)
	local bottom = math.min(math.ceil(maximum.Y), resolution - 1)
	if left > right or top > bottom then return end

	local red, green, blue = color.R * 255, color.G * 255, color.B * 255
	local value = math.clamp(alpha, 0, 1) * 255

	for row = top, bottom do
		local rowOffset = row * resolution * 4
		for column = left, right do
			local index = rowOffset + column * 4
			buffer.writeu8(pixels, index, red)
			buffer.writeu8(pixels, index + 1, green)
			buffer.writeu8(pixels, index + 2, blue)
			buffer.writeu8(pixels, index + 3, value)
		end
	end

	self._minX = math.min(self._minX, left)
	self._maxX = math.max(self._maxX, right)
	self._minY = math.min(self._minY, top)
	self._maxY = math.max(self._maxY, bottom)
end

function MapCanvas:ClearRect(minimum: Vector2, maximum: Vector2)
	local resolution = self.Resolution
	local pixels = self._pixels

	local left = math.max(math.floor(minimum.X), 0)
	local right = math.min(math.ceil(maximum.X), resolution - 1)
	local top = math.max(math.floor(minimum.Y), 0)
	local bottom = math.min(math.ceil(maximum.Y), resolution - 1)
	if left > right or top > bottom then return end

	local width = (right - left + 1) * 4
	for row = top, bottom do
		buffer.fill(pixels, (row * resolution + left) * 4, 0, width)
	end

	self._minX = math.min(self._minX, left)
	self._maxX = math.max(self._maxX, right)
	self._minY = math.min(self._minY, top)
	self._maxY = math.max(self._maxY, bottom)
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
