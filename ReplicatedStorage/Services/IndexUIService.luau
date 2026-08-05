local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FriendAvatar = require(ReplicatedStorage.Modules.FriendAvatar)
local IndexConfig = require(ReplicatedStorage.Configs.IndexConfig)

--- Drives `StarterGui.IndexGui`: fills its card grid from `IndexConfig`, renders a headshot of each
--- enemy into the card's viewport, pages through them eight at a time, and writes the selected
--- entry into the info panel. The layout itself is authored in Studio and never built here -- this
--- only ever clones the authored `Cards.Template` and sets text, tints and visibility on it.
---
--- Opening and closing the window is deliberately not handled here. Nothing in this file touches
--- `IndexGui.Enabled` or the close button, so whatever ends up owning the open/close animation can
--- do so without having to coordinate with the contents.
---
--- Paging is done by visibility rather than by a `UIPageLayout`. A `UIGridLayout` skips children
--- whose `Visible` is false, so hiding the seven-through-twelfth cards leaves the first eight laid
--- out in exactly the authored grid -- which means one card per entry, built once, and a page flip
--- that does not have to rebuild a single viewport. A page layout would have needed the grid split
--- across a frame per page and the rigs re-cloned or re-parented on every flip, for the same result.
---
--- Every card is a `Template` *holder* frame with the card button inside it. The layout only ever
--- sees the holder, which is what lets the card grow, lift and tilt on hover without the grid
--- putting it straight back -- and it means visibility is set on the holder while every animated
--- property belongs to the button. The page arrows are arranged the same way, because a
--- `UIListLayout` positions each arrow from the other's size and scaling one in place shoved its
--- neighbour along the row.
---
--- Discovery is already the thing that decides what a card says, even though every entry is handed
--- out at the moment: `IndexConfig.DiscoveredByDefault` fills the set at startup and
--- `SetDiscovered` / `SetDiscoveredSet` replace it. When there is somewhere to persist discovery
--- from, that flag goes false and the server calls one of those -- nothing else has to move.
local IndexUIService = {}

if not RunService:IsClient() then
	return IndexUIService
end

local HEADSHOT = IndexConfig.Headshot
local LOCKED = IndexConfig.Locked
local PER_PAGE = IndexConfig.EntriesPerPage
local CARD = IndexConfig.Animation.Card
local BUTTON = IndexConfig.Animation.Button
local PAGE = IndexConfig.Animation.Page
local INFO = IndexConfig.Animation.Info

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--- One entry's card. `Holder` is what the grid lays out and what paging shows and hides; `Button` is
--- what everything else touches, because it is the only part of a card free to move.
type Card = {
	Id: string,
	Holder: Frame,
	Button: ImageButton,
	Label: TextLabel,
	Marker: ImageLabel,
	--- The marker's authored size, kept because the pop animation scales it from nothing. Reading it
	--- back off the instance would sample a pop still in flight and shrink the marker a little more
	--- with every click.
	MarkerSize: UDim2,
	Viewport: ViewportFrame,
	Hovered: boolean,
	Pressed: boolean,
	Tween: Tween?,
}

--- Every entry's card, keyed by entry id. Built once, then only repainted.
local Cards: { [string]: Card } = {}
--- Which entries the player has met. Absent is undiscovered; there is no third state.
local Discovered: { [string]: boolean } = {}
--- Entry ids in the order they are currently listed, which is authored order minus anything
--- `HideUndiscovered` has taken out. Recomputed by `Refresh`, and what pages are cut from.
local Listed: { string } = {}

local selectedId: string? = nil
local currentPage = 1

local Entries = IndexConfig.Entries
local EntriesById: { [string]: IndexConfig.Entry } = {}
for _, entry in Entries do
	EntriesById[entry.Id] = entry
end

--- Finding the GUI ------------------------------------------------------------------------------

-- Waited for with a timeout rather than indefinitely: this module is required from a plain loop
-- over `ReplicatedStorage.Services`, so blocking here would stall every service after it.
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

--- Headshots -------------------------------------------------------------------------------------

local templateSource: Instance? = nil
local warnedAboutFallback = false

--- The folder the enemy model templates live in. `ReplicatedStorage` is where they belong and where
--- `EnemyService` clones them from; the workspace fallback is only a safety net for a place where
--- they have been dragged out for authoring, and it deliberately picks the folder holding the most
--- of the configured models so it cannot latch onto the live enemy folder instead.
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

--- The part a shot is centred on: whatever the entry named, then a `Head`, then the model's primary
--- part. A one-part enemy like the Eye or the Creep names its own part and lands on the first case.
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

--- Builds the placeholder stood in for an enemy with nothing renderable of its own. Framed off its
--- whole bounding box rather than a focus part, since there is no head to find.
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

