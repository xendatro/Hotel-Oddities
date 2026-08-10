--- The card that appears when a friend of yours dies: their face, their name, a bar that drains for
--- `Window` seconds, and the two buttons. Pressing revive asks the server to open the product
--- prompt; the server re-checks everything before it does, so nothing here is trusted.
---
--- Deliberately small and off to one side. It arrives during somebody else's worst moment of the
--- round, usually while the player it is shown to is being chased by the same thing, and a card that
--- has to be dealt with before you can see the hallway again would cost more deaths than it sells.
---
--- The template lives in `StarterGui.ReviveFriendUI.Holder.Card` rather than being built here,
--- because it is a piece of art rather than a piece of behaviour -- restyling one should not mean
--- editing this file.

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
local SLIDE_IN = 0.94 -- scale a card arrives at before settling

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

--- Drawing ----------------------------------------------------------------------------------------

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

	-- `Close` drops the entry it is given, which is allowed mid-iteration and is what lets an expired
	-- card be taken down from inside the same pass that noticed it had run out.
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

--- Buttons ----------------------------------------------------------------------------------------

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

--- Opening and closing ----------------------------------------------------------------------------

--- Takes a card down, whether its bar ran out, the player dismissed it, or the offer was withdrawn.
--- Safe to call on a player with no card up.
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

-- The oldest card on screen, by the layout order it was given when it opened.
local function oldest(): Player?
	local found, foundOrder = nil, math.huge
	for target, card in Cards do
		if card.Root.LayoutOrder < foundOrder then
			found, foundOrder = target, card.Root.LayoutOrder
		end
	end
	return found
end

--- Puts a card up for `target`, or restarts the countdown on the one already there.
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
	-- Named apart from the template so the two are never confused by anything walking the holder.
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
		-- Closed on press rather than on the purchase landing: the Robux prompt covers the screen
		-- anyway, and a card still counting down behind it would only expire while it was hidden.
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
