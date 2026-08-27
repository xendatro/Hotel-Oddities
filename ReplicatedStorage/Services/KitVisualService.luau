local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local HumanoidStatsService = require(ReplicatedStorage.Services.HumanoidStatsService)

local ROW = KitConfig.Animation.Row
local VIEWPORT = KitConfig.Viewport
local MINIMUM_LINES = 6

local FONT = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local INK = Color3.fromRGB(72, 72, 72)
local GOOD = Color3.fromRGB(64, 118, 72)
local BAD = Color3.fromRGB(164, 62, 62)
local MUTED = Color3.fromRGB(132, 128, 122)

local KitVisualService = {}

local Tools = ReplicatedStorage:WaitForChild("Tools")

function KitVisualService.Showcase(kit: KitConfig.Kit): string?
	if kit.Showcase then return kit.Showcase end

	local best, bestPrice = nil, -1
	for itemName in kit.Items or {} do
		local entry = ItemShopConfig.EntriesById[itemName]
		local price = if entry then entry.CoinPrice else 0
		if price > bestPrice then
			best, bestPrice = itemName, price
		end
	end
	return best
end

local function clearViewport(viewport: ViewportFrame)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then child:Destroy() end
	end
end

function KitVisualService.BuildPreview(viewport: ViewportFrame, itemName: string?)
	clearViewport(viewport)
	if not itemName then return end

	local source = Tools:FindFirstChild(itemName)
	if not source or not source:IsA("Tool") then return end

	local model = Instance.new("Model")
	model.Name = itemName

	local tool = source:Clone()
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	tool.Parent = model
	model.Parent = viewport
	model:PivotTo(CFrame.identity)

	local box, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.5 * VIEWPORT.Padding
	if radius <= 0 then return end

	local entry = ItemShopConfig.EntriesById[itemName]
	local distance = radius / math.tan(math.rad(VIEWPORT.FieldOfView) * 0.5)
	distance *= (entry and entry.Zoom) or VIEWPORT.Zoom

	local yaw = math.rad((entry and entry.Yaw) or VIEWPORT.Yaw)
	local pitch = math.rad((entry and entry.Pitch) or VIEWPORT.Pitch)
	local direction = CFrame.Angles(pitch, yaw, 0).LookVector

	local camera = Instance.new("Camera")
	camera.FieldOfView = VIEWPORT.FieldOfView
	camera.CFrame = CFrame.lookAt(box.Position + direction * distance, box.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = VIEWPORT.Ambient
	viewport.LightColor = VIEWPORT.LightColor
	viewport.LightDirection = VIEWPORT.LightDirection
end

local function ensure(parent: Instance, name: string, className: string): any
	local existing = parent:FindFirstChild(name)
	if existing then return existing end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

function KitVisualService.DressCard(button: ImageButton, kit: KitConfig.Kit)
	local rarity = KitConfig.GetRarity(kit)

	local stroke = ensure(button, "RarityStroke", "UIStroke") :: UIStroke
	stroke.Color = rarity.Accent
	stroke.Thickness = 2.5
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local ribbon = ensure(button, "Ribbon", "Frame") :: Frame
	ribbon.AnchorPoint = Vector2.new(0.5, 1)
	ribbon.Position = UDim2.fromScale(0.5, 1)
	ribbon.Size = UDim2.fromScale(1, 0.17)
	ribbon.BackgroundColor3 = rarity.Accent
	ribbon.BackgroundTransparency = 0.08
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = button.ZIndex + 2

	local ribbonLabel = ensure(ribbon, "Label", "TextLabel") :: TextLabel
	ribbonLabel.Size = UDim2.fromScale(1, 1)
	ribbonLabel.BackgroundTransparency = 1
	ribbonLabel.FontFace = BOLD
	ribbonLabel.Text = string.upper(rarity.Name)
	ribbonLabel.TextColor3 = Color3.fromRGB(248, 245, 238)
	ribbonLabel.TextScaled = true
	ribbonLabel.ZIndex = ribbon.ZIndex + 1
	local ribbonSize = ensure(ribbonLabel, "UITextSizeConstraint", "UITextSizeConstraint") :: UITextSizeConstraint
	ribbonSize.MaxTextSize = 14

	local name = ensure(button, "KitLabel", "TextLabel") :: TextLabel
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 0.035)
	name.Size = UDim2.fromScale(0.9, 0.16)
	name.BackgroundTransparency = 1
	name.FontFace = BOLD
	name.Text = string.upper(kit.Name)
	name.TextColor3 = INK
	name.TextScaled = true
	name.ZIndex = button.ZIndex + 2
	local nameSize = ensure(name, "UITextSizeConstraint", "UITextSizeConstraint") :: UITextSizeConstraint
	nameSize.MaxTextSize = 18

	local status = ensure(button, "StatusLabel", "TextLabel") :: TextLabel
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.fromScale(0.5, 0.835)
	status.Size = UDim2.fromScale(0.9, 0.13)
	status.BackgroundTransparency = 1
	status.FontFace = BOLD
	status.TextColor3 = rarity.Accent
	status.TextScaled = true
	status.Text = ""
	status.ZIndex = button.ZIndex + 2
	local statusSize = ensure(status, "UITextSizeConstraint", "UITextSizeConstraint") :: UITextSizeConstraint
	statusSize.MaxTextSize = 15

	local dim = ensure(button, "Dim", "Frame") :: Frame
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(28, 26, 24)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.ZIndex = button.ZIndex + 3

	local viewport = button:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, 0.45)
		viewport.Size = UDim2.fromScale(0.94, 0.56)
		viewport.ZIndex = button.ZIndex + 1
	end
