local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local KitCard = require(ReplicatedStorage.Classes.KitCard)
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local KitStateService = require(ReplicatedStorage.Services.KitStateService)
local KitVisualService = require(ReplicatedStorage.Services.KitVisualService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local KitInventoryUIService = {}

if not RunService:IsClient() then
	return KitInventoryUIService
end

local CARD = KitConfig.Animation.Card
local INFO = KitConfig.Animation.Info
local TEXT = KitConfig.Text

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild("KitInventory") :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local kitsFrame = design:WaitForChild("KitsCanvas"):WaitForChild("Kits") :: ScrollingFrame
local template = kitsFrame:WaitForChild("Template") :: ImageButton
local info = design:WaitForChild("Info") :: Frame
local infoName = info:WaitForChild("KitName") :: TextLabel
local infoDescription = info:WaitForChild("KitDescription") :: TextLabel
local infoViewport = info:WaitForChild("Preview"):WaitForChild("ViewportFrame") :: ViewportFrame
local infoStats = info:WaitForChild("KitStats") :: Frame
local equipButton = info:WaitForChild("Equip") :: ImageButton
local equipLabel = equipButton:WaitForChild("TextLabel") :: TextLabel
local shopButton = design:WaitForChild("ShopButton") :: ImageButton
local shopButtonLabel = shopButton:WaitForChild("TextLabel") :: TextLabel

local cards: { [string]: KitCard.KitCard } = {}
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

local function paintEquipButton()
	local kit = selectedId and KitConfig.EntriesById[selectedId]
	if not kit then return end

	local isEquipped = KitStateService:GetEquipped() == kit.Id
	equipLabel.Text = if isEquipped then TEXT.Equipped else TEXT.Equip
	equipLabel.TextColor3 = if isEquipped then KitVisualService.Good else KitVisualService.Ink
	equipButton.Interactable = not isEquipped
end

local function paintInfo(animate: boolean)
	local kit = selectedId and KitConfig.EntriesById[selectedId]
	if not kit then return end

	local rarity = KitConfig.GetRarity(kit)
	infoName.Text = string.upper(kit.Name)
	infoName.TextColor3 = rarity.Accent
	infoDescription.Text = kit.Description
	KitVisualService.BuildPreview(infoViewport, KitVisualService.Showcase(kit))
	KitVisualService.FillDetails(infoStats, kit, animate)
	paintEquipButton()

	if animate then playInfoTransition() end
end

local function paintCards()
	local equipped = KitStateService:GetEquipped()

	for id, card in cards do
		local isEquipped = id == equipped
		card:SetStatus(
			if isEquipped then TEXT.Equipped else "",
			false,
			if isEquipped then KitVisualService.Good else nil
		)
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

local function rebuild()
	for _, card in cards do
		card:Destroy()
	end
	cards = {}

	local visible = {}
	for _, kit in KitConfig.Entries do
		if KitStateService:IsOwned(kit.Id) then table.insert(visible, kit) end
	end
	visible = KitVisualService.SortByRarity(visible, true)

	for order, kit in visible do
		cards[kit.Id] = KitCard.new(template, kitsFrame, kit, order, selectKit)
	end

	if not selectedId or not cards[selectedId] then
		selectedId = visible[1] and visible[1].Id
	end

	local selected = cards[selectedId or ""]
	if selected then selected:SetSelected(true) end

	paintCards()
	paintInfo(false)
end

local function deal()
	dealGeneration += 1
	local generation = dealGeneration

	local order = 0
	for _, kit in KitVisualService.SortByRarity(KitConfig.Entries, true) do
		local card = cards[kit.Id]
		if not card then continue end
		order += 1
		card:Deal((order - 1) * CARD.Stagger)
	end

	task.delay(0.05, function()
		if dealGeneration ~= generation then return end
		KitVisualService.FillDetails(infoStats, KitConfig.EntriesById[selectedId or ""] or KitConfig.Entries[1], true)
	end)
end

equipButton.Activated:Connect(function()
	if selectedId then KitStateService:Equip(selectedId) end
end)

local function destination(): string
	return if KitStateService:CanRoll() then "RollGui" else "KitsShop"
end

local function refreshNav()
	shopButtonLabel.Text = if KitStateService:CanRoll() then "ROLL" else "SHOP"
end

shopButton.Activated:Connect(function()
	InterfaceService:Open(destination())
end)

KitStateService.KitsChanged:Connect(function()
	refreshNav()
	rebuild()
end)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then deal() end
end)

InterfaceService.WireMotion(equipButton)
InterfaceService.WireMotion(shopButton)
refreshNav()
rebuild()

return KitInventoryUIService
