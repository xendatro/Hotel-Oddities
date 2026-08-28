local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
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
local touch = main:WaitForChild("Touch") :: Frame
local powerButton = touch:WaitForChild("Power") :: TextButton
local raiseButton = touch:WaitForChild("Raise") :: TextButton
local talkButton = touch:WaitForChild("Talk") :: TextButton

local promptStroke = prompt:FindFirstChildOfClass("UIStroke")
local idleBackground = powerButton.BackgroundColor3

powerButton.Activated:Connect(function()
	WalkieTalkieService:TogglePower()
end)

raiseButton.Activated:Connect(function()
	WalkieTalkieService:ToggleRaised()
end)

talkButton.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	WalkieTalkieService:SetTransmitting(true)
end)

talkButton.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	WalkieTalkieService:SetTransmitting(false)
end)

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

local function background(active: boolean): Color3
	return if active then TOUCH.ActiveBackground else idleBackground
end

local function step()
	local equipped = WalkieTalkieService:IsEquipped()
	local powered = WalkieTalkieService:IsPowered()
	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	prompt.Text = if isTouch
		then PROMPT.TouchText
		else string.format(PROMPT.Text, Config.Keys.Power.Name)
	setPromptVisible(equipped and not powered)

	touch.Visible = isTouch and equipped
	powerButton.Visible = touch.Visible
	raiseButton.Visible = touch.Visible and powered
	talkButton.Visible = touch.Visible and powered and not WalkieTalkieService:IsRaised()

	powerButton.BackgroundColor3 = background(powered)
	raiseButton.BackgroundColor3 = background(WalkieTalkieService:IsRaised())
	talkButton.BackgroundColor3 = background(WalkieTalkieService:IsTransmitting())
end

RunService.Heartbeat:Connect(step)

return WalkieHudService
