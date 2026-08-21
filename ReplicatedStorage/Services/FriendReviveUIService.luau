local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)

local FriendReviveUIService = {}

if not RunService:IsClient() then
	return FriendReviveUIService
end

local Communication = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("Revive")
local Offer = Communication:WaitForChild("Offer") :: RemoteEvent
local Withdraw = Communication:WaitForChild("Withdraw") :: RemoteEvent
local Request = Communication:WaitForChild("Request") :: RemoteEvent

local CONFIG = PerkConfig.FriendRevive
local RENDER_JOB = "FriendReviveCards"
local HOVER_TIME = 0.12
local SLIDE_IN = 0.94

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("ReviveFriendUI") :: ScreenGui
local Holder = ScreenGui:WaitForChild("Holder") :: Frame
local Template = Holder:WaitForChild("Card") :: CanvasGroup

type Card = {
	Root: CanvasGroup,
	Fill: Frame,
	Scale: UIScale,
	Target: Player,
	ExpiresAt: number,
	Window: number,
}

local Cards: { [Player]: Card } = {}
local Order = 0
local Rendering = false

local function tween(instance: Instance, time: number, goal: { [string]: any })
	local motion = TweenService:Create(
		instance,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
	motion:Play()
	return motion
end

local function render()
	local now = os.clock()
	local anyOpen = false

	for target, card in Cards do
		local remaining = math.clamp((card.ExpiresAt - now) / card.Window, 0, 1)
		card.Fill.Size = UDim2.fromScale(remaining, 1)

		if remaining <= 0 then
			FriendReviveUIService:Close(target)
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

function FriendReviveUIService:Close(target: Player)
	local card = Cards[target]
	if not card then return end
	Cards[target] = nil

	tween(card.Scale, CONFIG.CloseTime, { Scale = SLIDE_IN })
	local fade = tween(card.Root, CONFIG.CloseTime, { GroupTransparency = 1 })
	fade.Completed:Once(function()
		card.Root:Destroy()
	end)
end

local function oldest(): Player?
	local found, foundOrder = nil, math.huge
	for target, card in Cards do
		if card.Root.LayoutOrder < foundOrder then
			found, foundOrder = target, card.Root.LayoutOrder
		end
	end
	return found
end

function FriendReviveUIService:Open(target: Player, window: number)
	local existing = Cards[target]
	if existing then
		existing.Window = window
		existing.ExpiresAt = os.clock() + window
		startRendering()
		return
	end

	local open = 0
	for _ in Cards do
		open += 1
	end
	if open >= CONFIG.MaxCards then
		local drop = oldest()
		if drop then
			FriendReviveUIService:Close(drop)
		end
	end

	Order += 1
	local root = Template:Clone()
	root.Name = `Card_{target.UserId}`
	root.LayoutOrder = Order
	root.GroupTransparency = 1
	root.Visible = true
	root.Parent = Holder

	local scale = root:WaitForChild("CardScale") :: UIScale
	scale.Scale = SLIDE_IN

	local nameLabel = root:WaitForChild("PlayerName") :: TextLabel
	nameLabel.Text = target.DisplayName

	local fill = (root:WaitForChild("Bar") :: Frame):WaitForChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(1, 1)

	loadHeadshot(root:WaitForChild("Headshot") :: ImageLabel, target.UserId)

	local revive = root:WaitForChild("Revive") :: TextButton
	local cancel = root:WaitForChild("Cancel") :: TextButton

	wireButton(revive, revive.BackgroundColor3, Color3.fromRGB(192, 38, 46), function()
		Request:FireServer(target)
		FriendReviveUIService:Close(target)
	end)

	wireButton(cancel, cancel.BackgroundColor3, Color3.fromRGB(58, 56, 64), function()
		FriendReviveUIService:Close(target)
	end)

	Cards[target] = {
		Root = root,
		Fill = fill,
		Scale = scale,
		Target = target,
		ExpiresAt = os.clock() + window,
		Window = window,
	}

	tween(root, CONFIG.OpenTime, { GroupTransparency = 0 })
	tween(scale, CONFIG.OpenTime, { Scale = 1 })
	startRendering()
end

Offer.OnClientEvent:Connect(function(target: Player, window: number)
	FriendReviveUIService:Open(target, window)
end)

Withdraw.OnClientEvent:Connect(function(target: Player)
	FriendReviveUIService:Close(target)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	FriendReviveUIService:Close(player)
end)

return FriendReviveUIService
