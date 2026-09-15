local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InventoryCard = require(ReplicatedStorage.Classes.InventoryCard)
local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)
local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local InventoryUIService = require(ReplicatedStorage.Services.InventoryUIService)
local ItemPreviewService = require(ReplicatedStorage.Services.ItemPreviewService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local InventoryPageUIService = {}

if not RunService:IsClient() then
	return InventoryPageUIService
end

local PAGE = InventoryConfig.Page
local TEXT = PAGE.Text
local CARD = ItemShopConfig.Animation.Card
local INFO = ItemShopConfig.Animation.Info
local HOTBAR = InventoryConfig.HotbarSlots
local CAPACITY = HOTBAR + InventoryConfig.BackpackSlots

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild(PAGE.Gui) :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local itemsFrame = design:WaitForChild("Items") :: ScrollingFrame
local template = itemsFrame:WaitForChild("Template") :: ImageButton
local hotbarFrame = design:WaitForChild("Hotbar") :: Frame
local info = design:WaitForChild("Info") :: Frame
local infoName = info:WaitForChild("ItemName") :: TextLabel
local infoDescription = info:WaitForChild("ItemDescription") :: TextLabel
local infoViewport = info:WaitForChild("Preview"):WaitForChild("ViewportFrame") :: ViewportFrame
local moveButton = info:WaitForChild("MoveButton") :: ImageButton
local moveLabel = moveButton:WaitForChild("TextLabel") :: TextLabel

local dragGui = GuiBuilderService.CreateScreenGui(PAGE.DragGui, PAGE.DragGuiDisplayOrder)

local hotbarSlots: { Frame } = {}
local slotStrokes: { UIStroke } = {}
for index = 1, HOTBAR do
	local slot = hotbarFrame:WaitForChild(`Slot{index}`) :: Frame
	hotbarSlots[index] = slot

	local stroke = GuiBuilderService.Stroke(slot, PAGE.DropStrokeColor, PAGE.DropStrokeThickness)
	stroke.Transparency = 1
	slotStrokes[index] = stroke
end

template.Visible = false

local cards: { [number]: InventoryCard.InventoryCard } = {}
local selectedIndex: number? = nil
local dealGeneration = 0
local noticeToken = 0
local moveLabelColor = moveLabel.TextColor3

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}

local drag = nil :: {
	Card: InventoryCard.InventoryCard,
	Origin: Vector2,
	Started: boolean,
	Ghost: ImageButton?,
	Target: number?,
}?

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

local function selectedEntry(): InventoryUIService.Entry?
	if not selectedIndex then return nil end
	return InventoryUIService:GetEntry(selectedIndex)
end

local function paintMoveButton()
	noticeToken += 1
	local entry = selectedEntry()

	if not entry then
		moveLabel.Text = ""
		moveButton.Visible = false
		moveButton.Interactable = false
		return
	end

	moveButton.Visible = true
	moveButton.Interactable = true
	moveLabel.TextColor3 = moveLabelColor
	moveLabel.Text = if InventoryUIService:IsHotbarSlot(entry.Slot) then TEXT.ToBag else TEXT.ToHotbar
end

local function notice(text: string)
	noticeToken += 1
	local token = noticeToken

	moveLabel.Text = text
	moveLabel.TextColor3 = PAGE.Bad

	task.delay(PAGE.NoticeTime, function()
		if token ~= noticeToken then return end
		paintMoveButton()
	end)
end

local function paintInfo(animate: boolean)
	local entry = selectedEntry()

	if not entry then
		infoName.Text = TEXT.Empty
		infoDescription.Text = TEXT.EmptyDescription
		ItemPreviewService:Clear(infoViewport)
		paintMoveButton()
		return
	end

	local shopEntry = ItemShopConfig.EntriesById[entry.Name]
	local name = if shopEntry then shopEntry.Name else entry.Name
	local suffix = if entry.Quantity > 1 then ` x{entry.Quantity}` else ""

	infoName.Text = string.upper(name) .. suffix
	infoDescription.Text = if shopEntry then shopEntry.Description else ""
	ItemPreviewService:Render(infoViewport, entry.Name)
	paintMoveButton()

	if animate then playInfoTransition() end
end

local function paintSlotStrokes()
	local target = drag and drag.Target
	for index, stroke in slotStrokes do
		if target == index then
			stroke.Color = PAGE.DropStrokeColor
			stroke.Transparency = 0
		elseif selectedIndex == index and cards[index] then
			stroke.Color = PAGE.SelectStrokeColor
			stroke.Transparency = 0
		else
			stroke.Transparency = 1
		end
	end
end

local function selectSlot(index: number?, animate: boolean)
	if index == selectedIndex then return end

	local previous = cards[selectedIndex or 0]
	if previous then previous:SetSelected(false) end

	selectedIndex = index

	local selected = cards[index or 0]
	if selected then selected:SetSelected(true) end

	paintSlotStrokes()
	paintInfo(animate)
end

local function onSelect(card: InventoryCard.InventoryCard)
	selectSlot(card.Index, true)
end

local function onPress(card: InventoryCard.InventoryCard, input: InputObject)
	if drag then return end
	if
		input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch
	then
		return
	end

	drag = {
		Card = card,
		Origin = Vector2.new(input.Position.X, input.Position.Y),
		Started = false,
	}
end

