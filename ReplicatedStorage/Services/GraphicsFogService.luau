local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GraphicsFogConfig = require(ReplicatedStorage.Configs.GraphicsFogConfig)

local GraphicsFogService = {}

if not RunService:IsClient() or not GraphicsFogConfig.Enabled then
	return GraphicsFogService
end

local GameSettings = UserSettings():GetService("UserGameSettings")
local AutomaticConfig = GraphicsFogConfig.Automatic
local CageConfig = GraphicsFogConfig.Cage

local CAGE_BIND = "GraphicsFogCage"
local CAGE_NORMALS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

local baseFogStart = Lighting.FogStart
local baseFogEnd = Lighting.FogEnd
local baseFogColor = Lighting.FogColor

local parkedAtmosphere: Atmosphere? = nil
local cage: Model? = nil
local cageSlabs: { BasePart } = {}
local fogEnd = GraphicsFogConfig.ReleaseDistance
local fogActive = false
local settled = false

local deviceClass: string
local estimatedLevel: number
local frames = 0
local sampleElapsed = 0
local lastStepClock = -math.huge

local function getDeviceClass(): string
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Mobile"
	end
	return "Desktop"
end

deviceClass = getDeviceClass()
estimatedLevel = AutomaticConfig.StartingLevel[deviceClass] or AutomaticConfig.StartingLevel.Desktop

local function getSavedLevel(): number?
	local saved = GameSettings.SavedQualityLevel
	if saved == Enum.SavedQualitySetting.Automatic then
		return nil
	end
	return saved.Value
end

local function updateEstimate(deltaTime: number)
	frames += 1
	sampleElapsed += deltaTime
	if sampleElapsed < AutomaticConfig.SampleWindow then return end

	local average = frames / sampleElapsed
	frames = 0
	sampleElapsed = 0

	local now = os.clock()
	if now - lastStepClock < AutomaticConfig.StepCooldown then return end

	local step = 0
	if average < AutomaticConfig.LowFpsThreshold then
		step = -1
	elseif average > AutomaticConfig.HighFpsThreshold then
		step = 1
	end
	if step == 0 then return end

	local range = AutomaticConfig.LevelRange[deviceClass] or AutomaticConfig.LevelRange.Desktop
	local stepped = math.clamp(estimatedLevel + step, range.Min, range.Max)
	if stepped == estimatedLevel then return end

	estimatedLevel = stepped
	lastStepClock = now
end

local function parkAtmosphere()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then return end

	if not parkedAtmosphere then
		parkedAtmosphere = atmosphere
	end
	atmosphere.Parent = nil
end

local function restoreAtmosphere()
	if parkedAtmosphere and parkedAtmosphere.Parent == nil then
		parkedAtmosphere.Parent = Lighting
	end
	parkedAtmosphere = nil
end

local function buildCage()
	if cage or not CageConfig.Enabled then return end

	local model = Instance.new("Model")
	model.Name = "GraphicsFogCage"

	cageSlabs = {}
	for _, normal in CAGE_NORMALS do
		local slab = Instance.new("Part")
		slab.Name = "Slab"
		slab.Anchored = true
		slab.CanCollide = false
		slab.CanQuery = false
		slab.CanTouch = false
		slab.CastShadow = false
		slab.Locked = true
		slab.Massless = true
		slab.Material = Enum.Material.SmoothPlastic
		slab.Reflectance = 0
		slab.Color = Color3.new(0, 0, 0)
		slab:SetAttribute("Normal", normal)
		slab.Parent = model
		table.insert(cageSlabs, slab)
	end

	model.Parent = workspace.CurrentCamera
	cage = model
end

local function destroyCage()
	if cage then
		cage:Destroy()
		cage = nil
	end
	cageSlabs = {}
end

local function updateCage()
	if not cage or not CageConfig.Enabled then return end

	local camera = workspace.CurrentCamera
	if not camera then return end
	if cage.Parent ~= camera then
		cage.Parent = camera
	end

	local radius = fogEnd * CageConfig.RadiusRatio
	local span = radius * 4
	local origin = camera.CFrame.Position

	for _, slab in cageSlabs do
		local normal = slab:GetAttribute("Normal") :: Vector3
		local along = normal:Abs()
		slab.Size = along * CageConfig.Thickness + (Vector3.one - along) * span
		slab.CFrame = CFrame.new(origin + normal * radius)
	end
end

local function applyFog()
	Lighting.FogEnd = fogEnd
	Lighting.FogStart = fogEnd * GraphicsFogConfig.FogStartRatio
end

local function setFogActive(value: boolean)
	if fogActive == value then return end
	fogActive = value

	if value then
		Lighting.FogColor = GraphicsFogConfig.FogColor
		parkAtmosphere()
		buildCage()
		applyFog()
		RunService:BindToRenderStep(CAGE_BIND, Enum.RenderPriority.Camera.Value + 5, updateCage)
	else
		RunService:UnbindFromRenderStep(CAGE_BIND)
		destroyCage()
		restoreAtmosphere()
		Lighting.FogStart = baseFogStart
		Lighting.FogEnd = baseFogEnd
		Lighting.FogColor = baseFogColor
	end
end

local function step(deltaTime: number)
	local level = getSavedLevel()
	if not level then
		updateEstimate(deltaTime)
		level = estimatedLevel
	end

	local wanted = level <= GraphicsFogConfig.HighestFoggedLevel
	local clampedLevel = if GraphicsFogConfig.ForceLowestLevel
		then 1
		else math.clamp(math.round(level), 1, 10)
	local targetFogEnd = if wanted
		then GraphicsFogConfig.FogEndByLevel[clampedLevel]
		else GraphicsFogConfig.ReleaseDistance

	if settled then
		local alpha = 1 - math.exp(-deltaTime * GraphicsFogConfig.FogEndBlendSpeed)
		fogEnd += (targetFogEnd - fogEnd) * alpha
	else
		settled = true
		fogEnd = targetFogEnd
	end

	if wanted then
		setFogActive(true)
		applyFog()
	elseif fogActive then
		if fogEnd >= GraphicsFogConfig.ReleaseDistance * 0.95 then
			setFogActive(false)
		else
			applyFog()
		end
	end
end

Lighting.ChildAdded:Connect(function(child)
	if fogActive and child:IsA("Atmosphere") then
		task.defer(parkAtmosphere)
	end
end)

GameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
	frames = 0
	sampleElapsed = 0
	lastStepClock = -math.huge
	if getSavedLevel() == nil then
		estimatedLevel = AutomaticConfig.StartingLevel[deviceClass] or AutomaticConfig.StartingLevel.Desktop
	end
end)

RunService.Heartbeat:Connect(step)

function GraphicsFogService:GetEffectiveLevel(): number
	return getSavedLevel() or estimatedLevel
end

function GraphicsFogService:IsFogActive(): boolean
	return fogActive
end

return GraphicsFogService
