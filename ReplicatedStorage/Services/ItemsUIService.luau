local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VoiceChatService = game:GetService("VoiceChatService")

local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)

local ItemsUIService = {}

if not RunService:IsClient() then
	return ItemsUIService
end

local CARD = ItemShopConfig.Animation.Card
local BUTTON = ItemShopConfig.Animation.Button
local INFO = ItemShopConfig.Animation.Info
local VIEWPORT = ItemShopConfig.Viewport

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("ItemsGui") :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local itemsFrame = design:WaitForChild("Items") :: Frame
local template = itemsFrame:WaitForChild("Template") :: ImageButton
local info = design:WaitForChild("Info") :: Frame
local infoName = info:WaitForChild("ItemName") :: TextLabel
local infoDescription = info:WaitForChild("ItemDescription") :: TextLabel
local infoViewport = info:WaitForChild("Preview"):WaitForChild("ViewportFrame") :: ViewportFrame
local coinPrice = info:WaitForChild("coin_icon"):WaitForChild("ItemPrice") :: TextLabel
local coinButton = info:WaitForChild("CoinBuyButton") :: ImageButton
local robuxButton = info:WaitForChild("RobuxBuyButton") :: ImageButton
local coinButtonLabel = coinButton:WaitForChild("TextLabel") :: TextLabel
local robuxButtonLabel = robuxButton:WaitForChild("TextLabel") :: TextLabel
local balance = design:WaitForChild("background_frame"):WaitForChild("Coins"):WaitForChild("CurrentBalance") :: TextLabel

local Communication = ReplicatedStorage.Communication.Items
local Purchase = Communication.Purchase :: RemoteEvent
local Sync = Communication.Sync :: RemoteEvent
local Tools = ReplicatedStorage.Tools

type Card = {
	Id: string,
	Holder: Frame,
	Button: ImageButton,
	Hovered: boolean,
	Pressed: boolean,
	Tween: Tween?,
}

local Cards: { [string]: Card } = {}
local visibleEntries: { ItemShopConfig.Entry } = {}
local selectedId: string? = nil
local dealGeneration = 0
local robuxPrices: { [string]: number } = {}

local function clearViewport(viewport: ViewportFrame)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then child:Destroy() end
	end
end

local function buildPreview(viewport: ViewportFrame, entry: ItemShopConfig.Entry)
	clearViewport(viewport)

	local source = Tools:FindFirstChild(entry.Id)
	if not source or not source:IsA("Tool") then return end

	local model = Instance.new("Model")
	model.Name = entry.Id
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
	local distance = radius / math.tan(math.rad(VIEWPORT.FieldOfView) * 0.5)
	distance *= entry.Zoom or VIEWPORT.Zoom

	local yaw = math.rad(entry.Yaw or VIEWPORT.Yaw)
	local pitch = math.rad(entry.Pitch or VIEWPORT.Pitch)
	local direction = CFrame.Angles(pitch, yaw, 0).LookVector
	local camera = Instance.new("Camera")
	camera.FieldOfView = VIEWPORT.FieldOfView
	camera.CFrame = CFrame.lookAt(box.Position + direction * distance, box.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function poseCard(card: Card, override: TweenInfo?)
	local scale, lift, tilt = 1, 0, 0
	local duration = CARD.SettleTime
	local style = Enum.EasingStyle.Back

	if card.Pressed then
		scale, duration, style = CARD.PressScale, CARD.PressTime, Enum.EasingStyle.Quad
	elseif card.Hovered then
		scale, lift, tilt, duration = CARD.HoverScale, CARD.HoverLift, CARD.HoverTilt, CARD.HoverTime
	elseif card.Id == selectedId then
		scale, lift, tilt = CARD.SelectedScale, CARD.SelectedLift, CARD.SelectedTilt
	end

	if card.Tween then card.Tween:Cancel() end
	card.Tween = TweenService:Create(card.Button, override or TweenInfo.new(duration, style, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(scale, scale),
		Position = UDim2.fromScale(0.5, 0.5 - lift),
		Rotation = tilt,
	})
	card.Tween:Play()
end

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}

