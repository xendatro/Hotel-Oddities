local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FriendAvatar = require(ReplicatedStorage.Services.FriendAvatarService)
local IndexConfig = require(ReplicatedStorage.Configs.IndexConfig)
local Redaction = require(ReplicatedStorage.Services.RedactionService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local IndexUIService = {}

if not RunService:IsClient() then
	return IndexUIService
end

local DeathScreenService = require(ReplicatedStorage.Services.DeathScreenService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)

local HEADSHOT = IndexConfig.Headshot
local LOCKED = IndexConfig.Locked
local DISCOVERY = IndexConfig.Discovery
local REVEAL = IndexConfig.Discovery.Reveal
local PER_PAGE = IndexConfig.EntriesPerPage

local INTERFACE_PAGE = "Index"
local CARD = IndexConfig.Animation.Card
local BUTTON = IndexConfig.Animation.Button
local PAGE = IndexConfig.Animation.Page
local INFO = IndexConfig.Animation.Info

local playerGui = GuiBuilderService.GetPlayerGui()

type Card = {
	Id: string,
	Holder: Frame,
	Button: ImageButton,
	Label: TextLabel,
	LabelColor: Color3,
	Marker: ImageLabel,
	MarkerSize: UDim2,
	Viewport: ViewportFrame,
	Hovered: boolean,
	Pressed: boolean,
	Tween: Tween?,
	Connections: { RBXScriptConnection },
}

local Cards: { [string]: Card } = {}
local Progress: { [string]: number } = {}
local Listed: { string } = {}

type Reveal = {
	Id: string,
	Progress: number,
	Order: { number },
	Started: { [number]: number },
	Token: number,
}
local RevealState: Reveal? = nil
local revealToken = 0

local selectedId: string? = nil
local currentPage = 1

local Entries = IndexConfig.Entries
local EntriesById: { [string]: IndexConfig.Entry } = {}
for _, entry in Entries do
	EntriesById[entry.Id] = entry
end

local gui = playerGui:WaitForChild("IndexGui", 10) :: ScreenGui?
local design = gui and gui:WaitForChild("Design", 5) :: Frame?

if not design then
	warn("[IndexUIService] IndexGui.Design is missing; the index will not be wired up.")
	return IndexUIService
end

local cardsFrame = design:WaitForChild("Cards") :: Frame
local cardTemplate = cardsFrame:WaitForChild("Template") :: Frame
local pagination = design:WaitForChild("Pagination") :: Frame
local prevButton = pagination:WaitForChild("Prev"):WaitForChild("Button") :: ImageButton
local nextButton = pagination:WaitForChild("Next"):WaitForChild("Button") :: ImageButton
local closeButton = design:FindFirstChild("CloseButton") :: ImageButton?
local infoPanel = design:WaitForChild("InfoPanel") :: Frame
local infoName = infoPanel:WaitForChild("Name") :: TextLabel
local infoDescription = infoPanel:WaitForChild("Description") :: TextLabel
local infoHeadshot = infoPanel:WaitForChild("PostIt"):WaitForChild("Headshot") :: ViewportFrame

local templateSource: Instance? = nil
local warnedAboutFallback = false

local function resolveTemplateSource(): Instance?
	if templateSource and templateSource.Parent then return templateSource end

	local replicated = ReplicatedStorage:FindFirstChild(IndexConfig.TemplateFolder)
	if replicated then
		templateSource = replicated
		return replicated
	end

	local best, bestScore = nil, 0
	for _, folder in workspace:GetChildren() do
		if folder.Name ~= IndexConfig.TemplateFolder then continue end

		local score = 0
		for _, entry in Entries do
			if folder:FindFirstChild(entry.Model) then
				score += 1
			end
		end
		if score > bestScore then
			best, bestScore = folder, score
		end
	end

	if best and not warnedAboutFallback then
		warnedAboutFallback = true
		warn(
			("[IndexUIService] No ReplicatedStorage.%s; reading headshot models from %s instead. "):format(
				IndexConfig.TemplateFolder,
				best:GetFullName()
			) .. "EnemyService clones from ReplicatedStorage, so it cannot spawn anything from there."
		)
	end

	templateSource = best
	return best
end

local function findFocus(model: Model, headshot: IndexConfig.Headshot?): BasePart?
	local named = headshot and headshot.Focus
	if named then
		local part = model:FindFirstChild(named, true)
		if part and part:IsA("BasePart") then return part end
	end

	local head = model:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then return head end

	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function buildStandin(parts: { IndexConfig.StandinPart }): Model
	local model = Instance.new("Model")
	model.Name = "Standin"

	for index, description in parts do
		local part = Instance.new("Part")
		part.Name = "Standin" .. index
		part.Shape = description.Shape or Enum.PartType.Ball
		part.Size = description.Size
		part.Color = description.Color or Color3.new(1, 1, 1)
		part.Material = description.Material or Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = CFrame.new(description.Offset or Vector3.zero)
		part.Parent = model
	end

	return model
end

local function clearViewport(viewport: ViewportFrame)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
end

local function applyTransparency(model: Model, transparency: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = math.max(descendant.Transparency, transparency)
		end
	end
end

local function paintHeadshot(model: Model, color: Color3, material: Enum.Material)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = color
			descendant.Material = material
			descendant.Transparency = 0
			descendant.CastShadow = false
		end

		if descendant:IsA("MeshPart") then
			descendant.TextureID = ""
		elseif descendant:IsA("SpecialMesh") then
			descendant.TextureId = ""
		elseif descendant:IsA("Decal")
			or descendant:IsA("Texture")
			or descendant:IsA("SurfaceAppearance")
			or descendant:IsA("Shirt")
			or descendant:IsA("Pants")
			or descendant:IsA("ShirtGraphic")
			or descendant:IsA("BodyColors")
		then
			descendant:Destroy()
		end
	end
end

local function measure(model: Model, headshot: IndexConfig.Headshot): (Vector3?, Vector3?)
	if headshot.Standin then
		local box, size = model:GetBoundingBox()
		return box.Position, size
	end

	local focus = findFocus(model, headshot)
	if not focus then return nil, nil end
	return focus.Position, focus.Size
end

local function present(viewport: ViewportFrame, model: Model, headshot: IndexConfig.Headshot)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.AutoRotate = false
	end

	if headshot.Transparency then
		applyTransparency(model, headshot.Transparency)
	end

	model:PivotTo(CFrame.identity)

	local target, extent = measure(model, headshot)
	if not target or not extent then
		model:Destroy()
		return
	end

	if headshot.Color then
		paintHeadshot(model, headshot.Color, headshot.Material or Enum.Material.SmoothPlastic)
	end

	clearViewport(viewport)
	model.Parent = viewport

	local yaw = headshot.Yaw or HEADSHOT.Yaw
	local pitch = headshot.Pitch or HEADSHOT.Pitch
	local zoom = headshot.Zoom or HEADSHOT.Zoom

	local radius = math.max(extent.X, extent.Y, extent.Z) * 0.5 * HEADSHOT.Padding
	local distance = (radius / math.tan(math.rad(HEADSHOT.FieldOfView) * 0.5)) * zoom

	local facing = model:GetPivot().Rotation
	local direction = (facing * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)).LookVector
	local aim = target + facing:VectorToWorldSpace(headshot.Offset or Vector3.zero)

	local camera = Instance.new("Camera")
	camera.FieldOfView = HEADSHOT.FieldOfView
	camera.CFrame = CFrame.lookAt(aim + direction * distance, aim)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local Generations: { [ViewportFrame]: number } = {}

local function buildHeadshot(viewport: ViewportFrame, entry: IndexConfig.Entry)
	local headshot = entry.Headshot or {}

	local generation = (Generations[viewport] or 0) + 1
	Generations[viewport] = generation

	if headshot.Standin then
		present(viewport, buildStandin(headshot.Standin), headshot)
	else
		local source = resolveTemplateSource()
		local template = source and source:FindFirstChild(entry.Model)
		if not template or not template:IsA("Model") then
			clearViewport(viewport)
			warn(("[IndexUIService] No model named %q for index entry %q."):format(entry.Model, entry.Id))
		else
			present(viewport, template:Clone(), headshot)
		end
	end

	if not headshot.WearFriendAvatar then return end

	task.spawn(function()
		local rig = FriendAvatar.Build(entry.Id)
		if not rig then return end

		if Generations[viewport] ~= generation or not viewport.Parent then
			rig:Destroy()
			return
		end

		present(viewport, rig, headshot)
	end)
end

local function poseCard(card: Card, override: TweenInfo?)
	local scale, lift, tilt = 1, 0, 0
	local duration, style, direction = CARD.SettleTime, CARD.Style, CARD.Direction

	if card.Pressed then
		scale, lift, tilt = CARD.PressScale, 0, CARD.PressTilt
		duration, style, direction = CARD.PressTime, CARD.PressStyle, CARD.PressDirection
	elseif card.Hovered then
		scale, lift, tilt = CARD.HoverScale, CARD.HoverLift, CARD.HoverTilt
		duration = CARD.HoverTime
	elseif card.Id == selectedId then
		scale, lift, tilt = CARD.SelectedScale, CARD.SelectedLift, CARD.SelectedTilt
	end

	if card.Tween then
		card.Tween:Cancel()
	end

	local tween = TweenService:Create(card.Button, override or TweenInfo.new(duration, style, direction), {
		Size = UDim2.fromScale(scale, scale),
		Position = UDim2.fromScale(0.5, 0.5 - lift),
		Rotation = tilt,
	})
	card.Tween = tween
	tween:Play()
end

local pageGeneration = 0

local function dealPage(ids: { string })
	pageGeneration += 1
	local generation = pageGeneration

	for offset, id in ids do
		local card = Cards[id]
		if not card then continue end

		if card.Tween then
			card.Tween:Cancel()
		end
		card.Button.Size = UDim2.fromScale(PAGE.EnterScale, PAGE.EnterScale)
		card.Button.Position = UDim2.fromScale(0.5, 0.5 + PAGE.EnterDrop)
		card.Button.Rotation = 0

		task.delay((offset - 1) * PAGE.Stagger, function()
			if pageGeneration ~= generation then return end
			poseCard(card, TweenInfo.new(PAGE.EnterTime, CARD.Style, CARD.Direction))
		end)
	end
end

type Chrome = {
	Button: ImageButton,
	Base: UDim2,
	Hovered: boolean,
	Pressed: boolean,
	Enabled: boolean,
	Tween: Tween?,
}

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
	local tween = TweenService:Create(chrome.Button, TweenInfo.new(duration, BUTTON.Style, BUTTON.Direction), {
		Size = UDim2.new(
			base.X.Scale * scale,
			base.X.Offset * scale,
			base.Y.Scale * scale,
			base.Y.Offset * scale
		),
	})
	chrome.Tween = tween
	tween:Play()
end

local prevChrome: Chrome? = nil
local nextChrome: Chrome? = nil

local function wireChrome(button: ImageButton): Chrome
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

function IndexUIService:GetProgress(id: string): number
	return Progress[id] or 0
end

function IndexUIService:IsDiscovered(id: string): boolean
	return IndexUIService:GetProgress(id) > DISCOVERY.NamedAbove
end

local function descriptionFor(
	entry: IndexConfig.Entry,
	progress: number,
	suppress: { [number]: boolean }?,
	colors: { [number]: Color3 }?
): string
	if progress <= DISCOVERY.NamedAbove then return LOCKED.Description end

	return Redaction.Render(entry.Description, entry.Id, progress, {
		Rich = true,
		HiddenColor = DISCOVERY.HiddenColor,
		BlockRatio = DISCOVERY.BlockRatio,
		Suppress = suppress,
		Colors = colors,
	})
end

local LIT = HEADSHOT.Tint

local function paintCard(entry: IndexConfig.Entry)
	local card = Cards[entry.Id]
	if not card then return end

	local discovered = IndexUIService:IsDiscovered(entry.Id)

	card.Label.Text = discovered and string.upper(entry.Name) or LOCKED.CardName
	card.Label.TextColor3 = discovered and card.LabelColor or LOCKED.CardTextColor

	card.Viewport.ImageColor3 = discovered and LIT or LOCKED.Tint
	card.Viewport.Visible = discovered or LOCKED.ShowSilhouette

	card.Button.ImageColor3 = discovered and LIT or LOCKED.CardTint
end

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}

