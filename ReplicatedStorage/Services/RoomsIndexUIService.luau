local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RoomsIndexUIService = {}

if not RunService:IsClient() then
	return RoomsIndexUIService
end

local BadgeConfig = require(ReplicatedStorage.Configs.BadgeConfig)
local BadgeIconService = require(ReplicatedStorage.Services.BadgeIconService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local POIConfig = require(ReplicatedStorage.Configs.POIConfig)
local RoomsIndexConfig = require(ReplicatedStorage.Configs.RoomsIndexConfig)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local CARD = RoomsIndexConfig.Animation.Card
local BUTTON = RoomsIndexConfig.Animation.Button
local INFO = RoomsIndexConfig.Animation.Info
local PER_PAGE = RoomsIndexConfig.Columns * RoomsIndexConfig.Rows
local Entries = RoomsIndexConfig.Entries
local EntriesById = RoomsIndexConfig.EntriesById

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild(RoomsIndexConfig.Gui) :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local cardsFrame = design:WaitForChild("Cards") :: Frame
local cardTemplate = cardsFrame:WaitForChild("Template") :: Frame
local pagination = design:WaitForChild("Pagination") :: Frame
local prevButton = pagination:WaitForChild("Prev"):WaitForChild("Button") :: ImageButton
local nextButton = pagination:WaitForChild("Next"):WaitForChild("Button") :: ImageButton
local counter = design:WaitForChild("Counter") :: TextLabel
local info = design:WaitForChild("Info") :: Frame
local infoPhoto = info:WaitForChild("Photo") :: ImageLabel
local infoHidden = infoPhoto:WaitForChild("Hidden") :: TextLabel
local infoName = info:WaitForChild("RoomName") :: TextLabel
local infoDescription = info:WaitForChild("RoomDescription") :: TextLabel

local DiscoveredRemote = CommunicationService.Get(POIConfig.Remotes.Folder, POIConfig.Remotes.Discovered) :: RemoteEvent
local SyncRemote = CommunicationService.Get(POIConfig.Remotes.Folder, POIConfig.Remotes.Sync) :: RemoteEvent

type Card = {
	Id: string,
	Holder: Frame,
	Button: ImageButton,
	Photo: ImageLabel,
	Hidden: TextLabel,
	Caption: TextLabel,
	Pin: ImageLabel,
	Hovered: boolean,
	Pressed: boolean,
	Tween: Tween?,
}

type Chrome = {
	Button: ImageButton,
	Base: UDim2,
	Hovered: boolean,
	Pressed: boolean,
	Enabled: boolean,
	Tween: Tween?,
}

local Cards: { [string]: Card } = {}
local Discovered: { [string]: boolean } = {}
local selectedId: string? = nil
local currentPage = 1
local dealGeneration = 0
local prevChrome: Chrome? = nil
local nextChrome: Chrome? = nil

function RoomsIndexUIService:IsDiscovered(id: string): boolean
	return Discovered[id] == true
end

function RoomsIndexUIService:GetDiscoveredCount(): number
	local count = 0
	for _, entry in Entries do
		if Discovered[entry.Id] then
			count += 1
		end
	end
	return count
end

function RoomsIndexUIService:GetSelected(): string?
	return selectedId
end

function RoomsIndexUIService:GetPage(): number
	return currentPage
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

	if card.Tween then
		card.Tween:Cancel()
	end
	card.Tween = TweenService:Create(card.Button, override or TweenInfo.new(duration, style, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(scale, scale),
		Position = UDim2.fromScale(0.5, 0.5 - lift),
		Rotation = tilt,
	})
	card.Tween:Play()
end

local function roomPhoto(entry: RoomsIndexConfig.Entry): string
	local badgeId = BadgeConfig.Rooms[entry.Id]
	local icon = BadgeIconService:Peek(badgeId)
	if icon then return icon end

	BadgeIconService:Fetch(badgeId, function(resolved: string)
		if resolved == "" or not Discovered[entry.Id] then return end
		local card = Cards[entry.Id]
		if card then
			card.Photo.Image = resolved
		end
		if selectedId == entry.Id then
			infoPhoto.Image = resolved
		end
	end)
	return ""
end

local function paintCard(card: Card)
	local entry = EntriesById[card.Id]
	local discovered = Discovered[card.Id] == true
	card.Photo.Image = if discovered then roomPhoto(entry) else ""
	card.Hidden.Visible = not discovered
	card.Caption.Text = if discovered then string.upper(entry.Name) else RoomsIndexConfig.Locked.CardName
	card.Pin.Visible = card.Id == selectedId
end

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}

