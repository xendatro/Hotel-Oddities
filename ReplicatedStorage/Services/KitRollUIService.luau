local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local KitStateService = require(ReplicatedStorage.Services.KitStateService)
local KitVisualService = require(ReplicatedStorage.Services.KitVisualService)

local KitRollUIService = {}

if not RunService:IsClient() then
	return KitRollUIService
end

local ROLL = KitConfig.Roll
local PITCH = ROLL.CardWidth + ROLL.CardPadding
local CAROUSEL_JOB = "KitRollCarousel"

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild("RollGui") :: ScreenGui
local main = gui:WaitForChild("Main") :: Frame
local reel = main:WaitForChild("Reel") :: CanvasGroup
local strip = reel:WaitForChild("Strip") :: Frame
local marker = main:WaitForChild("Marker") :: Frame
local backdrop = main:WaitForChild("Backdrop") :: Frame
local result = main:WaitForChild("Result") :: Frame
local rarityLabel = result:WaitForChild("RarityLabel") :: TextLabel
local kitNameLabel = result:WaitForChild("KitNameLabel") :: TextLabel
local kitDescLabel = result:WaitForChild("KitDescLabel") :: TextLabel
local rollButton = main:WaitForChild("RollButton") :: ImageButton
local rollLabel = rollButton:WaitForChild("TextLabel") :: TextLabel
local myKitsButton = main:WaitForChild("MyKitsButton") :: ImageButton
local costLabel = main:WaitForChild("Cost"):WaitForChild("CostLabel") :: TextLabel
local balance = main:WaitForChild("background_frame"):WaitForChild("Gems"):WaitForChild("CurrentBalance") :: TextLabel
local notice = main:WaitForChild("Notice") :: TextLabel

local shopTemplate = playerGui:WaitForChild("KitsShop"):WaitForChild("Design"):WaitForChild("KitsCanvas"):WaitForChild("Kits"):WaitForChild("Template") :: ImageButton

local random = Random.new()
local busy = false
local weighted: { KitConfig.Kit } = {}

for _, kit in KitConfig.Entries do
	local rarity = KitConfig.GetRarity(kit)
	local copies = math.max(1, math.floor(rarity.Weight))
	for _ = 1, copies do
		table.insert(weighted, kit)
	end
end

local REASONS = {
	InsufficientGems = "Not enough gems.",
	Restricted = "Paid random items are not available on your account.",
	Busy = "Still rolling.",
	NotLoaded = "Your save is still loading.",
	Failed = "The roll could not be completed.",
	EmptyPool = "No kits are available to roll.",
}

local markerScale = marker:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
markerScale.Name = "MarkerScale"
markerScale.Parent = marker

local resultScale = result:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
resultScale.Name = "ResultScale"
resultScale.Parent = result

local reelBase = reel.Position

local function offsetFor(index: number): number
	return 0.5 - ((index - 1) * PITCH + ROLL.CardWidth * 0.5)
end

local function makeReelCard(kit: KitConfig.Kit, index: number): ImageButton
	local card = shopTemplate:Clone()
	card.Name = `Slot{index}`
	card.Visible = true
	card.Active = false
	card.Selectable = false
	card.AutoButtonColor = false
	card.Modal = false
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.Position = UDim2.fromScale((index - 1) * PITCH, 0.5)
	card.Size = UDim2.fromScale(ROLL.CardWidth, 0.92)
	card.ZIndex = 22
	card.Parent = strip

	local aspect = card:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then aspect:Destroy() end

	local scale = Instance.new("UIScale")
	scale.Name = "CarouselScale"
	scale.Scale = ROLL.MinScale
	scale.Parent = card

	KitVisualService.DressCard(card, kit)

	local viewport = card:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		KitVisualService.BuildPreview(viewport, KitVisualService.Showcase(kit))
	end

	return card
end

local function clearReel()
	RunService:UnbindFromRenderStep(CAROUSEL_JOB)
	for _, child in strip:GetChildren() do
		child:Destroy()
	end