local infoHeadshotId: string? = nil

local function playInfoTransition()
	TweenProxyService.CancelAll(infoTweens)

	infoName.TextTransparency = 1
	infoDescription.TextTransparency = 1
	infoHeadshot.ImageTransparency = 1
	infoName.Position = infoNameBase + UDim2.fromScale(0, INFO.Rise)
	infoDescription.Position = infoDescriptionBase + UDim2.fromScale(0, INFO.Rise)

	local info = TweenInfo.new(INFO.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	infoTweens = {
		TweenService:Create(infoName, info, { TextTransparency = 0, Position = infoNameBase }),
		TweenService:Create(infoDescription, info, { TextTransparency = 0, Position = infoDescriptionBase }),
		TweenService:Create(infoHeadshot, info, { ImageTransparency = 0 }),
	}
	for _, tween in infoTweens do
		tween:Play()
	end
end

local function settleInfo()
	TweenProxyService.CancelAll(infoTweens)

	infoName.TextTransparency = 0
	infoDescription.TextTransparency = 0
	infoHeadshot.ImageTransparency = 0
	infoName.Position = infoNameBase
	infoDescription.Position = infoDescriptionBase
end

local function renderReveal(state: Reveal, now: number): (string, boolean)
	local entry = EntriesById[state.Id]
	if not entry then return "", true end

	local body = infoDescription.TextColor3
	local suppress: { [number]: boolean } = {}
	local colors: { [number]: Color3 } = {}
	local finished = true

	for _, position in state.Order do
		local started = state.Started[position]

		if not started then
			suppress[position] = true
			finished = false
			continue
		end

		local age = now - started

		if age < REVEAL.ChargeTime then
			suppress[position] = true
			colors[position] = DISCOVERY.HiddenColor:Lerp(REVEAL.ChargeColor, age / REVEAL.ChargeTime)
			finished = false
			continue
		end

		local cooled = (age - REVEAL.ChargeTime) / REVEAL.SettleTime
		if cooled >= 1 then continue end
		finished = false

		if cooled < REVEAL.FlashFraction then
			colors[position] = REVEAL.ChargeColor:Lerp(DISCOVERY.NewColor, cooled / REVEAL.FlashFraction)
		else
			local rest = (cooled - REVEAL.FlashFraction) / (1 - REVEAL.FlashFraction)
			colors[position] = DISCOVERY.NewColor:Lerp(body, rest * rest)
		end
	end

	return descriptionFor(entry, state.Progress, suppress, colors), finished
end

local function paintInfo(animate: boolean?)
	local entry = selectedId and EntriesById[selectedId]

	if not entry then
		settleInfo()
		infoName.Text = IndexConfig.Empty.Name
		infoDescription.Text = IndexConfig.Empty.Description
		infoHeadshot.Visible = false
		infoHeadshotId = nil
		return
	end

	local progress = IndexUIService:GetProgress(entry.Id)
	local discovered = IndexUIService:IsDiscovered(entry.Id)

	infoName.Text = discovered and string.upper(entry.Name) or LOCKED.Name
	infoHeadshot.ImageColor3 = discovered and LIT or LOCKED.Tint
	infoHeadshot.Visible = discovered or LOCKED.ShowSilhouette

	if RevealState and RevealState.Id == entry.Id then
		infoDescription.Text = (renderReveal(RevealState, os.clock()))
	else
		infoDescription.Text = descriptionFor(entry, progress)
	end

	if infoHeadshotId ~= entry.Id then
		infoHeadshotId = entry.Id
		buildHeadshot(infoHeadshot, entry)
	end

	if animate then
		playInfoTransition()
	else
		settleInfo()
	end
end

local function pageCount(): number
	return math.max(1, math.ceil(#Listed / PER_PAGE))
end

local function currentSlice(): { string }
	local first = (currentPage - 1) * PER_PAGE
	local slice = {}
	for index = first + 1, math.min(first + PER_PAGE, #Listed) do
		table.insert(slice, Listed[index])
	end
	return slice
end

local function applyPage()
	local pages = pageCount()
	currentPage = math.clamp(currentPage, 1, pages)

	local showing: { [string]: boolean } = {}
	for _, id in currentSlice() do
		showing[id] = true
	end

	for id, card in Cards do
		card.Holder.Visible = showing[id] == true

		local selected = id == selectedId
		if selected and not card.Marker.Visible then
			card.Marker.Size = UDim2.new(0, 0, 0, 0)
			card.Marker.Visible = true
			TweenService:Create(
				card.Marker,
				TweenInfo.new(CARD.HoverTime, CARD.Style, CARD.Direction),
				{ Size = card.MarkerSize }
			):Play()
		elseif not selected then
			card.Marker.Visible = false
		end

		poseCard(card)
	end

	local colors = IndexConfig.Pagination
	local canGoBack = currentPage > 1
	local canGoForward = currentPage < pages

	prevButton.ImageColor3 = canGoBack and colors.Enabled or colors.Disabled
	nextButton.ImageColor3 = canGoForward and colors.Enabled or colors.Disabled
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

function IndexUIService:Refresh()
	local previous = table.concat(Listed, "\0")

	table.clear(Listed)
	for _, entry in Entries do
		if entry.Listed == false then continue end
		if IndexConfig.HideUndiscovered and not IndexUIService:IsDiscovered(entry.Id) then continue end
		table.insert(Listed, entry.Id)
	end
	local relisted = table.concat(Listed, "\0") ~= previous

	for _, entry in Entries do
		paintCard(entry)
	end

	if selectedId and not table.find(Listed, selectedId) then
		selectedId = Listed[1]
	elseif not selectedId then
		selectedId = Listed[1]
	end

	applyPage()

	if relisted then
		dealPage(currentSlice())
	end

	paintInfo(false)
end

function IndexUIService:SetPage(page: number)
	local target = math.clamp(page, 1, pageCount())
	if target == currentPage then return end

	currentPage = target
	applyPage()
	dealPage(currentSlice())
end

function IndexUIService:GetPage(): number
	return currentPage
end

function IndexUIService:NextPage()
	IndexUIService:SetPage(currentPage + 1)
end

function IndexUIService:PreviousPage()
	IndexUIService:SetPage(currentPage - 1)
end

function IndexUIService:Select(id: string?)
	if id and not EntriesById[id] then return end
	if id == selectedId then return end

	selectedId = id
	applyPage()
	paintInfo(true)
end

function IndexUIService:GetSelected(): string?
	return selectedId
end

function IndexUIService:SetProgress(id: string, progress: number)
	if not EntriesById[id] then return end

	local value = math.clamp(progress, 0, 1)
	if Progress[id] == value then return end

	Progress[id] = value > 0 and value or nil
	IndexUIService:Refresh()
end

function IndexUIService:SetProgressSet(set: { [string]: number })
	table.clear(Progress)
	for id, progress in set do
		if EntriesById[id] and type(progress) == "number" and progress > 0 then
			Progress[id] = math.clamp(progress, 0, 1)
		end
	end
	IndexUIService:Refresh()
end

function IndexUIService:GetProgressSet(): { [string]: number }
	return table.clone(Progress)
end

function IndexUIService:PlayReveal(id: string, before: number, after: number)
	local entry = EntriesById[id]
	if not entry then return end

	local gained = Redaction.NewlyVisible(entry.Description, entry.Id, before, after)
	if #gained == 0 then return end

	revealToken += 1
	local token = revealToken

	local state: Reveal = {
		Id = id,
		Progress = after,
		Order = gained,
		Started = {},
		Token = token,
	}
	RevealState = state

	task.spawn(function()
		local waitedUntil = os.clock() + REVEAL.DeathScreenTimeout
		while DeathScreenService:IsVisible() and os.clock() < waitedUntil do
			task.wait(0.1)
		end
		if revealToken ~= token then return end

		task.wait(REVEAL.AfterDeathDelay)
		if revealToken ~= token then return end

		InterfaceService:Open(INTERFACE_PAGE)
		IndexUIService:Select(id)
		paintInfo(false)

		task.wait(REVEAL.OpenDelay)
		if revealToken ~= token then return end

		local interval = math.min(REVEAL.WordInterval, REVEAL.MaxDuration / #gained)
		local began = os.clock()
		local started = 0

		while true do
			if revealToken ~= token then return end

			local now = os.clock()
			while started < #gained and now - began >= started * interval do
				started += 1
				state.Started[gained[started]] = began + (started - 1) * interval
			end

			local text, finished = renderReveal(state, now)
			if selectedId == state.Id then
				infoDescription.Text = text
			end
			if finished then break end

			RunService.Heartbeat:Wait()
		end

		if revealToken ~= token then return end
		task.wait(REVEAL.SettleDelay)
		if revealToken ~= token then return end

		RevealState = nil
		paintInfo(false)
	end)
end

local function buildModalBlocker()
	local blocker = Instance.new("ImageButton")
	blocker.Name = "ModalBlocker"
	blocker.BackgroundTransparency = 1
	blocker.ImageTransparency = 1
	blocker.AutoButtonColor = false
	blocker.Modal = true
	blocker.Active = true
	blocker.Selectable = false
	blocker.AnchorPoint = Vector2.new(0.5, 0.5)
	blocker.Position = UDim2.fromScale(0.5, 0.5)
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.ZIndex = 0
	blocker.Parent = gui
end

local function clearBuiltUi()
	for _, card in Cards do
		for _, connection in card.Connections do
			connection:Disconnect()
		end
	end
	table.clear(Cards)

	for _, child in cardsFrame:GetChildren() do
		if child ~= cardTemplate and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for _, child in gui:GetChildren() do
		if child.Name == "ModalBlocker" then
			child:Destroy()
		end
	end
end

local function buildCard(index: number, entry: IndexConfig.Entry)
	local holder = cardTemplate:Clone()
	holder.Name = entry.Id
	holder.LayoutOrder = index
	holder.Visible = false
	holder.Parent = cardsFrame

	local button = holder:FindFirstChild("Card") :: ImageButton
	local marker = button:FindFirstChild("Selected") :: ImageLabel
	local label = button:FindFirstChild("Name") :: TextLabel
	local card: Card = {
		Id = entry.Id,
		Holder = holder,
		Button = button,
		Label = label,
		LabelColor = label.TextColor3,
		Marker = marker,
		MarkerSize = marker.Size,
		Viewport = button:FindFirstChild("Headshot") :: ViewportFrame,
		Hovered = false,
		Pressed = false,
		Connections = {},
	}
	Cards[entry.Id] = card

	buildHeadshot(card.Viewport, entry)

	table.insert(card.Connections, button.Activated:Connect(function()
		IndexUIService:Select(entry.Id)
	end))

	table.insert(card.Connections, button.MouseEnter:Connect(function()
		card.Hovered = true
		poseCard(card)
	end))
	table.insert(card.Connections, button.MouseLeave:Connect(function()
		card.Hovered = false
		card.Pressed = false
		poseCard(card)
	end))
	table.insert(card.Connections, button.MouseButton1Down:Connect(function()
		card.Pressed = true
		poseCard(card)
	end))
	table.insert(card.Connections, button.MouseButton1Up:Connect(function()
		card.Pressed = false
		poseCard(card)
	end))
end

local function build()
	clearBuiltUi()
	buildModalBlocker()

	for index, entry in Entries do
		if entry.Listed == false then continue end
		buildCard(index, entry)
	end

	prevChrome = wireChrome(prevButton)
	nextChrome = wireChrome(nextButton)

	prevButton.Activated:Connect(function()
		IndexUIService:PreviousPage()
	end)

	nextButton.Activated:Connect(function()
		IndexUIService:NextPage()
	end)

	if closeButton then
		wireChrome(closeButton)
	end

	if PAGE.ReplayOnOpen and gui then
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled then
				dealPage(currentSlice())
			end
		end)
	end
end

if IndexConfig.StartProgress > 0 then
	for _, entry in Entries do
		Progress[entry.Id] = math.clamp(IndexConfig.StartProgress, 0, 1)
	end
end

build()

local updateEvent = CommunicationService.Find("Index", "Update")
local revealEvent = CommunicationService.Find("Index", "Reveal")

if updateEvent and updateEvent:IsA("RemoteEvent") then
	updateEvent.OnClientEvent:Connect(function(set)
		IndexUIService:SetProgressSet(set or {})
	end)
	updateEvent:FireServer()
end

if revealEvent and revealEvent:IsA("RemoteEvent") then
	revealEvent.OnClientEvent:Connect(function(id, before, after)
		if type(id) ~= "string" or type(before) ~= "number" or type(after) ~= "number" then return end
		IndexUIService:PlayReveal(id, before, after)
	end)
end

IndexUIService:Refresh()

return IndexUIService
