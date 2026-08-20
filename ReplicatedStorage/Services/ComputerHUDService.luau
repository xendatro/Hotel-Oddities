--- The computer counter: one small pill on the right edge saying how many of the hotel's computers
--- have been broken into. It is the only place the player is told there is a set of them at all, so
--- it appears the moment a maze with computers exists and hides itself again when none do.
---
--- The number is THIS player's. Hacking is per player -- everyone hunts the same five machines but
--- breaks into their own copy of each -- so somebody else finishing one never moves this pill.
---
--- Nothing here decides anything. The total is read straight off CollectionService, and how many are
--- done comes from the interaction service's local set, which the server keeps in step. Both are
--- recounted from scratch on every signal, so a maze appearing, a maze going away and a computer
--- being hacked all need exactly the same bookkeeping here: none.
---
--- The pill sits at 0.375 of the right edge rather than the middle of it: the effects HUD grows out
--- from the centre of that edge and the revive card occupies 0.17-0.34 of it, and this is the middle
--- of the only band that stays clear when both of them are up at once.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ComputerHUDService = {}

if not RunService:IsClient() then
	return ComputerHUDService
end

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
--- The sibling that owns this client's hacked set. Required outright rather than lazily: both are
--- client-only modules in the same folder, both are booted by the same deferred loop, and a counter
--- that could not read the thing it counts would have nothing to say anyway.
local ComputerService = require(ReplicatedStorage.Services.ComputerService)

local HUD = ComputerConfig.HUD
local TAG = ComputerConfig.Tag

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--- Building the interface -------------------------------------------------------------------------

local pill: Frame
local stroke: UIStroke
local counter: TextLabel
local icon: ImageLabel? = nil
local fallback: TextLabel? = nil

local function build()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = HUD.Name
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HUD.DisplayOrder
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	pill = Instance.new("Frame")
	pill.Name = "Counter"
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -HUD.EdgeMargin, HUD.VerticalPosition, 0)
	pill.Size = HUD.Size
	pill.BackgroundColor3 = HUD.Background
	pill.BackgroundTransparency = HUD.BackgroundTransparency
	pill.BorderSizePixel = 0
	pill.Parent = screenGui

	-- Two pixels of corner and a hard stroke: the same chunky rectangle the minigames are drawn from,
	-- so the counter reads as part of the same machine rather than as part of the hotel's interface.
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = pill

	stroke = Instance.new("UIStroke")
	stroke.Color = HUD.Stroke
	stroke.Thickness = HUD.StrokeThickness
	stroke.Parent = pill

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

--- The icon ---------------------------------------------------------------------------------------

--- Stands in until the art exists, so the pill is never a lonely number.
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

--- The uploaded asset id, or nil while the assets module has not been written or its id is still 0.
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

-- The assets module is written by a separate pass and may land after this service has already drawn
-- its fallback. Watching for it means the icon appears without a rejoin.
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

--- Counting ---------------------------------------------------------------------------------------

local complete = false

--- How many computers THIS player has broken into, and how many there are. Read off the tag rather
--- than held as a running total, so a maze appearing or being torn down needs no bookkeeping here.
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

	-- A hotel with no computers in it should not be told about computers.
	screenGui.Enabled = total > 0
	counter.Text = `{hacked}/{total}`

	complete = total > 0 and hacked == total
	if not complete then
		stroke.Color = HUD.Stroke
		counter.TextColor3 = HUD.Text
		stroke.Transparency = 0
	end
end

-- CollectionService directly rather than TagService:Listen, because the interaction service already
-- listens to this tag and a second listen would be refused. The tag signals are only the TOTAL
-- moving; the hacked half moves on the interaction service's own signal instead.
CollectionService:GetInstanceAddedSignal(TAG):Connect(refresh)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(refresh)
ComputerService.Changed:Connect(refresh)
refresh()

--- Finishing --------------------------------------------------------------------------------------

-- Every computer done is the one moment this pill is worth looking at, so it keeps pulsing rather
-- than flashing once and going quiet -- the number stays readable throughout.
RunService.Heartbeat:Connect(function()
	if not complete or not screenGui.Enabled then return end

	local pulse = (math.sin(os.clock() * HUD.FlashSpeed * math.pi * 2) + 1) / 2
	stroke.Color = HUD.Complete
	stroke.Transparency = HUD.FlashDepth * (1 - pulse)
	counter.TextColor3 = HUD.Text:Lerp(HUD.Complete, pulse)
end)

--- Reading the state ------------------------------------------------------------------------------

--- How many computers THIS player has broken into, and how many there are.
function ComputerHUDService:GetProgress(): (number, number)
	return count()
end

return ComputerHUDService