end

local function kickMarker()
	markerScale.Scale = 1.35
	TweenService:Create(markerScale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function startCarousel()
	local lastNearest = -1

	RunService:BindToRenderStep(CAROUSEL_JOB, Enum.RenderPriority.Camera.Value, function()
		local width = reel.AbsoluteSize.X
		if width <= 0 then return end

		local centre = reel.AbsolutePosition.X + width * 0.5
		local nearest, nearestDistance = -1, math.huge

		for _, card in strip:GetChildren() do
			if not card:IsA("ImageButton") then continue end

			local cardCentre = card.AbsolutePosition.X + card.AbsoluteSize.X * 0.5
			local offset = cardCentre - centre
			local normalised = math.clamp(math.abs(offset) / (width * 0.5), 0, 1)
			local closeness = 1 - normalised

			local scale = card:FindFirstChild("CarouselScale")
			if scale and scale:IsA("UIScale") then
				scale.Scale = ROLL.MinScale + (ROLL.MaxScale - ROLL.MinScale) * closeness * closeness
			end
			card.Rotation = -(offset / width) * ROLL.CardTilt
			card.ZIndex = 22 + math.floor(closeness * 20)

			local distance = math.abs(offset)
			if distance < nearestDistance then
				nearest, nearestDistance = tonumber(card.Name:match("%d+")) or -1, distance
			end
		end

		if nearest ~= lastNearest then
			if lastNearest ~= -1 then kickMarker() end
			lastNearest = nearest
		end
	end)
end

local function pulseBackdrop(rarity: KitConfig.Rarity)
	backdrop.BackgroundColor3 = rarity.Color
	backdrop.BackgroundTransparency = ROLL.BackdropTransparency
	backdrop.Size = UDim2.fromScale(0.4, 0.26)

	TweenService:Create(backdrop, TweenInfo.new(ROLL.BackdropTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.52, 0.36),
	}):Play()
end

local function shake(strength: number)
	task.spawn(function()
		local finish = os.clock() + ROLL.ShakeTime
		while os.clock() < finish do
			local remaining = (finish - os.clock()) / ROLL.ShakeTime
			local amount = strength * remaining
			reel.Position = reelBase + UDim2.fromScale(
				random:NextNumber(-amount, amount),
				random:NextNumber(-amount, amount)
			)
			RunService.RenderStepped:Wait()
		end
		reel.Position = reelBase
	end)
end

local function setResult(kit: KitConfig.Kit?, duplicate: boolean, refund: number)
	if not kit then
		rarityLabel.Text = ""
		kitNameLabel.Text = ""
		kitDescLabel.Text = ""
		return
	end

	local rarity = KitConfig.GetRarity(kit)
	rarityLabel.Text = string.upper(rarity.Name)
	rarityLabel.TextColor3 = rarity.Accent
	kitNameLabel.Text = string.upper(kit.Name)
	kitNameLabel.TextColor3 = rarity.Accent
	kitDescLabel.Text = if duplicate
		then `Already owned. {refund} gems refunded.`
		else kit.Description
	kitDescLabel.TextColor3 = KitVisualService.Ink

	resultScale.Scale = ROLL.ResultPop
	TweenService:Create(resultScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	for _, label in { rarityLabel, kitNameLabel, kitDescLabel } do
		label.TextTransparency = 1
		TweenService:Create(
			label,
			TweenInfo.new(ROLL.RevealTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 0 }
		):Play()
	end
end

local function flashWinner(card: ImageButton, rarity: KitConfig.Rarity)
	local scale = card:FindFirstChild("CarouselScale")
	if scale and scale:IsA("UIScale") then
		TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = ROLL.MaxScale * 1.12,
		}):Play()
	end

	local stroke = card:FindFirstChild("RarityStroke")
	if not stroke or not stroke:IsA("UIStroke") then return end

	stroke.Color = rarity.Accent
	local grow = TweenService:Create(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Thickness = 6,
	})
	grow:Play()
	grow.Completed:Once(function()
		if not stroke.Parent then return end
		TweenService:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = 3,
			Color = rarity.Accent,
		}):Play()
	end)
