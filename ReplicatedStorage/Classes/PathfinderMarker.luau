local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Other = ReplicatedStorage.Props.Other

local PathfinderMarker = {}
PathfinderMarker.__index = PathfinderMarker

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
	self.PadTransparency = pad.Transparency
	self.Dot = pad.Label.Dot
	self.Dot.Number.Text = tostring(index)

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