--- Never makes anything more opaque than it already is, so a rig's invisible `HumanoidRootPart`
--- does not come back as a translucent block in the middle of the shot.
local function applyTransparency(model: Model, transparency: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = math.max(descendant.Transparency, transparency)
		end
	end
end

--- Where the camera aims and how big the thing it is framing is. A stand-in has no head to find, so
--- it is measured whole.
local function measure(model: Model, headshot: IndexConfig.Headshot): (Vector3?, Vector3?)
	if headshot.Standin then
		local box, size = model:GetBoundingBox()
		return box.Position, size
	end

	local focus = findFocus(model, headshot)
	if not focus then return nil, nil end
	return focus.Position, focus.Size
end

--- Puts `model` in `viewport`, clearing whatever was there, and points a camera at its head. Takes
--- ownership of `model`: it is parented in, stripped and re-posed.
local function present(viewport: ViewportFrame, model: Model, headshot: IndexConfig.Headshot)
	-- Nothing in a portrait should be running: an `Animate` script would sit there trying to load
	-- animations onto a Humanoid that is not in the world.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end

	-- The Humanoid stays, because it is what holds the rig's face and body colours on -- take it away
	-- and a Chaser is a blank tan head. It is only stopped from doing anything: left running it
	-- re-seats the body against a joint solver a `ViewportFrame` never turns, and a rig built from a
	-- `HumanoidDescription` (which carries no `Motor6D`s at all) collapses onto its own root. Same
	-- two switches `GhostRenderService` throws on the ghost's client-side avatar, for the same reason.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.AutoRotate = false
	end

	if headshot.Transparency then
		applyTransparency(model, headshot.Transparency)
	end

	-- Parked at the origin so the camera maths below deals in small numbers regardless of where the
	-- template happens to be sitting.
	model:PivotTo(CFrame.identity)

	local target, extent = measure(model, headshot)
	if not target or not extent then
		model:Destroy()
		return
	end

	clearViewport(viewport)
	model.Parent = viewport

	local yaw = headshot.Yaw or HEADSHOT.Yaw
	local pitch = headshot.Pitch or HEADSHOT.Pitch
	local zoom = headshot.Zoom or HEADSHOT.Zoom

	-- Fit the largest axis of what is being framed into the vertical field of view, padded so a hat,
	-- a mask or an accessory that is not part of the measurement still lands inside the frame.
	local radius = math.max(extent.X, extent.Y, extent.Z) * 0.5 * HEADSHOT.Padding
	local distance = (radius / math.tan(math.rad(HEADSHOT.FieldOfView) * 0.5)) * zoom

	-- The model's own pivot is what "straight on" means: an R15 rig's root looks the way the rig
	-- faces, so the camera goes out along that and turns back around.
	local facing = model:GetPivot().Rotation
	local direction = (facing * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)).LookVector
	local aim = target + facing:VectorToWorldSpace(headshot.Offset or Vector3.zero)

	local camera = Instance.new("Camera")
	camera.FieldOfView = HEADSHOT.FieldOfView
	camera.CFrame = CFrame.lookAt(aim + direction * distance, aim)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

--- Bumped every time a viewport is asked for a new shot, so a friend's avatar that finishes loading
--- after the viewport has moved on to another entry is thrown away instead of drawn over it.
local Generations: { [ViewportFrame]: number } = {}

--- Puts one enemy into `viewport`. Called once per card at startup and once per selection for the
--- info panel. An entry that wears a friend's avatar is drawn from its own model first and swapped
--- once the avatar arrives -- the fetch is two web calls deep, and a card that is blank until they
--- come back looks broken rather than pending.
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
		-- Keyed on the entry rather than the viewport, so the card and the info panel show the same
		-- face and a repaint does not roll a new friend.
		local rig = FriendAvatar.Build(entry.Id)
		if not rig then return end

		if Generations[viewport] ~= generation or not viewport.Parent then
			rig:Destroy()
			return
		end

		present(viewport, rig, headshot)
	end)
end

--- Animation ------------------------------------------------------------------------------------

--- Moves a card to the one pose its current state calls for. A press beats a hover and a hover beats
--- a selection, so there is only ever one target and nothing to sequence -- every path through here
--- cancels whatever was running and tweens from wherever that left the card, which is what stops a
--- pointer swept across the grid from leaving cards stuck half-raised behind it.
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

--- Bumped by every deal, so the tail of an interrupted one cannot land on the page that replaced it.
local pageGeneration = 0

--- Deals the cards of a page out rather than having them appear already there. Each one starts a
--- little small and a little low and is sent to its resting pose a beat after the one before it.
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

