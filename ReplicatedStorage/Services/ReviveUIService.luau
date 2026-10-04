local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)
local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local ReviveUIService = {}

if not RunService:IsClient() then
	return ReviveUIService
end

local Offer = CommunicationService.Get("Revive", "Offer") :: RemoteEvent
local Withdraw = CommunicationService.Get("Revive", "Withdraw") :: RemoteEvent
local Request = CommunicationService.Get("Revive", "Request") :: RemoteEvent
local Prompt = CommunicationService.Get("Revive", "Prompt") :: RemoteEvent
local Show = CommunicationService.Get("Death", "Show") :: RemoteEvent

local CONFIG = PerkConfig.FriendRevive
local REVIVE = DeathConfig.Revive
local RENDER_JOB = "ReviveCards"
local HOVER_TIME = 0.12
local SLIDE_IN = 0.94
local SELF_ORDER = 1e6

local LocalPlayer = Players.LocalPlayer
local PlayerGui = GuiBuilderService.GetPlayerGui()
local ScreenGui = PlayerGui:WaitForChild("ReviveUI") :: ScreenGui
local Holder = ScreenGui:WaitForChild("Holder") :: Frame
local Template = Holder:WaitForChild("Card") :: CanvasGroup

type Mode = "Keyboard" | "Gamepad" | "Touch"

type Card = {
	Root: CanvasGroup,
	Fill: Frame,
	Scale: UIScale,
	Key: Frame,
	KeyLabel: TextLabel,
	Target: Player,
	Token: number?,
	ExpiresAt: number,
	Window: number,
}

local Cards: { [Player]: Card } = {}
local Order = 0
local Rendering = false
local Mode: Mode = "Keyboard"

local function modeFor(inputType: Enum.UserInputType): Mode?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	if inputType.Name:find("Gamepad") then
		return "Gamepad"
	end
	if inputType == Enum.UserInputType.Keyboard or inputType.Name:find("Mouse") then
		return "Keyboard"
	end
	return nil
end

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function tween(instance: Instance, time: number, goal: { [string]: any })
	local motion = TweenService:Create(
		instance,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
	motion:Play()
	return motion
end

local function keyTarget(): Card?
	local own = Cards[LocalPlayer]
	if own then return own end

	local found: Card? = nil
	for _, card in Cards do
		if not found or card.Root.LayoutOrder > found.Root.LayoutOrder then
			found = card
		end
	end
	return found
end

local function refreshKeys()
	local target = keyTarget()
	local label = if Mode == "Gamepad" then REVIVE.GamepadLabel else REVIVE.KeyLabel
	for _, card in Cards do
		card.KeyLabel.Text = label
		card.Key.Visible = Mode ~= "Touch" and card == target
	end
end

local function render()
	local now = os.clock()
	local anyOpen = false

	for target, card in Cards do
		local remaining = math.clamp((card.ExpiresAt - now) / card.Window, 0, 1)
		card.Fill.Size = UDim2.fromScale(remaining, 1)

		if remaining <= 0 then
			ReviveUIService:Close(target)
		else
			anyOpen = true
		end
	end

	if not anyOpen then
		Rendering = false
		RunService:UnbindFromRenderStep(RENDER_JOB)
	end
end

local function startRendering()
	if Rendering then return end
	Rendering = true
	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Last.Value, render)
end

local function wireButton(button: TextButton, base: Color3, hovered: Color3, activated: () -> ())
	button.MouseEnter:Connect(function()
		tween(button, HOVER_TIME, { BackgroundColor3 = hovered })
	end)
	button.MouseLeave:Connect(function()
		tween(button, HOVER_TIME, { BackgroundColor3 = base })
	end)
	button.Activated:Connect(activated)
end

local function loadHeadshot(image: ImageLabel, userId: number)
	task.spawn(function()
		local success, content = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
		if success and image.Parent then
			image.Image = content
		end
	end)
end

local function activate(target: Player)
	local card = Cards[target]
	if not card then return end

	if target == LocalPlayer then
		if card.Token then
			Prompt:FireServer(card.Token)
		end
		return
	end

	Request:FireServer(target)
	ReviveUIService:Close(target)
