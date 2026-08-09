local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Other = ReplicatedStorage.Props.Other

--- @class PathfinderMarker
--- One trail marker: the `PathfinderMarker` prop, planted facing the way its owner was going, with
--- its numbered dot set to the placement it is.
---
--- Cloned only on the client that placed it and never replicated, so a marker is a note the player
--- leaves for themselves and nobody else's world contains it. The dot is deliberately not drawn on
--- top of geometry: a marker down the corridor is something you have to be able to see to use.
---
--- Everything about how one looks lives on the prop. This class owns only what changes per marker:
--- which number it carries, how far down the trail it is, and its way in and out.
local PathfinderMarker = {}
PathfinderMarker.__index = PathfinderMarker

--- @param cframe CFrame -- on the floor, facing the way the arrow should point
--- @param index number -- the placement's running number, shown on the dot
function PathfinderMarker.new(cframe: CFrame, index: number, config, parent: Instance)
	local template = Other:FindFirstChild("PathfinderMarker")
	if not template then
		warn("PathfinderMarker: no PathfinderMarker model in ReplicatedStorage.Props.Other")
		return nil
	end

	local self = setmetatable({}, PathfinderMarker)

	self.Config = config
	self.Position = cframe.Position
	self.Index = index

	local model = template:Clone()
	model.Name = `Marker{index}`
	model:PivotTo(cframe)

	local pad = model:FindFirstChild("Pad") :: BasePart
	self.Pad = pad
	self.PadTransparency = pad.Transparency -- the prop's own resting look, restored after a pulse
	self.Dot = pad.Label.Dot
	self.Dot.Number.Text = tostring(index)

	-- Everything solid that is not the pad is arrow, so extra parts added to the prop later shade
	-- and fade along with the rest of it.
	self.Blades = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= pad then
			table.insert(self.Blades, part)
		end
	end

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

	self.Pad.Transparency = self.PadTransparency
	self.PulseTween = TweenService:Create(
		self.Pad,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true),
		{ Transparency = math.max(self.PadTransparency - 0.55, 0) }
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
