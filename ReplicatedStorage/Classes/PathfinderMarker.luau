local TweenService = game:GetService("TweenService")

--- @class PathfinderMarker
--- One trail marker: a glowing floor pad with an arrow pointing the way its owner was facing, and a
--- numbered dot floating over it.
---
--- Built entirely from parts in code, and created only on the client that placed it -- nothing here
--- replicates, so a marker is a note the player leaves for themselves and nobody else's world
--- contains it. The dot is deliberately NOT drawn on top of geometry: a marker down the corridor is
--- something you have to be able to see to use.
local PathfinderMarker = {}
PathfinderMarker.__index = PathfinderMarker

local ARROW_LIFT = 0.06

-- name, size, offset, yaw. Forward is -Z, so the two blades meet in a point ahead of the stem.
local ARROW = {
	{ "BladeLeft", Vector3.new(1.25, 0.06, 0.3), Vector3.new(-0.44, ARROW_LIFT, -0.36), math.rad(45) },
	{ "BladeRight", Vector3.new(1.25, 0.06, 0.3), Vector3.new(0.44, ARROW_LIFT, -0.36), math.rad(-45) },
	{ "Stem", Vector3.new(0.3, 0.06, 1.1), Vector3.new(0, ARROW_LIFT, 0.35), 0 },
}

local function newPart(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false -- so no aim, dig or enemy raycast ever hits a marker
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

local function buildLabel(adornee: BasePart, index: number, config): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Adornee = adornee
	-- Sized in studs rather than pixels so the dot recedes with the marker it belongs to. At a fixed
	-- pixel size the far end of a trail piles into an unreadable stack of overlapping numbers.
	billboard.Size = UDim2.fromScale(1, 1)
	-- Screen space, not world space: the pad it hangs off is a cylinder lying on its side, and a
	-- world-space offset is rotated by the adornee, which throws the dot out sideways.
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.MaxDistance = config.LabelDistance
	billboard.LightInfluence = 0
	billboard.Parent = adornee

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromScale(1, 1)
	dot.BackgroundTransparency = 0.25
	dot.BorderSizePixel = 0
	dot.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot

	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.Size = UDim2.fromScale(1, 1)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.GothamBold
	number.Text = tostring(index)
	number.TextScaled = true
	number.TextColor3 = Color3.fromRGB(12, 14, 18)
	number.Parent = dot

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.2, 0)
	padding.PaddingBottom = UDim.new(0.2, 0)
	padding.Parent = number

	return billboard, dot
end

--- @param cframe CFrame -- on the floor, facing the way the arrow should point
--- @param index number -- the placement's running number, shown on the dot
function PathfinderMarker.new(cframe: CFrame, index: number, config, parent: Instance)
	local self = setmetatable({}, PathfinderMarker)

	self.Config = config
	self.Position = cframe.Position
	self.Index = index

	local model = Instance.new("Model")
	model.Name = `Marker{index}`

	-- A cylinder's flat faces point along its X axis, so it lies down a quarter turn from upright.
	local pad = newPart(
		"Pad",
		Vector3.new(0.08, config.PadSize, config.PadSize),
		cframe * CFrame.Angles(0, 0, math.pi / 2),
		model
	)
	pad.Shape = Enum.PartType.Cylinder
	pad.Transparency = 0.7

	self.Pad = pad
	self.Blades = {}
	for _, entry in ARROW do
		local name, size, offset, yaw = entry[1], entry[2], entry[3], entry[4]
		local blade = newPart(name, size, cframe * CFrame.new(offset) * CFrame.Angles(0, yaw, 0), model)
		table.insert(self.Blades, blade)
	end

	local _, dot = buildLabel(pad, index, config)
	self.Dot = dot

	model.PrimaryPart = pad
	model.Parent = parent
	self.Model = model

	self:SetShade(1)
	self:_scaleTo(0.4, 1, config.PlaceTime)

	return self
end

-- Model scale is a method rather than a property, so a NumberValue is tweened and the scale follows.
function PathfinderMarker:_scaleTo(from: number, to: number, time: number): Tween
	local model = self.Model
	model:ScaleTo(from)

	local scale = Instance.new("NumberValue")
	scale.Value = from

	local connection = scale:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:ScaleTo(scale.Value)
		end
	end)

	local tween = TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Back), { Value = to })
	tween.Completed:Once(function()
		connection:Disconnect()
		scale:Destroy()
	end)
	tween:Play()
	return tween
end

--- Colours the marker by age: 1 is the one just placed, 0 the oldest still standing. The gradient is
--- what makes a trail readable as a direction rather than a scattering of dots.
function PathfinderMarker:SetShade(alpha: number)
	if self.Dying then return end

	local color = self.Config.OldColor:Lerp(self.Config.NewColor, alpha)

	self.Pad.Color = color
	for _, blade in self.Blades do
		blade.Color = color
		blade.Transparency = 0.3 * (1 - alpha)
	end
	self.Dot.BackgroundColor3 = color
	self.Dot.BackgroundTransparency = 0.25 + 0.35 * (1 - alpha)
end

--- A quick flare, used to answer "there is already one of these here" without spending a marker.
function PathfinderMarker:Pulse()
	if self.Dying then return end
	if self.PulseTween then
		self.PulseTween:Cancel()
	end

	self.Pad.Transparency = 0.7
	self.PulseTween = TweenService:Create(
		self.Pad,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true),
		{ Transparency = 0.15 }
	)
	self.PulseTween:Play()
end

function PathfinderMarker:Destroy()
	if self.Dying then return end
	self.Dying = true

	if self.PulseTween then
		self.PulseTween:Cancel()
		self.PulseTween = nil
	end

	local time = self.Config.RemoveTime
	self:_scaleTo(self.Model:GetScale(), 0.2, time)

	for _, part in { self.Pad, table.unpack(self.Blades) } do
		TweenService:Create(part, TweenInfo.new(time), { Transparency = 1 }):Play()
	end
	TweenService:Create(self.Dot, TweenInfo.new(time), { BackgroundTransparency = 1 }):Play()

	local model = self.Model
	task.delay(time, function()
		model:Destroy()
	end)
end

return PathfinderMarker
