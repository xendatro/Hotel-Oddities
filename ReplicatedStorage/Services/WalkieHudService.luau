local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local TouchButtonService = require(ReplicatedStorage.Services.TouchButtonService)
local WalkieTalkieService = require(ReplicatedStorage.Services.WalkieTalkieService)

local WalkieHudService = {}

if not RunService:IsClient() then
	return WalkieHudService
end

local PROMPT = Config.Prompt
local TOUCH = Config.Touch

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild("WalkieHud") :: ScreenGui
local main = gui:WaitForChild("Main") :: Frame
local prompt = main:WaitForChild("Prompt") :: TextLabel

local promptStroke = prompt:FindFirstChildOfClass("UIStroke")

gui.Enabled = true

local powerButton: TextButton? = nil
local raiseButton: TextButton? = nil
local talkButton: TextButton? = nil

if TouchButtonService:IsAvailable() then
	local labels = TOUCH.Labels
	powerButton = TouchButtonService:Create("WalkiePower", labels.Power)
	raiseButton = TouchButtonService:Create("WalkieRaise", labels.Raise)
	talkButton = TouchButtonService:Create("WalkieTalk", labels.Talk)

	powerButton.Activated:Connect(function()
		WalkieTalkieService:TogglePower()
	end)

	raiseButton.Activated:Connect(function()
		WalkieTalkieService:ToggleRaised()
	end)

	talkButton.Activated:Connect(function()
		WalkieTalkieService:ToggleTransmitting()
	end)
end

local promptShown = false
local promptTweens: { Tween } = {}

local function setPromptVisible(visible: boolean)
	if promptShown == visible then return end
	promptShown = visible

	for _, tween in promptTweens do
		tween:Cancel()
	end
	table.clear(promptTweens)

	local info = TweenInfo.new(PROMPT.FadeTime)
	local transparency = if visible then 0 else 1
	table.insert(promptTweens, TweenService:Create(prompt, info, { TextTransparency = transparency }))
	if promptStroke then
		table.insert(promptTweens, TweenService:Create(promptStroke, info, { Transparency = transparency }))
	end
	for _, tween in promptTweens do
		tween:Play()
	end
end

local function step()
	local equipped = WalkieTalkieService:IsEquipped()
	local powered = WalkieTalkieService:IsPowered()
	local raised = WalkieTalkieService:IsRaised()
	local isTouch = UserInputService.PreferredInput == Enum.PreferredInput.Touch

	prompt.Text = if isTouch
		then PROMPT.TouchText
		else string.format(PROMPT.Text, Config.Keys.Power.Name)
	setPromptVisible(equipped and not powered)

	if not (powerButton and raiseButton and talkButton) then return end

	powerButton.Visible = equipped
	raiseButton.Visible = equipped and powered
	talkButton.Visible = equipped and powered and not raised

	TouchButtonService:SetActive(powerButton, powered)
	TouchButtonService:SetActive(raiseButton, raised)
	TouchButtonService:SetActive(talkButton, WalkieTalkieService:IsTransmitting())
end

RunService.Heartbeat:Connect(step)

return WalkieHudService
