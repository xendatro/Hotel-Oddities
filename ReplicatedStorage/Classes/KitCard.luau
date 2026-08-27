local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local KitVisualService = require(ReplicatedStorage.Services.KitVisualService)

local CARD = KitConfig.Animation.Card

local KitCard = {}
KitCard.__index = KitCard

export type KitCard = typeof(setmetatable({} :: {
	Kit: KitConfig.Kit,
	Holder: Frame,
	Button: ImageButton,
	Hovered: boolean,
	Pressed: boolean,
	Selected: boolean,
	Tween: Tween?,
	Connections: { [string]: RBXScriptConnection },
}, KitCard))

local function setUpConnections(self: KitCard, onSelect: (KitConfig.Kit) -> ())
	local button = self.Button

	return {
		Enter = button.MouseEnter:Connect(function()
			self.Hovered = true
			self:Pose()
		end),
		Leave = button.MouseLeave:Connect(function()
			self.Hovered = false
			self.Pressed = false
			self:Pose()
		end),
		Down = button.MouseButton1Down:Connect(function()
			self.Pressed = true
			self:Pose()
		end),
		Up = button.MouseButton1Up:Connect(function()
			self.Pressed = false
			self:Pose()
		end),
		Activated = button.Activated:Connect(function()
			onSelect(self.Kit)
		end),
	}
end

function KitCard.new(
	template: ImageButton,
	parent: Instance,
	kit: KitConfig.Kit,
	order: number,
	onSelect: (KitConfig.Kit) -> ()
): KitCard
	local holder = Instance.new("Frame")
	holder.Name = kit.Id
	holder.BackgroundTransparency = 1
	holder.Size = template.Size
	holder.LayoutOrder = order
	holder.Parent = parent

	local button = template:Clone()
	button.Name = "Card"
	button.Visible = true
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = holder

	local self = setmetatable({
		Kit = kit,
		Holder = holder,
		Button = button,
		Hovered = false,
		Pressed = false,
		Selected = false,
		Tween = nil,
		Connections = {},
	}, KitCard) :: KitCard

	KitVisualService.DressCard(button, kit)

	local viewport = button:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		KitVisualService.BuildPreview(viewport, KitVisualService.Showcase(kit))
	end

	self.Connections = setUpConnections(self, onSelect)
	return self
end

function KitCard:Pose(override: TweenInfo?)
	local scale, lift, tilt = 1, 0, 0
	local duration = CARD.SettleTime
	local style = Enum.EasingStyle.Back

	if self.Pressed then
		scale, duration, style = CARD.PressScale, CARD.PressTime, Enum.EasingStyle.Quad
	elseif self.Hovered then
		scale, lift, tilt, duration = CARD.HoverScale, CARD.HoverLift, CARD.HoverTilt, CARD.HoverTime
	elseif self.Selected then
		scale, lift, tilt = CARD.SelectedScale, CARD.SelectedLift, CARD.SelectedTilt
	end

	if self.Tween then self.Tween:Cancel() end
	self.Tween = TweenService:Create(
		self.Button,
		override or TweenInfo.new(duration, style, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromScale(scale, scale),
			Position = UDim2.fromScale(0.5, 0.5 - lift),
			Rotation = tilt,
		}
	)
	self.Tween:Play()
end

function KitCard:SetSelected(selected: boolean)
	if self.Selected == selected then return end
	self.Selected = selected
	self:Pose()
end

function KitCard:SetStatus(text: string, dimmed: boolean, color: Color3?)
	KitVisualService.SetCardStatus(self.Button, text, dimmed, color)
end

function KitCard:Deal(delay: number)
	if self.Tween then self.Tween:Cancel() end

	self.Button.Size = UDim2.fromScale(CARD.EnterScale, CARD.EnterScale)
	self.Button.Position = UDim2.fromScale(0.5, 0.5 + CARD.EnterDrop)
	self.Button.Rotation = 0

	task.delay(delay, function()
		if self.Button.Parent ~= self.Holder then return end
		self:Pose(TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end)
end

function KitCard:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	if self.Tween then self.Tween:Cancel() end
	self.Holder:Destroy()
end

return KitCard