--- A page arrow or the close button. These sit at whatever size they were authored at rather than
--- filling a holder, so `Base` is what a scale is applied to -- the arrows fill theirs and the close
--- button does not, and both have to grow about their own centre either way.
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

--- Set by `build`. `applyPage` runs before them at startup and has to tolerate that.
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

--- Painting --------------------------------------------------------------------------------------

--- Whether the player has met this enemy. Everything user-facing goes through here rather than
--- reading `Discovered` directly, so the day discovery arrives there is one place it comes from.
function IndexUIService:IsDiscovered(id: string): boolean
	return Discovered[id] == true
end

local function paintCard(entry: IndexConfig.Entry)
	local card = Cards[entry.Id]
	if not card then return end

	local discovered = IndexUIService:IsDiscovered(entry.Id)

	-- Raised, because the cards are labels on a board rather than sentences.
	card.Label.Text = discovered and string.upper(entry.Name) or LOCKED.Name
	card.Viewport.ImageColor3 = discovered and HEADSHOT.Tint or LOCKED.Tint
	card.Viewport.Visible = discovered or LOCKED.ShowSilhouette
end

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}

--- Brings the panel's contents back in from just below, faded. Called on a change of selection and
--- not on a repaint, so unlocking something does not re-run the panel it is already showing.
local function playInfoTransition()
	for _, tween in infoTweens do
		tween:Cancel()
	end
	table.clear(infoTweens)

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

--- Puts the panel back where it belongs with nothing in flight, for a repaint that is not a change
--- of selection. Without this a repaint landing mid-transition would leave the text half faded.
local function settleInfo()
	for _, tween in infoTweens do
		tween:Cancel()
	end
	table.clear(infoTweens)

	infoName.TextTransparency = 0
	infoDescription.TextTransparency = 0
	infoHeadshot.ImageTransparency = 0
	infoName.Position = infoNameBase
	infoDescription.Position = infoDescriptionBase
end

local function paintInfo(animate: boolean?)
	local entry = selectedId and EntriesById[selectedId]

	if not entry then
		settleInfo()
		infoName.Text = IndexConfig.Empty.Name
		infoDescription.Text = IndexConfig.Empty.Description
		infoHeadshot.Visible = false
		return
	end

	local discovered = IndexUIService:IsDiscovered(entry.Id)
	infoName.Text = discovered and string.upper(entry.Name) or LOCKED.Name
	infoDescription.Text = discovered and entry.Description or LOCKED.Description
	infoHeadshot.ImageColor3 = discovered and HEADSHOT.Tint or LOCKED.Tint
	infoHeadshot.Visible = discovered or LOCKED.ShowSilhouette

	buildHeadshot(infoHeadshot, entry)

	if animate then
		playInfoTransition()
	else
		settleInfo()
	end
end

--- Paging ----------------------------------------------------------------------------------------