local function playInfoTransition()
	for _, tween in infoTweens do tween:Cancel() end
	table.clear(infoTweens)

	infoName.TextTransparency = 1
	infoDescription.TextTransparency = 1
	infoViewport.ImageTransparency = 1
	infoName.Position = infoNameBase + UDim2.fromScale(0, INFO.Rise)
	infoDescription.Position = infoDescriptionBase + UDim2.fromScale(0, INFO.Rise)

	local tweenInfo = TweenInfo.new(INFO.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	infoTweens = {
		TweenService:Create(infoName, tweenInfo, { TextTransparency = 0, Position = infoNameBase }),
		TweenService:Create(infoDescription, tweenInfo, { TextTransparency = 0, Position = infoDescriptionBase }),
		TweenService:Create(infoViewport, tweenInfo, { ImageTransparency = 0 }),
	}
	for _, tween in infoTweens do tween:Play() end
end

local function robuxText(entry: ItemShopConfig.Entry): string
	return `{ItemShopConfig.RobuxIcon} {robuxPrices[entry.Id] or entry.RobuxPrice}`
end

local function paintInfo(animate: boolean)
	if not selectedId then return end
	local entry = ItemShopConfig.EntriesById[selectedId]
	if not entry then return end

	infoName.Text = string.upper(entry.Name)
	infoDescription.Text = entry.Description
	coinPrice.Text = tostring(entry.CoinPrice)
	coinButtonLabel.Text = "BUY"
	robuxButtonLabel.Text = robuxText(entry)
	buildPreview(infoViewport, entry)
	if animate then playInfoTransition() end
end

local function selectCard(id: string)
	if id == selectedId then return end
	local previous = Cards[selectedId]
	selectedId = id
	if previous then poseCard(previous) end
	local selected = Cards[selectedId]
	if selected then poseCard(selected) end
	paintInfo(true)
end

local function buildCards()
	for order, entry in visibleEntries do
		local holder = Instance.new("Frame")
		holder.Name = entry.Id
		holder.BackgroundTransparency = 1
		holder.Size = template.Size
		holder.LayoutOrder = order
		holder.Parent = itemsFrame

		local button = template:Clone()
		button.Name = "Card"
		button.Visible = true
		button.AutoButtonColor = false
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromScale(0.5, 0.5)
		button.Size = UDim2.fromScale(1, 1)
		button.Parent = holder
		buildPreview(button:WaitForChild("ViewportFrame") :: ViewportFrame, entry)

		local card: Card = {
			Id = entry.Id,
			Holder = holder,
			Button = button,
			Hovered = false,
			Pressed = false,
		}
		Cards[entry.Id] = card

		button.MouseEnter:Connect(function()
			card.Hovered = true
			poseCard(card)
		end)
		button.MouseLeave:Connect(function()
			card.Hovered = false
			card.Pressed = false
			poseCard(card)
		end)
		button.MouseButton1Down:Connect(function()
			card.Pressed = true
			poseCard(card)
		end)
		button.MouseButton1Up:Connect(function()
			card.Pressed = false
			poseCard(card)
		end)
		button.Activated:Connect(function()
			selectCard(entry.Id)
		end)
	end
	template.Visible = false
end

local function dealCards()
	dealGeneration += 1
	local generation = dealGeneration
	for offset, entry in visibleEntries do
		local card = Cards[entry.Id]
		if not card then continue end
		if card.Tween then card.Tween:Cancel() end
		card.Button.Size = UDim2.fromScale(CARD.EnterScale, CARD.EnterScale)
		card.Button.Position = UDim2.fromScale(0.5, 0.5 + CARD.EnterDrop)
		card.Button.Rotation = 0
		task.delay((offset - 1) * CARD.Stagger, function()
			if dealGeneration ~= generation then return end
			poseCard(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		end)
	end
end

type ButtonState = { Hovered: boolean, Pressed: boolean, Tween: Tween? }

local function wireButton(button: ImageButton)
	button.AutoButtonColor = false
	local scale = button:FindFirstChild("InteractionScale") :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "InteractionScale"
		scale.Parent = button
	end
	local baseRotation = button.Rotation
	local state: ButtonState = { Hovered = false, Pressed = false }

	local function pose()
		local targetScale, targetRotation, duration = 1, baseRotation, BUTTON.SettleTime
		if state.Pressed then
			targetScale, targetRotation, duration = BUTTON.PressScale, baseRotation + BUTTON.HoverTilt * 0.5, BUTTON.PressTime
		elseif state.Hovered then
			targetScale, targetRotation, duration = BUTTON.HoverScale, baseRotation + BUTTON.HoverTilt, BUTTON.HoverTime
		end
		if state.Tween then state.Tween:Cancel() end
		state.Tween = TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = targetScale,
		})
		state.Tween:Play()
		TweenService:Create(button, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Rotation = targetRotation,
		}):Play()
	end

	button.MouseEnter:Connect(function()
		state.Hovered = true
		pose()
	end)
	button.MouseLeave:Connect(function()
		state.Hovered = false
		state.Pressed = false
		pose()
	end)
	button.MouseButton1Down:Connect(function()
		state.Pressed = true
		pose()
	end)
	button.MouseButton1Up:Connect(function()
		state.Pressed = false
		pose()
	end)
