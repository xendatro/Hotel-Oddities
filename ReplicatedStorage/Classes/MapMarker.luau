local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local Spring = require(ReplicatedStorage.Classes.Spring)

local Markers = MapConfig.Markers

local MapMarker = {}
MapMarker.__index = MapMarker

export type MapMarker = typeof(setmetatable({} :: {
	Kind: string,
	Frame: Frame,
	Connections: { RBXScriptConnection },
	_glyph: TextLabel,
	_disc: Frame,
	_ring: Frame,
	_scale: UIScale,
	_spring: any,
	_ringClock: number,
	_flashClock: number,
	_stroke: UIStroke,
}, MapMarker))

local GLYPHS = {
	Computer = "C",
	Spawn = "S",
	Exit = "E",
	Default = "?",
}

local function setUpConnections(self: MapMarker): { RBXScriptConnection }
	return {
		RunService.RenderStepped:Connect(function(deltaTime)
			self._spring:Step(deltaTime)
			self._scale.Scale = self._spring.Position

			if self._ringClock < math.huge then
				self._ringClock += deltaTime
				local progress = self._ringClock / Markers.PingTime
				if progress >= 1 then
					self._ringClock = math.huge
					self._ring.Visible = false
				else
					local eased = 1 - (1 - progress) ^ 3
					local size = Markers.Size * (1 + eased * Markers.PingSize)
					self._ring.Size = UDim2.fromOffset(size, size)
					self._ring.BackgroundTransparency = 1
					self._stroke.Transparency = eased
				end
			end

			if self._flashClock < math.huge then
				self._flashClock += deltaTime
				local progress = self._flashClock / Markers.FlashTime
				if progress >= 1 then
					self._flashClock = math.huge
					self._glyph.TextTransparency = 0
				else
					self._glyph.TextTransparency = (1 - progress) * 0.65 * math.abs(math.sin(progress * math.pi * 3))
				end
			end
		end),
	}
end

function MapMarker.new(parent: GuiObject, kind: string, userId: number?): MapMarker
	local self = setmetatable({}, MapMarker)

	self.Kind = kind

	local frame = Instance.new("Frame")
	frame.Name = kind .. "Marker"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(Markers.Size, Markers.Size)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 15
	frame.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local ring = Instance.new("Frame")
	ring.Name = "Ping"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(Markers.Size, Markers.Size)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.ZIndex = 14
	ring.Parent = frame
	GuiBuilderService.Corner(ring, UDim.new(1, 0))

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = Markers.Fill
	disc.BackgroundTransparency = Markers.FillTransparency
	disc.BorderSizePixel = 0
	disc.ZIndex = 15
	disc.Parent = frame
	GuiBuilderService.Corner(disc, UDim.new(1, 0))
	GuiBuilderService.Stroke(disc, MapConfig.Ink.Color, Markers.StrokeWidth)

	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.new(1, -Markers.GlyphInset, 1, -Markers.GlyphInset)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.Kalam
	glyph.Text = GLYPHS[kind] or GLYPHS.Default
	glyph.TextColor3 = MapConfig.Ink.Color
	glyph.TextScaled = true
	glyph.ZIndex = 16
	glyph.Parent = frame

	if userId then
		glyph.Visible = false

		local headshot = Instance.new("ImageLabel")
		headshot.Name = "Headshot"
		headshot.AnchorPoint = Vector2.new(0.5, 0.5)
		headshot.Position = UDim2.fromScale(0.5, 0.5)
		headshot.Size = UDim2.new(1, -Markers.StrokeWidth * 2, 1, -Markers.StrokeWidth * 2)
		headshot.BackgroundTransparency = 1
		headshot.Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
		headshot.ZIndex = 16
		headshot.Parent = frame
		GuiBuilderService.Corner(headshot, UDim.new(1, 0))
	end

	self.Frame = frame
	self._disc = disc
	self._glyph = glyph
	self._ring = ring
	self._scale = scale
	self._stroke = GuiBuilderService.Stroke(ring, MapConfig.Ink.Color, Markers.StrokeWidth)
	self._spring = Spring.new(190, 0.5, 1 / 120)
	self._spring:Snap(1)
	self._spring.Target = 1
	self._ringClock = math.huge
	self._flashClock = math.huge

	self.Connections = setUpConnections(self)

	return self
end

function MapMarker:SetPosition(position: UDim2)
	self.Frame.Position = position
end

function MapMarker:SetFaded(faded: boolean)
	self._glyph.TextTransparency = if faded then 0.55 else 0
	self._disc.BackgroundTransparency = if faded then 0.55 else Markers.FillTransparency
end

function MapMarker:Pop()
	self._spring:Snap(Markers.PopScale)
	self._spring.Target = 1
	self._ringClock = 0
	self._flashClock = 0
	self._ring.Visible = true
	self._stroke.Transparency = 0
end

function MapMarker:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self.Frame:Destroy()
end

return MapMarker