local function rebuild()
	for _, card in cards do
		card:Destroy()
	end
	cards = {}

	local snapshot = InventoryUIService:GetSnapshot()
	local order = 0
	for index = 1, CAPACITY do
		local entry = snapshot[index]
		if not entry then continue end

		local isHotbar = InventoryUIService:IsHotbarSlot(index)
		order += 1
		cards[index] = InventoryCard.new(
			template,
			if isHotbar then hotbarSlots[index] else itemsFrame,
			entry,
			order,
			onSelect,
			onPress,
			isHotbar
		)
	end

	if not selectedIndex or not cards[selectedIndex] then
		selectedIndex = nil
		for index = 1, CAPACITY do
			if cards[index] then
				selectedIndex = index
				break
			end
		end
	end

	local selected = cards[selectedIndex or 0]
	if selected then selected:SetSelected(true) end

	paintSlotStrokes()
	paintInfo(false)
end

local function deal()
	dealGeneration += 1
	local generation = dealGeneration

	local order = 0
	for index = 1, CAPACITY do
		local card = cards[index]
		if not card then continue end
		order += 1
		card:Deal((order - 1) * CARD.Stagger)
	end

	task.delay(0.05, function()
		if dealGeneration ~= generation then return end
		paintInfo(true)
	end)
end

local function contains(object: GuiObject, point: Vector2): boolean
	local topLeft = object.AbsolutePosition
	local size = object.AbsoluteSize
	return point.X >= topLeft.X
		and point.X <= topLeft.X + size.X
		and point.Y >= topLeft.Y
		and point.Y <= topLeft.Y + size.Y
end

local function slotAt(point: Vector2): number?
	for index, slot in hotbarSlots do
		if contains(slot, point) then return index end
	end
	return nil
end

local function threshold(input: InputObject): number
	return if input.UserInputType == Enum.UserInputType.Touch
		then InventoryConfig.TouchDragThreshold
		else InventoryConfig.DragThreshold
end

local function setTarget(index: number?)
	if not drag or drag.Target == index then return end
	drag.Target = index
	paintSlotStrokes()
end

local function beginDrag(position: Vector3)
	if not drag then return end
	local card = drag.Card
	drag.Started = true

	local holderSize = hotbarSlots[1].AbsoluteSize
	local ghost = card.Button:Clone()
	ghost.Name = "DragGhost"
	local aspect = ghost:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then aspect:Destroy() end
	ghost.Visible = true
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Rotation = 0
	ghost.Size = UDim2.fromOffset(holderSize.X, holderSize.Y)
	ghost.Position = UDim2.fromOffset(position.X, position.Y)
	ghost.ImageTransparency = InventoryConfig.Transparency.Dragging
	ghost.ZIndex = PAGE.GhostZIndex
	ghost.Active = false
	ghost.Interactable = false
	ghost.Parent = dragGui

	local viewport = ghost:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		ItemPreviewService:Render(viewport, card.ToolName)
	end

	drag.Ghost = ghost
	card:SetDragging(true)
end

local function updateDrag(position: Vector3)
	if not drag or not drag.Ghost then return end
	drag.Ghost.Position = UDim2.fromOffset(position.X, position.Y)

	local target = slotAt(Vector2.new(position.X, position.Y))
	setTarget(if target ~= drag.Card.Index then target else nil)
end

local function endDrag(position: Vector3?)
	if not drag then return end
	local card = drag.Card
	local started = drag.Started

	if drag.Ghost then
		local viewport = drag.Ghost:FindFirstChild("ViewportFrame")
		if viewport and viewport:IsA("ViewportFrame") then
			ItemPreviewService:Clear(viewport)
		end
		drag.Ghost:Destroy()
	end
	setTarget(nil)
	card:SetDragging(false)
	drag = nil

	if not started or not position then return end

	local point = Vector2.new(position.X, position.Y)
	local target = slotAt(point)
	if target and target ~= card.Index then
		selectedIndex = target
		InventoryUIService:Move(card.Index, target)
		return
	end

	if InventoryUIService:IsHotbarSlot(card.Index) and contains(itemsFrame, point) then
		local free = InventoryUIService:FindFreeSlot(false)
		if not free then
			notice(TEXT.BagFull)
			return
		end
		selectedIndex = free
		InventoryUIService:Move(card.Index, free)
	end
end

local function moveSelected()
	local entry = selectedEntry()
	if not entry then return end

	local toHotbar = not InventoryUIService:IsHotbarSlot(entry.Slot)
	local free = InventoryUIService:FindFreeSlot(toHotbar)
	if not free then
		notice(if toHotbar then TEXT.HotbarFull else TEXT.BagFull)
		return
	end

	selectedIndex = free
	InventoryUIService:Move(entry.Slot, free)
end

local function togglePage()
	if InterfaceService:GetActive() == PAGE.Id then
		InterfaceService:Close()
	else
		InterfaceService:Open(PAGE.Id)
	end
end

moveButton.Activated:Connect(moveSelected)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if not drag then return end
	if
		input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch
	then
		return
	end

	if not drag.Started then
		local travelled = (Vector2.new(input.Position.X, input.Position.Y) - drag.Origin).Magnitude
		if travelled < threshold(input) then return end
		beginDrag(input.Position)
	end

	updateDrag(input.Position)
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if not drag then return end
	if
		input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch
	then
		return
	end

	endDrag(input.Position)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if not table.find(InventoryConfig.ToggleKeys, input.KeyCode) then return end
	togglePage()
end)

InventoryUIService.Changed:Connect(rebuild)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	InventoryUIService:SetHotbarVisible(not gui.Enabled)
	if gui.Enabled then
		deal()
	else
		endDrag(nil)
	end
end)

InterfaceService.WireMotion(moveButton)
rebuild()

return InventoryPageUIService