end

function KitVisualService.SetCardStatus(button: ImageButton, text: string, dimmed: boolean, color: Color3?)
	local status = button:FindFirstChild("StatusLabel")
	if status and status:IsA("TextLabel") then
		status.Text = text
		if color then status.TextColor3 = color end
	end

	local dim = button:FindFirstChild("Dim")
	if dim and dim:IsA("Frame") then
		dim.Visible = dimmed
		dim.BackgroundTransparency = if dimmed then 0.55 else 1
	end
end

local function formatStat(row): string
	local stat = row.Stat

	if stat.Mode == "Scale" then
		local ratio = if stat.Base ~= 0 then row.Value / stat.Base - 1 else 0
		local percent = math.floor(math.abs(ratio) * 100 + 0.5)
		local sign = if ratio < 0 then "-" else "+"
		return `{string.upper(stat.Name)} {sign}{percent}%`
	end

	local delta = row.Delta
	local rounded = math.floor(math.abs(delta) + 0.5)
	local sign = if delta < 0 then "-" else "+"
	return `{string.upper(stat.Name)} {sign}{rounded}`
end

local function makeLabel(parent: Frame, order: number, height: number, bold: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = `Row{order}`
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, height)
	label.BackgroundTransparency = 1
	label.FontFace = if bold then BOLD else FONT
	label.TextColor3 = INK
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTransparency = 1
	label.Parent = parent

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = if bold then ROW.HeaderTextSize else ROW.TextSize
	constraint.Parent = label

	return label
end

local function statLines(kit: KitConfig.Kit): { { Text: string, Color: Color3 } }
	local lines = {}
	for _, row in HumanoidStatsService.Describe(kit.Stats or {}) do
		table.insert(lines, {
			Text = formatStat(row),
			Color = if row.Better then GOOD else BAD,
		})
	end
	return lines
end

local function itemLines(kit: KitConfig.Kit): { { Text: string, Color: Color3 } }
	local items = {}
	for itemName, count in kit.Items or {} do
		table.insert(items, { Name = itemName, Count = count })
	end
	table.sort(items, function(a, b)
		return a.Name < b.Name
	end)

	local lines = {}
	for _, item in items do
		table.insert(lines, {
			Text = if item.Count > 1 then `{item.Name} x{item.Count}` else item.Name,
			Color = INK,
		})
	end
	return lines
end

function KitVisualService.FillDetails(holder: Frame, kit: KitConfig.Kit, animate: boolean)
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	local layout = holder:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(ROW.Padding, 0)
	end

	local buffs = statLines(kit)
	local items = itemLines(kit)

	local lines: { { Text: string, Color: Color3, Header: boolean } } = {}

	local function section(title: string, entries)
		table.insert(lines, { Text = title, Color = MUTED, Header = true })
		if #entries == 0 then
			table.insert(lines, { Text = "None", Color = MUTED, Header = false })
			return
		end
		for _, entry in entries do
			table.insert(lines, { Text = entry.Text, Color = entry.Color, Header = false })
		end
	end

	section("BUFFS", buffs)
	section("ITEMS", items)

	local count = math.max(#lines, MINIMUM_LINES)
	local height = (1 - ROW.Padding * (count - 1)) / count

	for order, line in lines do
		local label = makeLabel(holder, order, height, line.Header)
		label.Text = line.Text
		label.TextColor3 = line.Color

		if not animate then
			label.TextTransparency = 0
			continue
		end

		task.delay((order - 1) * ROW.Stagger, function()
			if not label.Parent then return end
			TweenService:Create(
				label,
				TweenInfo.new(ROW.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0 }
			):Play()
		end)
	end
end

function KitVisualService.SortByRarity(entries: { KitConfig.Kit }, rarestFirst: boolean): { KitConfig.Kit }
	local sorted = table.clone(entries)

	table.sort(sorted, function(a, b)
		local orderA = KitConfig.GetRarity(a).Order
		local orderB = KitConfig.GetRarity(b).Order
		if orderA ~= orderB then
			return if rarestFirst then orderA > orderB else orderA < orderB
		end
		return a.Name < b.Name
	end)

	return sorted
end

KitVisualService.Ink = INK
KitVisualService.Good = GOOD
KitVisualService.Bad = BAD
KitVisualService.Muted = MUTED
KitVisualService.Font = FONT
KitVisualService.BoldFont = BOLD

return KitVisualService
