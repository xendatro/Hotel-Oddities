local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StalkerGlowService = {}

if not RunService:IsClient() then
	return StalkerGlowService
end

local EyeGlow = require(ReplicatedStorage.Classes.EyeGlow)
local MathService = require(ReplicatedStorage.Services.MathService)
local VfxConfig = require(ReplicatedStorage.Configs.VfxConfig)
local VfxService = require(ReplicatedStorage.Services.VfxService)

local STALKER = VfxConfig.Stalker
local ENEMY_TAG = "Enemy"

type Eye = {
	Part: BasePart,
	Color: Color3,
	Glow: EyeGlow.EyeGlow?,
}

type Flare = {
	Eyes: { Eye },
	SpottedAt: number,
	WithdrawnAt: number?,
}

local Flares: { [Model]: Flare } = {}
local Watched: { [Model]: { RBXScriptConnection } } = {}

local function findTemplate(path: { string }): Instance?
	local current: Instance? = ReplicatedStorage:FindFirstChild(VfxConfig.Folder)
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function inRange(model: Model): boolean
	local ok, pivot = pcall(model.GetPivot, model)
	return ok and VfxService:IsInRange(pivot.Position, STALKER.MaxDistance)
end

local function endFlare(model: Model)
	local flare = Flares[model]
	if not flare then return end
	Flares[model] = nil

	for _, eye in flare.Eyes do
		if eye.Part.Parent then eye.Part.Color = eye.Color end
		if eye.Glow then eye.Glow:Destroy() end
	end
end

local function puff(model: Model)
	local head = model:FindFirstChild(STALKER.HeadName)
	local camera = workspace.CurrentCamera
	if not head or not head:IsA("BasePart") or not camera then return end

	local origin = head.Position
	local away = MathService.Horizontal(origin - camera.CFrame.Position)
	local direction = if away.Magnitude > 1e-3
		then (away.Unit * (1 - STALKER.WispLift) + Vector3.yAxis * STALKER.WispLift).Unit
		else Vector3.yAxis
	VfxService:Play(VfxConfig.Templates.StalkerWisp, CFrame.lookAt(origin, origin + direction))
end

local function startFlare(model: Model)
	endFlare(model)
	if not inRange(model) then return end

	local head = model:FindFirstChild(STALKER.HeadName)
	if not head then return end

	local template = findTemplate(STALKER.GlowTemplate)
	local eyes: { Eye } = {}
	for _, name in STALKER.EyeNames do
		local part = head:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(eyes, {
				Part = part,
				Color = part.Color,
				Glow = EyeGlow.new(template, part, {
					Scale = STALKER.GlowScale,
					TowardCamera = STALKER.GlowTowardCamera,
				}),
			})
		end
	end
	if #eyes == 0 then return end

	Flares[model] = {
		Eyes = eyes,
		SpottedAt = os.clock(),
		WithdrawnAt = nil,
	}
	puff(model)
end

local function withdraw(model: Model)
	local flare = Flares[model]
	if flare and not flare.WithdrawnAt then
		flare.WithdrawnAt = os.clock()
	end
end

local function render(model: Model, flare: Flare, now: number): boolean
	if not model.Parent or now - flare.SpottedAt > STALKER.MaxFlareTime then return false end

	local fade = 1
	if flare.WithdrawnAt then
		fade = 1 - math.clamp((now - flare.WithdrawnAt) / STALKER.WithdrawFade, 0, 1)
		if fade <= 0 then return false end
	end

	local strength = EyeGlow.Flare(now - flare.SpottedAt, STALKER.FlareAttack, STALKER.FlareSustain, STALKER.FlareDecay)
	local growth = 1 + STALKER.FlareGrowth * strength
	for _, eye in flare.Eyes do
		if eye.Part.Parent then
			eye.Part.Color = eye.Color:Lerp(STALKER.HotEye, strength * STALKER.FlareEyeHeat * fade)
		end
		if eye.Glow then
			eye.Glow:Render(strength * fade, growth, 1 + STALKER.FlareBrightness * strength)
		end
	end
	return true
end

local function watch(instance: Instance)
	if not instance:IsA("Model") or Watched[instance] then return end
	local model = instance :: Model
	Watched[model] = {
		model:GetAttributeChangedSignal(STALKER.SpottedAttribute):Connect(function()
			startFlare(model)
		end),
		model:GetAttributeChangedSignal(STALKER.WithdrawnAttribute):Connect(function()
			withdraw(model)
		end),
	}
end

local function unwatch(instance: Instance)
	if not instance:IsA("Model") then return end
	local connections = Watched[instance]
	Watched[instance] = nil
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	endFlare(instance)
end

CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(watch)
CollectionService:GetInstanceRemovedSignal(ENEMY_TAG):Connect(unwatch)
for _, instance in CollectionService:GetTagged(ENEMY_TAG) do
	watch(instance)
end

RunService.RenderStepped:Connect(function()
	if next(Flares) == nil then return end
	local now = os.clock()
	for model, flare in Flares do
		if not render(model, flare, now) then
			endFlare(model)
		end
	end
end)

return StalkerGlowService