local function pageCount(): number
	return math.max(1, math.ceil(#Listed / PER_PAGE))
end

--- The entry ids showing on the current page, in the order they are laid out.
local function currentSlice(): { string }
	local first = (currentPage - 1) * PER_PAGE
	local slice = {}
	for index = first + 1, math.min(first + PER_PAGE, #Listed) do
		table.insert(slice, Listed[index])
	end
	return slice
end

--- Shows the current page's slice of `Listed` and hides everything else, then dims whichever arrows
--- have nowhere to go. Both are dim when there is only one page, which is the state the index sits
--- in until enough entries exist to fill a second.
---
--- Dealing is not done here. This runs on every selection too, and a card being clicked should not
--- send its whole page back through an entrance.
local function applyPage()
	local pages = pageCount()
	currentPage = math.clamp(currentPage, 1, pages)

	local showing: { [string]: boolean } = {}
	for _, id in currentSlice() do
		showing[id] = true
	end

	for id, card in Cards do
		card.Holder.Visible = showing[id] == true

		-- A card whose entry is selected keeps its marker even while it is off-page; hiding the card
		-- hides the marker with it, and flipping back should not have lost the selection.
		local selected = id == selectedId
		if selected and not card.Marker.Visible then
			-- Popped in rather than switched on, so the marker reads as being stamped onto the card.
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

--- Rebuilds the listing from the discovery set and repaints everything that reads off it. Cheap:
--- no viewport is touched except the info panel's, so this is safe to call on every unlock.
function IndexUIService:Refresh()
	table.clear(Listed)
	for _, entry in Entries do
		if IndexConfig.HideUndiscovered and not IndexUIService:IsDiscovered(entry.Id) then continue end
		table.insert(Listed, entry.Id)
	end

	for _, entry in Entries do
		paintCard(entry)
	end

	-- A selection that has just been filtered out of the listing cannot stay selected.
	if selectedId and not table.find(Listed, selectedId) then
		selectedId = Listed[1]
	elseif not selectedId then
		selectedId = Listed[1]
	end

	applyPage()
	dealPage(currentSlice())
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

--- Selection -------------------------------------------------------------------------------------

--- Puts an entry in the info panel and moves the marker onto its card. A locked entry is still
--- selectable: the panel says as little about it as the card does, which is the point of it having
--- a slot at all.
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

--- Discovery -------------------------------------------------------------------------------------

--- Marks one entry met, or unmarks it. Unknown ids are ignored rather than stored, so a saved set
--- from before an entry was renamed cannot resurrect a card that no longer exists.
function IndexUIService:SetDiscovered(id: string, discovered: boolean?)
	if not EntriesById[id] then return end

	local value = discovered ~= false
	if Discovered[id] == value then return end

	Discovered[id] = value or nil
	IndexUIService:Refresh()
end

--- Replaces the whole discovery set at once, which is the shape a save file arrives in. Anything
--- absent from `set` is treated as undiscovered.
function IndexUIService:SetDiscoveredSet(set: { [string]: boolean })
	table.clear(Discovered)
	for id, discovered in set do
		if EntriesById[id] and discovered then
			Discovered[id] = true
		end
	end
	IndexUIService:Refresh()
end

function IndexUIService:GetDiscovered(): { [string]: boolean }
	return table.clone(Discovered)
end

--- Building --------------------------------------------------------------------------------------

--- Makes the index modal: while it is up the mouse is free and nothing behind it can be clicked.
---
--- Both come from one full-screen transparent button sitting behind the board. `Modal` is what
--- releases the mouse -- this is a first-person game, so without it the cursor stays locked to the
--- middle of the screen and none of the cards can be reached. Being a button is what stops clicks
--- that miss the board reaching the world or any GUI underneath, which is the other half of what
--- modal means.
---
--- It lives inside `IndexGui`, so it is only present while the window is, and toggling
--- `IndexGui.Enabled` is still the only thing that opens and closes the index. It does not freeze
--- the character: walking away from an open index is a gameplay decision rather than a UI one, and
--- if you want it, disabling the controls belongs next to whatever owns the open.
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
	blocker.ZIndex = 0 -- `Design` sits at 1, so this is behind everything the player can see
	blocker.Parent = gui
end

local function buildCard(index: number, entry: IndexConfig.Entry)
	local holder = cardTemplate:Clone()
	holder.Name = entry.Id
	holder.LayoutOrder = index -- authored order, which the grid sorts on
	holder.Visible = false -- `applyPage` decides; an invisible holder is skipped by the grid
	holder.Parent = cardsFrame

	local button = holder:FindFirstChild("Card") :: ImageButton
	local marker = button:FindFirstChild("Selected") :: ImageLabel
	local card: Card = {
		Id = entry.Id,
		Holder = holder,
		Button = button,
		Label = button:FindFirstChild("Name") :: TextLabel,
		Marker = marker,
		MarkerSize = marker.Size,
		Viewport = button:FindFirstChild("Headshot") :: ViewportFrame,
		Hovered = false,
		Pressed = false,
	}
	Cards[entry.Id] = card

	buildHeadshot(card.Viewport, entry)

	button.Activated:Connect(function()
		IndexUIService:Select(entry.Id)
	end)

	-- A pointer leaving clears the press as well as the hover: releasing off the card never fires
	-- `MouseButton1Up` on it, and without this the card would stay squashed until it was pressed again.
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
	buildModalBlocker()

	for index, entry in Entries do
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

	-- Animated but not wired to anything. Opening and closing the index is still somebody else's to
	-- own; this only gives the button the same weight under a pointer as everything else on the board.
	if closeButton then
		wireChrome(closeButton)
	end

	-- Nothing here opens the window. It only notices that something else did, so the board is dealt
	-- out on the way in rather than already sitting there finished.
	if PAGE.ReplayOnOpen and gui then
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled then
				dealPage(currentSlice())
			end
		end)
	end
end

if IndexConfig.DiscoveredByDefault then
	for _, entry in Entries do
		Discovered[entry.Id] = true
	end
end

build()

-- Where a server-owned discovery set arrives, once one exists. Optional on purpose: the index works
-- standalone today, and adding the folder later is the only change needed to hand it over.
local communication = ReplicatedStorage:FindFirstChild("Communication")
local indexCommunication = communication and communication:FindFirstChild("Index")
local updateEvent = indexCommunication and indexCommunication:FindFirstChild("Update")
if updateEvent and updateEvent:IsA("RemoteEvent") then
	updateEvent.OnClientEvent:Connect(function(set)
		IndexUIService:SetDiscoveredSet(set or {})
	end)
	updateEvent:FireServer()
end

IndexUIService:Refresh()

return IndexUIService