end

local balanceColor = balance.TextColor3
local function flashBalance(success: boolean)
	local color = success and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(255, 105, 105)
	balance.TextColor3 = color
	TweenService:Create(balance, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextColor3 = balanceColor,
	}):Play()
end

coinButton.Activated:Connect(function()
	if selectedId then Purchase:FireServer(selectedId) end
end)

robuxButton.Activated:Connect(function()
	local entry = ItemShopConfig.EntriesById[selectedId]
	if not entry then return end
	local productId = MarketplaceService.Products.Items[entry.Product]
	if type(productId) == "number" and productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	else
		flashBalance(false)
	end
end)

Sync.OnClientEvent:Connect(function(coins: number, result: string?)
	balance.Text = tostring(coins)
	if result then flashBalance(result == "Purchased") end
end)

player:GetAttributeChangedSignal("Coins"):Connect(function()
	balance.Text = tostring(player:GetAttribute("Coins") or 0)
end)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then dealCards() end
end)

wireButton(coinButton)
wireButton(robuxButton)
balance.Text = tostring(player:GetAttribute("Coins") or ItemShopConfig.StartingCoins)
Sync:FireServer()

local function isVoiceEligible(): boolean
	local success, enabled = pcall(
		VoiceChatService.IsVoiceEnabledForUserIdAsync,
		VoiceChatService,
		player.UserId
	)
	return success and enabled == true
end

task.spawn(function()
	local voiceEligible = isVoiceEligible()
	for _, entry in ItemShopConfig.Entries do
		if not entry.RequiresVoice or voiceEligible then
			table.insert(visibleEntries, entry)
		end
	end
	selectedId = visibleEntries[1] and visibleEntries[1].Id
	buildCards()
	paintInfo(false)

	for _, entry in visibleEntries do
		local productId = MarketplaceService.Products.Items[entry.Product]
		if type(productId) ~= "number" or productId <= 0 then continue end
		task.spawn(function()
			local success, productInfo = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
			if not success or not productInfo or type(productInfo.PriceInRobux) ~= "number" then return end
			robuxPrices[entry.Id] = productInfo.PriceInRobux
			if selectedId == entry.Id then robuxButtonLabel.Text = robuxText(entry) end
		end)
	end
end)

return ItemsUIService
