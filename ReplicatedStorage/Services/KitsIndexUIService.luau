local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local KitsIndexUIService = {}

if not RunService:IsClient() then
	return KitsIndexUIService
end

local KitCard = require(ReplicatedStorage.Classes.KitCard)
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local KitsIndexConfig = require(ReplicatedStorage.Configs.KitsIndexConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local KitStateService = require(ReplicatedStorage.Services.KitStateService)
local KitVisualService = require(ReplicatedStorage.Services.KitVisualService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local CARD = KitConfig.Animation.Card
local INFO = KitConfig.Animation.Info
local TEXT = KitConfig.Text
local HEADER = KitsIndexConfig.Header
local LOCK = KitsIndexConfig.Lock

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild(KitsIndexConfig.Gui) :: ScreenGui
local design = gui:WaitForChild(KitsIndexConfig.Root) :: Frame
local kitsFrame = design:WaitForChild("KitsCanvas"):WaitForChild("Kits") :: ScrollingFrame
local template = kitsFrame:WaitForChild("Template") :: ImageButton
local info = design:WaitForChild("Info") :: Frame
local infoName = info:WaitForChild("KitName") :: TextLabel
local infoDescription = info:WaitForChild("KitDescription") :: TextLabel
local infoPreview = info:WaitForChild("Preview") :: ImageLabel
local infoStats = info:WaitForChild("KitStats") :: Frame
local equipButton = info:WaitForChild("Equip") :: ImageButton
local equipLabel = equipButton:WaitForChild("TextLabel") :: TextLabel
local backButton = design:WaitForChild("BackButton") :: ImageButton

local cards: { [string]: KitCard.KitCard } = {}
local ordered: { KitConfig.Kit } = {}
local headers: { Frame } = {}
local selectedId: string? = nil
local dealGeneration = 0

template.Visible = false

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}
local infoPortrait: (ImageLabel | ViewportFrame)? = nil

local function playInfoTransition()
	TweenProxyService.CancelAll(infoTweens)

	infoName.TextTransparency = 1
	infoDescription.TextTransparency = 1
	if infoPortrait then infoPortrait.ImageTransparency = 1 end
	infoName.Position = infoNameBase + UDim2.fromScale(0, INFO.Rise)
	infoDescription.Position = infoDescriptionBase + UDim2.fromScale(0, INFO.Rise)

	local tweenInfo = TweenInfo.new(INFO.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	infoTweens = {
		TweenService:Create(infoName, tweenInfo, { TextTransparency = 0, Position = infoNameBase }),
		TweenService:Create(infoDescription, tweenInfo, { TextTransparency = 0, Position = infoDescriptionBase }),
	}
	if infoPortrait then
		table.insert(infoTweens, TweenService:Create(infoPortrait, tweenInfo, { ImageTransparency = 0 }))
	end
	for _, tween in infoTweens do tween:Play() end
end

local function paintEquipButton()
	local kit = selectedId and KitConfig.EntriesById[selectedId]
	if not kit then return end

	if not KitStateService:IsOwned(kit.Id) then
		equipLabel.Text = TEXT.Locked
		equipLabel.TextColor3 = KitVisualService.Muted
		equipButton.Interactable = false
		return
	end

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
	infoPortrait = KitVisualService.FillPortrait(infoPreview, kit)
	KitVisualService.FillDetails(infoStats, kit, animate)
	paintEquipButton()

	if animate then playInfoTransition() end
end

local function paintCards()
	local equipped = KitStateService:GetEquipped()

	for id, card in cards do
		local owned = KitStateService:IsOwned(id)
		local isEquipped = id == equipped
		local status = if isEquipped then TEXT.Equipped elseif owned then TEXT.Owned else TEXT.Locked
		local color = if isEquipped
			then KitVisualService.Good
			elseif owned then KitVisualService.Ink
			else KitVisualService.Muted
		card:SetStatus(status, not owned, color)
		KitVisualService.SetCardLocked(card.Button, not owned, LOCK)
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

local function addHeader(rarity, order: number)
	local frame = Instance.new("Frame")
	frame.Name = rarity.Id .. "Header"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(HEADER.Width, HEADER.Height)
	frame.LayoutOrder = order
	frame.Parent = kitsFrame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0, 0.5)
	label.Size = UDim2.fromScale(0.42, 0.9)
	label.BackgroundTransparency = 1
	label.FontFace = KitVisualService.BoldFont
	label.Text = string.upper(rarity.Name)
	label.TextColor3 = rarity.Accent
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = HEADER.MaxTextSize
	constraint.Parent = label

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(1, 0.5)
	rule.Position = UDim2.fromScale(1, 0.58)
	rule.Size = UDim2.fromScale(0.55, HEADER.RuleHeight)
	rule.BackgroundColor3 = rarity.Accent
	rule.BackgroundTransparency = HEADER.RuleTransparency
	rule.BorderSizePixel = 0
	rule.Parent = frame

	table.insert(headers, frame)
end

local function rarityOrder(): { any }
	local rarities = table.clone(KitConfig.Rarities)
	table.sort(rarities, function(a, b)
		return if KitsIndexConfig.RarestFirst then a.Order > b.Order else a.Order < b.Order
	end)
	return rarities
end

local function build()
	for _, card in cards do
		card:Destroy()
	end
	for _, header in headers do
		header:Destroy()
	end
	cards = {}
	headers = {}
	table.clear(ordered)

	local order = 0
	for _, rarity in rarityOrder() do
		local group = {}
		for _, kit in KitConfig.Entries do
			if kit.Rarity == rarity.Id then table.insert(group, kit) end
		end
		if #group == 0 then continue end

		table.sort(group, function(a, b)
			return a.Name < b.Name
		end)

		order += 1
		addHeader(rarity, order)

		for _, kit in group do
			order += 1
			cards[kit.Id] = KitCard.new(template, kitsFrame, kit, order, selectKit)
			table.insert(ordered, kit)
		end
	end

	if not selectedId or not cards[selectedId] then
		selectedId = ordered[1] and ordered[1].Id
	end

	local selected = cards[selectedId or ""]
	if selected then selected:SetSelected(true) end

	paintCards()
	paintInfo(false)
end

local function deal()
	dealGeneration += 1
	local generation = dealGeneration

	for index, kit in ordered do
		local card = cards[kit.Id]
		if card then card:Deal((index - 1) * CARD.Stagger) end
	end

	task.delay(0.05, function()
		if dealGeneration ~= generation then return end
		KitVisualService.FillDetails(infoStats, KitConfig.EntriesById[selectedId or ""] or KitConfig.Entries[1], true)
	end)
end

equipButton.Activated:Connect(function()
	if not selectedId or not KitStateService:IsOwned(selectedId) then return end
	KitStateService:Equip(selectedId)
end)

backButton.Activated:Connect(function()
	InterfaceService:Open("KitInventory")
end)

KitStateService.KitsChanged:Connect(function()
	paintCards()
	paintInfo(false)
end)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then deal() end
end)

InterfaceService.WireMotion(equipButton)
InterfaceService.WireMotion(backButton)
build()

return KitsIndexUIService
