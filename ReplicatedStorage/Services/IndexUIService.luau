local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FriendAvatar = require(ReplicatedStorage.Modules.FriendAvatar)
local IndexConfig = require(ReplicatedStorage.Configs.IndexConfig)
local Redaction = require(ReplicatedStorage.Modules.Redaction)

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
--- Discovery decides what every card and the info panel say, and it is a number rather than a flag:
--- each entry carries a progress from 0 to 1, owned by the server's `EnemyDiscoveryService` and
--- arriving over `Communication.Index.Update`.
---
--- How much of that number is drawn depends on what is being drawn. The *board* reads it as a flag:
--- at zero an entry is `IndexConfig.Locked` -- UNDISCOVERED, no description, portrait tinted flat
--- black -- and anywhere above zero it is lit plainly, with the enemy's real name on it. There is no
--- middle. Walking brightness up with progress made the grid a row of half-lit photographs whose
--- dimness only ever repeated what the description already said, and left an enemy the player had
--- actually met still looking like one they had not.
---
--- The *description* is where the number is spent, a few words at a time, and it is spent by width
--- rather than by word count -- so half discovered means half a paragraph rather than half its words.
--- Which words go first, and how much of the text each one costs, is `Modules.Redaction`'s business.
---
--- Nothing here decides what *earns* progress. This file only draws it.
local IndexUIService = {}

if not RunService:IsClient() then
	return IndexUIService
end

-- Required after the client guard above, because it is a client service too and requiring it from a
-- server-side pass through `ReplicatedStorage.Services` would have it building GUIs for nobody.
local DeathScreenService = require(ReplicatedStorage.Services.DeathScreenService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)

local HEADSHOT = IndexConfig.Headshot
local LOCKED = IndexConfig.Locked
local DISCOVERY = IndexConfig.Discovery
local REVEAL = IndexConfig.Discovery.Reveal
local PER_PAGE = IndexConfig.EntriesPerPage

--- What the index is called in `InterfaceService`'s page table. Not the `ScreenGui`'s name -- the
--- controller deals in page ids, and `IndexGui` is what that id resolves to.
local INTERFACE_PAGE = "Index"
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
	LabelColor: Color3,
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
--- How much of each entry the player has earned, 0 to 1. Absent is zero, and zero is an entry they
--- have never met -- so an id missing from here and an id sitting at 0 mean the same thing, which is
--- what lets the server send only what has actually been discovered.
local Progress: { [string]: number } = {}
--- Entry ids in the order they are currently listed, which is authored order minus anything
--- `HideUndiscovered` has taken out. Recomputed by `Refresh`, and what pages are cut from.
local Listed: { string } = {}