end

local function oldestFriend(): Player?
	local found, foundOrder = nil, math.huge
	for target, card in Cards do
		if target ~= LocalPlayer and card.Root.LayoutOrder < foundOrder then
			found, foundOrder = target, card.Root.LayoutOrder
		end
	end
	return found
end

function ReviveUIService:Close(target: Player)
	local card = Cards[target]
	if not card then return end
	Cards[target] = nil
	refreshKeys()

	tween(card.Scale, CONFIG.CloseTime, { Scale = SLIDE_IN })
	local fade = tween(card.Root, CONFIG.CloseTime, { GroupTransparency = 1 })
	fade.Completed:Once(function()
		card.Root:Destroy()
	end)
end

function ReviveUIService:Open(target: Player, window: number, token: number?)
	local existing = Cards[target]
	if existing then
		existing.Window = window
		existing.ExpiresAt = os.clock() + window
		existing.Token = token or existing.Token
		startRendering()
		return
	end

	local own = target == LocalPlayer
	if not own then
		local open = 0
		for player in Cards do
			if player ~= LocalPlayer then
				open += 1
			end
		end
		if open >= CONFIG.MaxCards then
			local drop = oldestFriend()
			if drop then
				ReviveUIService:Close(drop)
			end
		end
	end

	Order += 1
	local root = Template:Clone()
	root.Name = `Card_{target.UserId}`
	root.LayoutOrder = if own then SELF_ORDER else Order
	root.GroupTransparency = 1
	root.Visible = true
	root.Parent = Holder

	local scale = root:WaitForChild("CardScale") :: UIScale
	scale.Scale = SLIDE_IN

	local nameLabel = root:WaitForChild("PlayerName") :: TextLabel
	nameLabel.Text = target.DisplayName

	if own then
		(root:WaitForChild("Prompt") :: TextLabel).Text = REVIVE.SelfPrompt
	end

	local fill = (root:WaitForChild("Bar") :: Frame):WaitForChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(1, 1)

	loadHeadshot(root:WaitForChild("Headshot") :: ImageLabel, target.UserId)

	local revive = root:WaitForChild("Revive") :: TextButton
	local cancel = root:WaitForChild("Cancel") :: TextButton
	local key = revive:WaitForChild("Key") :: Frame

	wireButton(revive, revive.BackgroundColor3, Color3.fromRGB(192, 38, 46), function()
		activate(target)
	end)

	wireButton(cancel, cancel.BackgroundColor3, Color3.fromRGB(58, 56, 64), function()
		ReviveUIService:Close(target)
	end)

	Cards[target] = {
		Root = root,
		Fill = fill,
		Scale = scale,
		Key = key,
		KeyLabel = key:WaitForChild("Label") :: TextLabel,
		Target = target,
		Token = token,
		ExpiresAt = os.clock() + window,
		Window = window,
	}
	refreshKeys()

	tween(root, CONFIG.OpenTime, { GroupTransparency = 0 })
	tween(scale, CONFIG.OpenTime, { Scale = 1 })
	startRendering()
end

Mode = modeFor(UserInputService:GetLastInputType()) or (if isTouchDevice() then "Touch" else "Keyboard")
Holder.Position = if isTouchDevice() then REVIVE.TouchPosition else REVIVE.Position
ScreenGui.Enabled = true

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	local mode = modeFor(inputType)
	if not mode or mode == Mode then return end
	Mode = mode
	refreshKeys()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode ~= REVIVE.Key and input.KeyCode ~= REVIVE.GamepadKey then return end

	local card = keyTarget()
	if card then
		activate(card.Target)
	end
end)

Show.OnClientEvent:Connect(function(_causeId: string?, token: number)
	ReviveUIService:Open(LocalPlayer, REVIVE.Window, token)
end)

Offer.OnClientEvent:Connect(function(target: Player, window: number)
	ReviveUIService:Open(target, window)
end)

Withdraw.OnClientEvent:Connect(function(target: Player)
	ReviveUIService:Close(target)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	ReviveUIService:Close(player)
end)

return ReviveUIService