end

local function showNotice(text: string)
	notice.Text = text
	notice.Visible = true
	notice.TextTransparency = 1
	TweenService:Create(notice, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()

	task.delay(2.6, function()
		if notice.Text ~= text then return end
		local fade = TweenService:Create(notice, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		})
		fade:Play()
		fade.Completed:Once(function()
			if notice.Text == text then notice.Visible = false end
		end)
	end)
end

local function refreshButton()
	local canRoll = KitStateService:CanRoll()
	local affordable = KitStateService:GetGems() >= ROLL.GemCost

	balance.Text = tostring(KitStateService:GetGems())
	costLabel.Text = tostring(ROLL.GemCost)

	if busy then
		rollLabel.Text = "ROLLING"
		rollLabel.TextColor3 = KitVisualService.Muted
	elseif not canRoll then
		rollLabel.Text = "UNAVAILABLE"
		rollLabel.TextColor3 = KitVisualService.Bad
	elseif affordable then
		rollLabel.Text = "ROLL"
		rollLabel.TextColor3 = KitVisualService.Ink
	else
		rollLabel.Text = KitConfig.Text.CannotAfford
		rollLabel.TextColor3 = KitVisualService.Bad
	end

	rollButton.Interactable = canRoll and affordable and not busy
end

local function spin(kit: KitConfig.Kit, duplicate: boolean, refund: number)
	clearReel()
	setResult(nil, false, 0)
	backdrop.BackgroundTransparency = 1

	local winner
	for index = 1, ROLL.ReelLength do
		local entry = if index == ROLL.WinnerIndex
			then kit
			else weighted[random:NextInteger(1, #weighted)]
		local card = makeReelCard(entry, index)
		if index == ROLL.WinnerIndex then winner = card end
	end

	strip.Position = UDim2.fromScale(offsetFor(1), 0)
	startCarousel()

	local jitter = random:NextNumber(-0.3, 0.3) * ROLL.CardWidth
	local overshoot = TweenService:Create(
		strip,
		TweenInfo.new(ROLL.SpinTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(offsetFor(ROLL.WinnerIndex) + jitter, 0) }
	)
	overshoot:Play()
	overshoot.Completed:Wait()

	local settle = TweenService:Create(
		strip,
		TweenInfo.new(ROLL.SettleTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(offsetFor(ROLL.WinnerIndex), 0) }
	)
	settle:Play()
	settle.Completed:Wait()

	RunService:UnbindFromRenderStep(CAROUSEL_JOB)

	local rarity = KitConfig.GetRarity(kit)
	if winner then flashWinner(winner, rarity) end
	pulseBackdrop(rarity)
	shake(ROLL.ShakeStrength * rarity.Order)
	kickMarker()
	setResult(kit, duplicate, refund)
end

local function roll()
	if busy then return end

	busy = true
	refreshButton()

	local response = KitStateService:RequestRoll()

	if not response.Ok then
		busy = false
		refreshButton()
		showNotice(REASONS[response.Reason] or "The roll could not be completed.")
		return
	end

	local kit = KitConfig.EntriesById[response.KitId]
	if kit then
		spin(kit, response.Duplicate == true, tonumber(response.Refund) or 0)
	end

	busy = false
	refreshButton()
end

rollButton.Activated:Connect(function()
	task.spawn(roll)
end)

myKitsButton.Activated:Connect(function()
	InterfaceService:Open("KitInventory")
end)

KitStateService.GemsChanged:Connect(refreshButton)
KitStateService.KitsChanged:Connect(refreshButton)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then return end
	clearReel()
	setResult(nil, false, 0)
	backdrop.BackgroundTransparency = 1
	reel.Position = reelBase
	notice.Visible = false
end)

InterfaceService.WireMotion(rollButton)
InterfaceService.WireMotion(myKitsButton)
refreshButton()

return KitRollUIService
