local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathService = require(ReplicatedStorage.Services.MathService)

local IMAGE_NAME = "Glow"
local VISIBLE = 0.01

local EyeGlow = {}
EyeGlow.__index = EyeGlow

export type Options = {
	Scale: number,
	TowardCamera: number,
	Tint: Color3?,
}

export type EyeGlow = typeof(setmetatable({} :: {
	Gui: BillboardGui,
	Image: ImageLabel,
	Size: UDim2,
	Transparency: number,
	Brightness: number,
}, EyeGlow))

function EyeGlow.new(template: Instance?, part: BasePart, options: Options): EyeGlow?
	if not template or not template:IsA("BillboardGui") then return nil end

	local gui = template:Clone()
	local image = gui:FindFirstChild(IMAGE_NAME)
	if not image or not image:IsA("ImageLabel") then
		gui:Destroy()
		return nil
	end

	if options.Tint then
		image.ImageColor3 = options.Tint
	end
	local size = gui.Size
	gui.Size = UDim2.new(size.X.Scale * options.Scale, size.X.Offset, size.Y.Scale * options.Scale, size.Y.Offset)
	gui.Adornee = part
	gui.Enabled = false
	gui.StudsOffset = Vector3.new(0, 0, options.TowardCamera)
	gui.Parent = part

	return setmetatable({
		Gui = gui,
		Image = image,
		Size = gui.Size,
		Transparency = image.ImageTransparency,
		Brightness = gui.Brightness,
	}, EyeGlow)
end

function EyeGlow.Flare(elapsed: number, attack: number, sustain: number, decay: number): number
	if elapsed <= 0 then return 0 end
	if elapsed < attack then
		return MathService.Eases.OutQuad(elapsed / attack)
	end
	return sustain + (1 - sustain) * math.exp(-(elapsed - attack) / decay)
end

function EyeGlow:Render(strength: number, growth: number, brightness: number)
	if not self.Gui.Parent then return end

	local shown = strength > VISIBLE
	if self.Gui.Enabled ~= shown then
		self.Gui.Enabled = shown
	end
	if not shown then return end

	local size = self.Size
	self.Gui.Size = UDim2.new(size.X.Scale * growth, size.X.Offset, size.Y.Scale * growth, size.Y.Offset)
	self.Gui.Brightness = self.Brightness * brightness
	self.Image.ImageTransparency = 1 - (1 - self.Transparency) * strength
end

function EyeGlow:Destroy()
	self.Gui:Destroy()
end

return EyeGlow
