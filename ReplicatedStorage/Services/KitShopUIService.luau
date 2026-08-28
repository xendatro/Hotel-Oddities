local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local KitCard = require(ReplicatedStorage.Classes.KitCard)
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local KitStateService = require(ReplicatedStorage.Services.KitStateService)
local KitVisualService = require(ReplicatedStorage.Services.KitVisualService)
local MathService = require(ReplicatedStorage.Services.MathService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local KitShopUIService = {}

if not RunService:IsClient() then
	return KitShopUIService
end

local CARD = KitConfig.Animation.Card
local INFO = KitConfig.Animation.Info
local TEXT = KitConfig.Text

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild("KitsShop") :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local kitsFrame = design:WaitForChild("KitsCanvas"):WaitForChild("Kits") :: ScrollingFrame
local template = kitsFrame:WaitForChild("Template") :: ImageButton
local info = design:WaitForChild("Info") :: Frame
local infoName = info:WaitForChild("KitName") :: TextLabel
local infoDescription = info:WaitForChild("KitDescription") :: TextLabel
local infoViewport = info:WaitForChild("Preview"):WaitForChild("ViewportFrame") :: ViewportFrame
local infoStats = info:WaitForChild("KitStats") :: Frame
local priceLabel = info:WaitForChild("gem_icon"):WaitForChild("KitPrice") :: TextLabel
local buyButton = info:WaitForChild("GemBuyButton") :: ImageButton
local buyLabel = buyButton:WaitForChild("TextLabel") :: TextLabel
local balance = design:WaitForChild("background_frame"):WaitForChild("Gems"):WaitForChild("CurrentBalance") :: TextLabel
local inventoryButton = design:WaitForChild("InventoryButton") :: ImageButton
local robuxButton = info:WaitForChild("RobuxBuyButton") :: ImageButton

local cards: { [string]: KitCard.KitCard } = {}
local ordered: { KitConfig.Kit } = {}
local selectedId: string? = nil
local dealGeneration = 0

template.Visible = false

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}

local function playInfoTransition()
	TweenProxyService.CancelAll(infoTweens)

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

local function paintBuyButton()
	local kit = selectedId and KitConfig.EntriesById[selectedId]
	if not kit then return end

	local owned = KitStateService:IsOwned(kit.Id)
	local affordable = KitStateService:CanAfford(kit.Id)

	if owned then
		buyLabel.Text = TEXT.Owned
		buyLabel.TextColor3 = KitVisualService.Good
	elseif affordable then
		buyLabel.Text = TEXT.Buy
		buyLabel.TextColor3 = KitVisualService.Ink
	else
		buyLabel.Text = TEXT.CannotAfford
		buyLabel.TextColor3 = KitVisualService.Bad
	end

	buyButton.Interactable = not owned and affordable
end

local function paintInfo(animate: boolean)
	local kit = selectedId and KitConfig.EntriesById[selectedId]
	if not kit then return end

	local rarity = KitConfig.GetRarity(kit)
	infoName.Text = string.upper(kit.Name)
	infoName.TextColor3 = rarity.Accent
	infoDescription.Text = kit.Description
	priceLabel.Text = MathService.Comma(rarity.GemPrice)
	KitVisualService.BuildPreview(infoViewport, KitVisualService.Showcase(kit))
	KitVisualService.FillDetails(infoStats, kit, animate)
	paintBuyButton()

	if animate then playInfoTransition() end
end

local function paintCards()
	for id, card in cards do
		local rarity = KitConfig.GetRarity(card.Kit)
		if KitStateService:IsOwned(id) then
			card:SetStatus(TEXT.Owned, true, KitVisualService.Good)
		else
			card:SetStatus(MathService.Comma(rarity.GemPrice), false, rarity.Accent)
		end
	end
end

local function selectKit(kit: KitConfig.Kit)
	if kit.Id == selectedId then return end

	local previous = cards[selectedId or ""]
	if previous then previous:SetSelected(false) end

	selectedId = kit.Id

	local selected = cards[kit.Id]
	if selected then selected:SetSelected(true) end

	paintInfo(true)
end

local function build()
	ordered = KitVisualService.SortByRarity(KitConfig.Entries, false)

	for order, kit in ordered do
		cards[kit.Id] = KitCard.new(template, kitsFrame, kit, order, selectKit)
	end

	selectedId = ordered[1] and ordered[1].Id
	local selected = cards[selectedId or ""]
	if selected then selected:SetSelected(true) end

	paintCards()
	paintInfo(false)
end

local function deal()
	dealGeneration += 1
	local generation = dealGeneration

	for order, kit in ordered do
		local card = cards[kit.Id]
		if card then card:Deal((order - 1) * CARD.Stagger) end
	end

	task.delay(0.05, function()
		if dealGeneration ~= generation then return end
		local kit = KitConfig.EntriesById[selectedId or ""]
		if kit then KitVisualService.FillDetails(infoStats, kit, true) end
	end)
end

local balanceColor = balance.TextColor3
local function flashBalance(success: boolean)
	balance.TextColor3 = if success then KitVisualService.Good else KitVisualService.Bad
	TweenService:Create(balance, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextColor3 = balanceColor,
	}):Play()
end

local function refreshBalance()
	balance.Text = `{KitConfig.Text.BalancePrefix}{MathService.Comma(KitStateService:GetGems())}`
	paintBuyButton()
	paintCards()
end

buyButton.Activated:Connect(function()
	if selectedId then KitStateService:Buy(selectedId) end
end)

inventoryButton.Activated:Connect(function()
	InterfaceService:Open("KitInventory")
end)

KitStateService.KitsChanged:Connect(function(result: string?)
	refreshBalance()
	if result == "Purchased" or result == "InsufficientGems" then
		flashBalance(result == "Purchased")
	end
end)

KitStateService.GemsChanged:Connect(refreshBalance)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then deal() end
end)

InterfaceService.WireMotion(buyButton)
InterfaceService.WireMotion(inventoryButton)
InterfaceService.WireMotion(robuxButton)

build()
refreshBalance()

return KitShopUIService
