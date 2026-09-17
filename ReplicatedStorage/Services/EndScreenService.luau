local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EndingConfig = require(ReplicatedStorage.Configs.EndingConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)

local EndScreenService = {}

if not RunService:IsClient() then
	return EndScreenService
end

local TEXT = EndingConfig.Text
local TIMING = EndingConfig.Timing
local MOTION = EndingConfig.Motion

local Show = CommunicationService.Get(EndingConfig.Remotes.Folder, EndingConfig.Remotes.Show) :: RemoteEvent
local Hide = CommunicationService.Get(EndingConfig.Remotes.Folder, EndingConfig.Remotes.Hide) :: RemoteEvent
local PlayAgain = CommunicationService.Get(EndingConfig.Remotes.Folder, EndingConfig.Remotes.PlayAgain) :: RemoteEvent

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild(EndingConfig.Gui) :: ScreenGui
local main = gui:WaitForChild("Main") :: Frame
local card = main:WaitForChild("Card") :: Frame
local paper = card:WaitForChild("Paper") :: ImageLabel
local logo = paper:WaitForChild("Logo") :: ImageLabel
local chip = paper:WaitForChild("TitleChip") :: ImageLabel
local chipLabel = chip:WaitForChild("Label") :: TextLabel
local subtitle = paper:WaitForChild("Subtitle") :: TextLabel
local postIt = paper:WaitForChild("PostIt") :: ImageLabel
local chapterLabel = postIt:WaitForChild("Label") :: TextLabel
local chapterNote = postIt:WaitForChild("Note") :: TextLabel
local button = paper:WaitForChild("PlayAgainButton") :: ImageButton
local buttonLabel = button:WaitForChild("Label") :: TextLabel

local function scaleOf(object: GuiObject, name: string): UIScale
	local existing = object:FindFirstChild(name)
	if existing and existing:IsA("UIScale") then return existing end

	local scale = Instance.new("UIScale")
	scale.Name = name
	scale.Parent = object
	return scale
end

local logoScale = scaleOf(logo, "RevealScale")
local chipScale = scaleOf(chip, "RevealScale")
local postItScale = scaleOf(postIt, "RevealScale")

local buttonBase = button.Position
local generation = 0
local visible = false
local sending = false
local tweens: { Tween } = {}

local function play(object: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(object, info, goal)
	table.insert(tweens, tween)
	tween:Play()
	return tween
end

local function cancelTweens()
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
end

local function info(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
end

local function setButtonShown(shown: boolean)
	local transparency = if shown then 0 else 1
	button.ImageTransparency = transparency
	buttonLabel.TextTransparency = transparency
	button.Interactable = shown
end

local function reset()
	cancelTweens()
	main.BackgroundColor3 = EndingConfig.Colors.Backdrop
	main.BackgroundTransparency = 1
	card.Position = UDim2.fromScale(0.5, MOTION.CardStartY)
	card.Rotation = MOTION.CardStartRotation
	logo.ImageTransparency = 1
	logoScale.Scale = MOTION.LogoStartScale
	chipScale.Scale = 0
	chipLabel.Text = TEXT.Title
	subtitle.Text = ""
	postItScale.Scale = 0
	postIt.Rotation = MOTION.PostItStartRotation
	chapterLabel.Text = TEXT.Chapter
	chapterNote.Text = TEXT.ChapterNote
	button.Position = buttonBase + UDim2.fromScale(0, MOTION.ButtonRise)
	buttonLabel.Text = TEXT.PlayAgain
	setButtonShown(false)
	sending = false
end

local function typeOut(text: string, current: number)
	for index = 1, #text do
		if generation ~= current then return end
		subtitle.Text = text:sub(1, index) .. TEXT.Caret
		task.wait(TIMING.TypeInterval)
	end

	task.spawn(function()
		local shown = true
		while generation == current and visible do
			shown = not shown
			subtitle.Text = text .. (if shown then TEXT.Caret else "")
			task.wait(TIMING.CaretBlink)
		end
	end)
end

local function sequence(current: number)
	play(main, info(TIMING.Backdrop), { BackgroundTransparency = 0 })

	task.wait(TIMING.CardDelay)
	if generation ~= current then return end
	play(card, info(TIMING.Card, Enum.EasingStyle.Back), {
		Position = UDim2.fromScale(0.5, MOTION.CardEndY),
		Rotation = MOTION.CardRotation,
	})

	task.wait(math.max(TIMING.LogoDelay - TIMING.CardDelay, 0))
	if generation ~= current then return end
	play(logo, info(TIMING.Logo), { ImageTransparency = 0 })
	play(logoScale, info(TIMING.Logo, Enum.EasingStyle.Back), { Scale = 1 })

	task.wait(math.max(TIMING.ChipDelay - TIMING.LogoDelay, 0))
	if generation ~= current then return end
	play(chipScale, info(TIMING.Chip, Enum.EasingStyle.Back), { Scale = 1 })

	task.wait(math.max(TIMING.TypeDelay - TIMING.ChipDelay, 0))
	if generation ~= current then return end
	typeOut(TEXT.Subtitle, current)
	if generation ~= current then return end

	task.wait(TIMING.PostItGap)
	if generation ~= current then return end
	play(postItScale, info(TIMING.PostIt, Enum.EasingStyle.Back), { Scale = 1 })
	play(postIt, info(TIMING.PostIt, Enum.EasingStyle.Back), { Rotation = MOTION.PostItRotation })

	task.wait(TIMING.ButtonGap)
	if generation ~= current then return end
	button.Interactable = false
	play(button, info(TIMING.Button, Enum.EasingStyle.Back), { Position = buttonBase, ImageTransparency = 0 })
	play(buttonLabel, info(TIMING.Button), { TextTransparency = 0 })

	task.wait(TIMING.Button)
	if generation ~= current then return end
	button.Interactable = true
end

function EndScreenService:IsVisible(): boolean
	return visible
end

function EndScreenService:Show()
	generation += 1
	local current = generation
	visible = true

	reset()
	InterfaceService:Close()
	InterfaceService:SetMouseUnlocked(true, true)
	gui.Enabled = true

	task.spawn(sequence, current)
end

function EndScreenService:Hide()
	if not visible then return end
	generation += 1
	visible = false
	cancelTweens()
	button.Interactable = false

	local fade = info(TIMING.FadeOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	play(card, fade, { Position = UDim2.fromScale(0.5, MOTION.CardExitY), Rotation = MOTION.CardStartRotation })
	local backdrop = play(main, fade, { BackgroundTransparency = 1 })
	backdrop.Completed:Once(function()
		if visible then return end
		gui.Enabled = false
		InterfaceService:SetMouseUnlocked(false, false)
		reset()
	end)
end

button.Activated:Connect(function()
	if not visible or sending then return end
	sending = true
	button.Interactable = false
	buttonLabel.Text = TEXT.Working
	PlayAgain:FireServer()
end)

Show.OnClientEvent:Connect(function()
	EndScreenService:Show()
end)

Hide.OnClientEvent:Connect(function()
	EndScreenService:Hide()
end)

InterfaceService.WireMotion(button)
gui.Enabled = false
reset()

return EndScreenService
