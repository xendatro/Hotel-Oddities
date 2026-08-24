local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ComputerHUDService = {}

if not RunService:IsClient() then
	return ComputerHUDService
end

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local ComputerService = require(ReplicatedStorage.Services.ComputerService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local HUD = ComputerConfig.HUD
local TAG = ComputerConfig.Tag

local pill: Frame
local stroke: UIStroke
local counter: TextLabel
local icon: ImageLabel? = nil
local fallback: TextLabel? = nil

local function build()
	local screenGui = GuiBuilderService.CreateScreenGui(HUD.Name, HUD.DisplayOrder)
	screenGui.Enabled = false

	pill = Instance.new("Frame")
	pill.Name = "Counter"
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -HUD.EdgeMargin, HUD.VerticalPosition, 0)
	pill.Size = HUD.Size
	pill.BackgroundColor3 = HUD.Background
	pill.BackgroundTransparency = HUD.BackgroundTransparency
	pill.BorderSizePixel = 0
	pill.Parent = screenGui

	GuiBuilderService.Corner(pill, UDim.new(0, 2))

	stroke = GuiBuilderService.Stroke(pill, HUD.Stroke, HUD.StrokeThickness)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local left = HUD.IconPadding + HUD.IconSize + HUD.IconPadding

	counter = Instance.new("TextLabel")
	counter.Name = "Count"
	counter.BackgroundTransparency = 1
	counter.AnchorPoint = Vector2.new(0, 0.5)
	counter.Position = UDim2.new(0, left, 0.5, 0)
	counter.Size = UDim2.new(1, -(left + HUD.IconPadding), 0, HUD.IconSize)
	counter.Font = HUD.Font
	counter.TextColor3 = HUD.Text
	counter.TextScaled = true
	counter.TextXAlignment = Enum.TextXAlignment.Center
	counter.Text = "0/0"
	counter.Parent = pill

	return screenGui
end

local screenGui = build()

local function buildFallback()
	if fallback then return end
	local label = Instance.new("TextLabel")
	label.Name = "Fallback"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, HUD.IconPadding, 0.5, 0)
	label.Size = UDim2.fromOffset(HUD.IconSize, HUD.IconSize)
	label.Font = HUD.Font
	label.TextColor3 = HUD.Text
	label.TextScaled = true
	label.Text = HUD.FallbackIcon
	label.Parent = pill
	fallback = label
end

local function iconId(): string?
	local configs = ReplicatedStorage:FindFirstChild("Configs")
	local module = configs and configs:FindFirstChild("ComputerAssets")
	if not module or not module:IsA("ModuleScript") then return nil end

	local ok, assets = pcall(require, module)
	if not ok or type(assets) ~= "table" then return nil end

	local id = assets.ComputerIcon
	if type(id) ~= "string" or id == "" or id == "rbxassetid://0" then return nil end
	return id
end

local function refreshIcon()
	if icon then return end

	local id = iconId()
	if not id then
		buildFallback()
		return
	end

	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0, 0.5)
	image.Position = UDim2.new(0, HUD.IconPadding, 0.5, 0)
	image.Size = UDim2.fromOffset(HUD.IconSize, HUD.IconSize)
	image.Image = id
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = pill
	icon = image

	if fallback then
		fallback:Destroy()
		fallback = nil
	end
end

refreshIcon()

if not icon then
	local configs = ReplicatedStorage:FindFirstChild("Configs")
	if configs then
		configs.ChildAdded:Connect(function(child: Instance)
			if child.Name == "ComputerAssets" then
				task.defer(refreshIcon)
			end
		end)
	end
end

local complete = false

local function count(): (number, number)
	local hacked, total = 0, 0
	for _, model in CollectionService:GetTagged(TAG) do
		if model:IsDescendantOf(workspace) then
			total += 1
			if ComputerService:IsHacked(model :: Model) then
				hacked += 1
			end
		end
	end
	return hacked, total
end

local function refresh()
	local hacked, total = count()

	screenGui.Enabled = total > 0
	counter.Text = `{hacked}/{total}`

	complete = total > 0 and hacked == total
	if not complete then
		stroke.Color = HUD.Stroke
		counter.TextColor3 = HUD.Text
		stroke.Transparency = 0
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(refresh)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(refresh)
ComputerService.Changed:Connect(refresh)
refresh()

RunService.Heartbeat:Connect(function()
	if not complete or not screenGui.Enabled then return end

	local pulse = (math.sin(os.clock() * HUD.FlashSpeed * math.pi * 2) + 1) / 2
	stroke.Color = HUD.Complete
	stroke.Transparency = HUD.FlashDepth * (1 - pulse)
	counter.TextColor3 = HUD.Text:Lerp(HUD.Complete, pulse)
end)

function ComputerHUDService:GetProgress(): (number, number)
	return count()
end

return ComputerHUDService