--- The reveal animation's picture of the description while it is running, or nil the rest of the
--- time. `Progress` here is the *new* progress: every word being uncovered is already visible at it
--- and is held back until the clock says its turn has come, which is what lets one render call draw
--- any frame of the animation from nothing but the current time.
type Reveal = {
	Id: string,
	Progress: number,
	--- The word positions this death earned, in the order `Redaction` earned them.
	Order: { number },
	--- When each of those started, as an `os.clock` stamp; absent until it does. Stamped with its
	--- *scheduled* time rather than with the time the frame happened to notice, so a dropped frame
	--- does not stretch the cadence of everything after it.
	Started: { [number]: number },
	Token: number, -- bumped by every new reveal, so an interrupted one cannot finish over its successor
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

--- How much of this entry the player has earned, 0 to 1. Everything user-facing goes through here
--- rather than reading `Progress` directly.
function IndexUIService:GetProgress(id: string): number
	return Progress[id] or 0
end

--- Whether the player has met this enemy at all. Kept as its own question because most of the index
--- only cares about the difference between nothing and something -- whether a card has a name on it,
--- whether it counts towards a total -- and reading `> 0` at each of those sites would spread the
--- definition of "met" across the file.
function IndexUIService:IsDiscovered(id: string): boolean
	return IndexUIService:GetProgress(id) > DISCOVERY.NamedAbove
end

--- What the description panel should read for an entry at `progress`. An entry nobody has met gets
--- the stock line rather than a wall of blocks: there is nothing to be partway through yet, and a
--- redacted paragraph would imply there is something specific behind it.
---
--- `suppress` and `colors` are the reveal animation's, and are nil every other time this is called.
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

--- What a lit card and a lit portrait are tinted with -- which is to say, nothing: white leaves the
--- artwork and the rendered shot exactly as authored. Named rather than written as `Color3.new(1,1,1)`
--- at four call sites so the two halves of "discovered" stay one decision.
local LIT = HEADSHOT.Tint

local function paintCard(entry: IndexConfig.Entry)
	local card = Cards[entry.Id]
	if not card then return end

	local discovered = IndexUIService:IsDiscovered(entry.Id)

	-- Raised, because the cards are labels on a board rather than sentences.
	card.Label.Text = discovered and string.upper(entry.Name) or LOCKED.CardName
	card.Label.TextColor3 = discovered and card.LabelColor or LOCKED.CardTextColor

	-- `ImageColor3` multiplies the shot the viewport renders, so `Locked.Tint` being flat black is
	-- what makes an undiscovered enemy a silhouette rather than a dim photograph of itself.
	card.Viewport.ImageColor3 = discovered and LIT or LOCKED.Tint
	card.Viewport.Visible = discovered or LOCKED.ShowSilhouette

	-- The card itself, not just the portrait pinned to it. Tinting only the viewport left an
	-- undiscovered entry as a bright white photograph of a dark shape, which read as a finished card
	-- of something black rather than as one nobody has filled in yet. `Button` is the piece that
	-- carries the artwork and every animation; the `Template` frame around it is an invisible holder
	-- that exists so the grid has something to lay out while the card is free to lift out of its cell.
	card.Button.ImageColor3 = discovered and LIT or LOCKED.CardTint
end

local infoNameBase = infoName.Position
local infoDescriptionBase = infoDescription.Position
local infoTweens: { Tween } = {}

--- Which entry the info panel's viewport is currently holding. Building a headshot clones a rig,
--- strips its scripts and re-aims a camera, and the panel is repainted on every replication the
--- server sends -- so doing that work again for an entry already sitting in the viewport was pure
--- flicker. Rebuilt only on a change of selection.
local infoHeadshotId: string? = nil

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

--- One frame of the reveal: the description as it should read at `now`, and whether every word in it
--- has finished moving.
---
--- Each earned word runs its own three-part sequence and nothing waits on anything else, so several
--- are always somewhere in one at a time. Where a given word is depends on nothing but how long ago
--- it started, which is what lets any frame be drawn without the panel keeping a running picture of
--- the animation -- and is why an interrupted reveal leaves nothing behind to unwind.
local function renderReveal(state: Reveal, now: number): (string, boolean)
	local entry = EntriesById[state.Id]
	if not entry then return "", true end

	local body = infoDescription.TextColor3
	local suppress: { [number]: boolean } = {}
	local colors: { [number]: Color3 } = {}
	local finished = true

	for _, position in state.Order do
		local started = state.Started[position]

		-- Not its turn yet. Left as ordinary redaction, so a word still queued looks no different from
		-- one this death was never going to buy -- there is nothing to give away which is which.
		if not started then
			suppress[position] = true
			finished = false
			continue
		end

		local age = now - started

		-- Charging. Still covered, but the blocks brighten out of the redaction colour and break at the
		-- top of it -- so a word landing is something happening to the page, and the eye is already on
		-- the right part of the paragraph when it does.
		if age < REVEAL.ChargeTime then
			suppress[position] = true
			colors[position] = DISCOVERY.HiddenColor:Lerp(REVEAL.ChargeColor, age / REVEAL.ChargeTime)
			finished = false
			continue
		end

		-- Cooling, or done. A word past its cool is left out of `colors` entirely and so is drawn in the
		-- label's own colour, exactly like a word the player has had for weeks.
		local cooled = (age - REVEAL.ChargeTime) / REVEAL.SettleTime
		if cooled >= 1 then continue end
		finished = false

		if cooled < REVEAL.FlashFraction then
			colors[position] = REVEAL.ChargeColor:Lerp(DISCOVERY.NewColor, cooled / REVEAL.FlashFraction)
		else
			-- Squared, so the word holds its warmth for most of the cool and then lets go, rather than
			-- sliding evenly towards the body colour from the moment it arrives.
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

	-- A reveal in flight owns the description outright: it is walking the panel from what the player
	-- knew before the death to what they know now, and a repaint landing in the middle of that would
	-- jump straight to the end and throw away the animation.
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
	local previous = table.concat(Listed, "\0")

	table.clear(Listed)
	for _, entry in Entries do
		if IndexConfig.HideUndiscovered and not IndexUIService:IsDiscovered(entry.Id) then continue end
		table.insert(Listed, entry.Id)
	end
	local relisted = table.concat(Listed, "\0") ~= previous

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

	-- Only when the listing itself has moved -- which at startup is nothing to something, and after
	-- that is only ever `HideUndiscovered` letting a new entry in. This runs on every replication the
	-- server sends, and a sighting paying out while the board is open should not send the page the
	-- player is reading back through its entrance animation four times a second.
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

--- Sets how much of one entry the player has. Unknown ids are ignored rather than stored, so a saved
--- set from before an entry was renamed cannot resurrect a card that no longer exists.
function IndexUIService:SetProgress(id: string, progress: number)
	if not EntriesById[id] then return end

	local value = math.clamp(progress, 0, 1)
	if Progress[id] == value then return end

	Progress[id] = value > 0 and value or nil
	IndexUIService:Refresh()
end

--- Replaces the whole set at once, which is the shape it arrives from the server in. Anything absent
--- is treated as undiscovered.
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

--- Reveal ----------------------------------------------------------------------------------------

--- Opens the index on `id` and uncovers the words a death has just earned, each one lighting up
--- through its own redaction and cooling back into the page a beat after the next has started.
---
--- Runs off `before` and `after` rather than off whatever `Progress` currently holds, because the
--- server sends the new set before it sends this -- by the time the animation starts the panel would
--- otherwise already be showing the finished description, and there would be nothing left to reveal.
--- The words gained between the two are suppressed back out of the render, then released in the
--- order `Redaction` earned them.
---
--- Deliberately does nothing when the gain uncovered no words. A death that moved an entry from 0.9
--- to 1.0 of a twelve-word description adds nothing visible, and opening a menu to show a player an
--- unchanged paragraph is worse than staying quiet.
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
		-- Wait the death screen out. It holds a finished hint for `MinimumTime` and only then fades,
		-- which outlasts the respawn that triggered this -- so the server firing on a timer could
		-- never have got this right, and opening on arrival put the board up behind a screen still
		-- typing at the player. Polled rather than signalled: this is the only thing that cares, and
		-- a poll cannot leak a connection if the reveal is interrupted.
		local waitedUntil = os.clock() + REVEAL.DeathScreenTimeout
		while DeathScreenService:IsVisible() and os.clock() < waitedUntil do
			task.wait(0.1)
		end
		if revealToken ~= token then return end

		-- A clear beat of the world back before the board arrives, so the two read as separate events.
		task.wait(REVEAL.AfterDeathDelay)
		if revealToken ~= token then return end

		-- Through the interface controller rather than by setting `Enabled`, so the board arrives with
		-- the same open animation and blur as a page the player asked for themselves.
		InterfaceService:Open(INTERFACE_PAGE)
		IndexUIService:Select(id)
		-- `Select` no-ops when the entry was already showing, and the panel still has to be repainted
		-- into its pre-reveal state either way.
		paintInfo(false)

		task.wait(REVEAL.OpenDelay)
		if revealToken ~= token then return end

		-- A long description filling from nothing would otherwise hold the player in a menu for as
		-- long as it took; past `MaxDuration` the words simply start faster. Only the spacing is
		-- squeezed -- each word still gets its whole charge and cool, which is what stops a big gain
		-- from degenerating into a flicker.
		local interval = math.min(REVEAL.WordInterval, REVEAL.MaxDuration / #gained)
		local began = os.clock()
		local started = 0

		-- Driven off the frame clock rather than off a wait per word. Every word is somewhere in its
		-- own charge-and-cool at any given moment, so the description is redrawn each frame from the
		-- time rather than once per word from a counter -- and only the description is touched. The
		-- panel's full repaint used to run here, which meant rebuilding the portrait viewport once per
		-- word: a rig cloned, stripped and re-framed twenty times over a four-second animation, for a
		-- picture that had not changed.
		while true do
			if revealToken ~= token then return end

			local now = os.clock()
			while started < #gained and now - began >= started * interval do
				started += 1
				state.Started[gained[started]] = began + (started - 1) * interval
			end

			local text, finished = renderReveal(state, now)
			-- The player is free to click another card mid-reveal. The animation keeps running -- it is
			-- theirs to come back to -- but it stops writing into a panel that is showing something else.
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

if IndexConfig.StartProgress > 0 then
	for _, entry in Entries do
		Progress[entry.Id] = math.clamp(IndexConfig.StartProgress, 0, 1)
	end
end

build()

-- Where the server's discovery set arrives. Found rather than waited for so a place without the
-- folder still draws an index -- an authoring copy with no server running should show the board
-- rather than hang on a `WaitForChild` behind every other client service in the startup loop.
local communication = ReplicatedStorage:FindFirstChild("Communication")
local indexCommunication = communication and communication:FindFirstChild("Index")
local updateEvent = indexCommunication and indexCommunication:FindFirstChild("Update")
local revealEvent = indexCommunication and indexCommunication:FindFirstChild("Reveal")

if updateEvent and updateEvent:IsA("RemoteEvent") then
	updateEvent.OnClientEvent:Connect(function(set)
		IndexUIService:SetProgressSet(set or {})
	end)
	-- Asked for rather than waited for: the profile may well have loaded before this GUI existed, in
	-- which case the server's own push has already been and gone.
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
