local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)

local Visor = ClientTool.extend("Visor")

local NEUTRAL = {
	Saturation = 0,
	Brightness = 0,
	Contrast = 0,
	TintColor = Color3.new(1, 1, 1),
}

local correction = Instance.new("ColorCorrectionEffect")
correction.Name = "VisorColor"
correction.Enabled = false
correction.Parent = Lighting

local activeTween: Tween? = nil
local activeCount = 0

local function tweenLighting(target: { [string]: any }, duration: number, onComplete: (() -> ())?)
	local previous = activeTween
	activeTween = nil
	if previous then
		previous:Cancel()
	end

	if target ~= NEUTRAL then
		correction.Enabled = true
	end

	local tween = TweenService:Create(
		correction,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		target
	)
	activeTween = tween
	tween:Play()
	tween.Completed:Once(function(playbackState)
		if activeTween ~= tween then return end
		activeTween = nil
		if playbackState == Enum.PlaybackState.Completed and onComplete then
			onComplete()
		end
	end)
end

function Visor.new(tool: Tool)
	return ClientTool.new(tool, Visor)
end

function Visor:_applyLighting(active: boolean)
	local config = self.Config
	local duration = if active then (config.LightingInTime or 0.3) else (config.LightingOutTime or 0.45)

	if active then
		tweenLighting({
			Saturation = config.LightingSaturation or -0.18,
			Brightness = config.LightingBrightness or 0.05,
			Contrast = config.LightingContrast or 0.04,
			TintColor = config.LightingTint or Color3.fromRGB(190, 220, 255),
		}, duration)
		return
	end

	tweenLighting(NEUTRAL, duration, function()
		if activeCount <= 0 then
			correction.Enabled = false
		end
	end)
end

function Visor:_setEquipped(equipped: boolean)
	if self.IsEquipped == equipped then return end
	self.IsEquipped = equipped

	if equipped then
		activeCount += 1
		self:_applyLighting(true)
		return
	end

	activeCount = math.max(activeCount - 1, 0)
	if activeCount <= 0 then
		self:_applyLighting(false)
	end
end

function Visor:OnEquipped()
	self:_setEquipped(true)
end

function Visor:OnUnequipped()
	self:_setEquipped(false)
end

function Visor:OnDestroy()
	self:_setEquipped(false)
end

return Visor