local function playInfoTransition()
	TweenProxyService.CancelAll(infoTweens)

	infoName.TextTransparency = 1
	infoDescription.TextTransparency = 1
	infoPhoto.ImageTransparency = 1
	infoName.Position = infoNameBase + UDim2.fromScale(0, INFO.Rise)
	infoDescription.Position = infoDescriptionBase + UDim2.fromScale(0, INFO.Rise)

	local tweenInfo = TweenInfo.new(INFO.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	infoTweens = {
		TweenService:Create(infoName, tweenInfo, { TextTransparency = 0, Position = infoNameBase }),
		TweenService:Create(infoDescription, tweenInfo, { TextTransparency = 0, Position = infoDescriptionBase }),
		TweenService:Create(infoPhoto, tweenInfo, { ImageTransparency = 0 }),
	}
	for _, tween in infoTweens do
		tween:Play()
	end
end

local function paintInfo(animate: boolean)
	local entry = selectedId and EntriesById[selectedId]
	if not entry then
		infoPhoto.Image = ""
		infoHidden.Visible = true
		infoName.Text = RoomsIndexConfig.Empty.Name
		infoDescription.Text = RoomsIndexConfig.Empty.Description
		return
	end

	local discovered = Discovered[entry.Id] == true
	infoPhoto.Image = if discovered then roomPhoto(entry) else ""
	infoHidden.Visible = not discovered
	infoName.Text = if discovered then string.upper(entry.Name) else RoomsIndexConfig.Locked.Name
	infoDescription.Text = if discovered then entry.Description else RoomsIndexConfig.Locked.Description
	if animate then
		playInfoTransition()
	end
end

local function paintCounter()
	counter.Text = string.format(RoomsIndexConfig.CounterText, RoomsIndexUIService:GetDiscoveredCount(), #Entries)
end

local function poseChrome(chrome: Chrome)
	local scale = 1
	local duration = BUTTON.SettleTime

	if not chrome.Enabled then
		scale = BUTTON.DisabledScale
	elseif chrome.Pressed then
		scale, duration = BUTTON.PressScale, BUTTON.PressTime
	elseif chrome.Hovered then
		scale, duration = BUTTON.HoverScale, BUTTON.HoverTime
	end

	if chrome.Tween then
		chrome.Tween:Cancel()
	end
	local base = chrome.Base
	chrome.Tween = TweenService:Create(chrome.Button, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(base.X.Scale * scale, base.X.Offset * scale, base.Y.Scale * scale, base.Y.Offset * scale),
	})
	chrome.Tween:Play()
end

local function wireChrome(button: ImageButton): Chrome
	button.AutoButtonColor = false
	local chrome: Chrome = {
		Button = button,
		Base = button.Size,
		Hovered = false,
		Pressed = false,
		Enabled = true,
	}

	button.MouseEnter:Connect(function()
		chrome.Hovered = true
		poseChrome(chrome)
	end)
	button.MouseLeave:Connect(function()
		chrome.Hovered = false
		chrome.Pressed = false
		poseChrome(chrome)
	end)
	button.MouseButton1Down:Connect(function()
		chrome.Pressed = true
		poseChrome(chrome)
	end)
	button.MouseButton1Up:Connect(function()
		chrome.Pressed = false
		poseChrome(chrome)
	end)

	return chrome
end

local function pageCount(): number
	return math.max(1, math.ceil(#Entries / PER_PAGE))
end

local function currentSlice(): { RoomsIndexConfig.Entry }
	local first = (currentPage - 1) * PER_PAGE
	local slice = {}
	for index = first + 1, math.min(first + PER_PAGE, #Entries) do
		table.insert(slice, Entries[index])
	end
	return slice
end

local function dealPage()
	dealGeneration += 1
	local generation = dealGeneration
	for offset, entry in currentSlice() do
		local card = Cards[entry.Id]
		if not card then continue end
		if card.Tween then
			card.Tween:Cancel()
		end
		card.Button.Size = UDim2.fromScale(CARD.EnterScale, CARD.EnterScale)
		card.Button.Position = UDim2.fromScale(0.5, 0.5 + CARD.EnterDrop)
		card.Button.Rotation = 0
		task.delay((offset - 1) * CARD.Stagger, function()
			if dealGeneration ~= generation then return end
			poseCard(card, TweenInfo.new(CARD.EnterTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		end)
	end
end

local function applyPage()
	local pages = pageCount()
	currentPage = math.clamp(currentPage, 1, pages)

	local showing: { [string]: boolean } = {}
	for _, entry in currentSlice() do
		showing[entry.Id] = true
	end
	for id, card in Cards do
		card.Holder.Visible = showing[id] == true
		poseCard(card)
	end

	local colors = RoomsIndexConfig.Pagination
	local canGoBack = currentPage > 1
	local canGoForward = currentPage < pages
	prevButton.ImageColor3 = if canGoBack then colors.Enabled else colors.Disabled
	nextButton.ImageColor3 = if canGoForward then colors.Enabled else colors.Disabled
	prevButton.Interactable = canGoBack
	nextButton.Interactable = canGoForward
	if prevChrome then
		prevChrome.Enabled = canGoBack
		poseChrome(prevChrome)
	end
	if nextChrome then
		nextChrome.Enabled = canGoForward
		poseChrome(nextChrome)
	end
end

function RoomsIndexUIService:Select(id: string?)
	if id and not EntriesById[id] then return end
	local previous = selectedId and Cards[selectedId]
	selectedId = id
	if previous then
		paintCard(previous)
		poseCard(previous)
	end
	local selected = selectedId and Cards[selectedId]
	if selected then
		paintCard(selected)
		poseCard(selected)
	end
	paintInfo(true)
end

function RoomsIndexUIService:SetPage(page: number)
	local pages = pageCount()
	local clamped = math.clamp(page, 1, pages)
	if clamped == currentPage then return end
	currentPage = clamped
	applyPage()
	dealPage()
end

function RoomsIndexUIService:NextPage()
	self:SetPage(currentPage + 1)
end

function RoomsIndexUIService:PreviousPage()
	self:SetPage(currentPage - 1)
end

function RoomsIndexUIService:Refresh()
	for _, card in Cards do
		paintCard(card)
	end
	paintInfo(false)
	paintCounter()
end

function RoomsIndexUIService:SetDiscovered(set: { [string]: any })
	table.clear(Discovered)
	for name, value in set do
		if type(name) == "string" and value then
			Discovered[name] = true
		end
	end
	self:Refresh()
end

function RoomsIndexUIService:MarkDiscovered(name: string)
	if Discovered[name] then return end
	Discovered[name] = true
	self:Refresh()
end

local function buildCard(index: number, entry: RoomsIndexConfig.Entry)
	local holder = cardTemplate:Clone()
	holder.Name = entry.Id
	holder.LayoutOrder = index
	holder.Visible = false
	holder.Parent = cardsFrame

	local button = holder:FindFirstChild("Card") :: ImageButton
	local photo = button:FindFirstChild("Photo") :: ImageLabel
	local card: Card = {
		Id = entry.Id,
		Holder = holder,
		Button = button,
		Photo = photo,
		Hidden = photo:FindFirstChild("Hidden") :: TextLabel,
		Caption = button:FindFirstChild("Caption") :: TextLabel,
		Pin = button:FindFirstChild("Pin") :: ImageLabel,
		Hovered = false,
		Pressed = false,
	}
	Cards[entry.Id] = card
	button.AutoButtonColor = false
	paintCard(card)

	button.Activated:Connect(function()
		RoomsIndexUIService:Select(entry.Id)
	end)
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
end

local function build()
	local badgeIds = {}
	for index, entry in Entries do
		table.insert(badgeIds, BadgeConfig.Rooms[entry.Id])
		buildCard(index, entry)
	end
	BadgeIconService:Prefetch(badgeIds)
	cardTemplate.Visible = false

	prevChrome = wireChrome(prevButton)
	nextChrome = wireChrome(nextButton)
	prevButton.Activated:Connect(function()
		RoomsIndexUIService:PreviousPage()
	end)
	nextButton.Activated:Connect(function()
		RoomsIndexUIService:NextPage()
	end)

	selectedId = Entries[1] and Entries[1].Id
	applyPage()
	RoomsIndexUIService:Refresh()

	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			dealPage()
		end
	end)
end

build()

DiscoveredRemote.OnClientEvent:Connect(function(name: any)
	if type(name) == "string" then
		RoomsIndexUIService:MarkDiscovered(name)
	end
end)

SyncRemote.OnClientEvent:Connect(function(set: any)
	if type(set) == "table" then
		RoomsIndexUIService:SetDiscovered(set)
	end
end)

SyncRemote:FireServer()

return RoomsIndexUIService
