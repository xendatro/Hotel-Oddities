local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OverheadNameConfig = require(ReplicatedStorage.Configs.OverheadNameConfig)

local OverheadName = {}
OverheadName.__index = OverheadName

function OverheadName.Format(player: Player): string
	if player.HasVerifiedBadge then
		return `{player.DisplayName} {utf8.char(OverheadNameConfig.VerifiedGlyph)}`
	end
	return player.DisplayName
end

local function build(parent: Instance): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OverheadName"
	billboard.ResetOnSpawn = false
	billboard.AlwaysOnTop = OverheadNameConfig.AlwaysOnTop
	billboard.LightInfluence = 0
	billboard.ClipsDescendants = false
	billboard.Size = UDim2.fromOffset(OverheadNameConfig.Size.X, OverheadNameConfig.Size.Y)
	billboard.ExtentsOffsetWorldSpace = OverheadNameConfig.ExtentsOffset
	billboard.StudsOffsetWorldSpace = OverheadNameConfig.StudsOffset
	billboard.MaxDistance = OverheadNameConfig.MaxDistance
	billboard.Enabled = false
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "DisplayName"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = OverheadNameConfig.Font
	label.TextSize = OverheadNameConfig.TextSize
	label.TextColor3 = OverheadNameConfig.TextColor
	label.TextStrokeColor3 = OverheadNameConfig.StrokeColor
	label.TextStrokeTransparency = OverheadNameConfig.StrokeTransparency
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = billboard

	return billboard, label
end

local function setUpConnections(self)
	self.Connections = {}

	local model = self.Model

	self.Connections.ChildAdded = model.ChildAdded:Connect(function(child)
		if child.Name == "Head" or child:IsA("Humanoid") then
			self:_Bind()
		end
	end)
	self.Connections.ChildRemoved = model.ChildRemoved:Connect(function(child)
		if child == self.Head or child == self.Humanoid then
			self:_Bind()
		end
	end)
	self.Connections.DisplayName = self.Player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		self:_Refresh()
	end)
	self.Connections.Verified = self.Player:GetPropertyChangedSignal("HasVerifiedBadge"):Connect(function()
		self:_Refresh()
	end)
end

function OverheadName.new(model: Model, player: Player, parent: Instance)
	local self = setmetatable({}, OverheadName)

	self.Model = model
	self.Player = player
	self.Head = nil :: BasePart?
	self.Humanoid = nil :: Humanoid?
	self.HumanoidConnections = {}
	self.Billboard, self.Label = build(parent)

	setUpConnections(self)
	self:_Refresh()
	self:_Bind()

	return self
end

function OverheadName:_Refresh()
	self.Label.Text = OverheadName.Format(self.Player)
end

function OverheadName:_UpdateShown()
	local humanoid = self.Humanoid
	self.Billboard.Enabled = self.Head ~= nil and humanoid ~= nil and humanoid.Health > 0
end

function OverheadName:_Bind()
	for _, connection in self.HumanoidConnections do
		connection:Disconnect()
	end
	self.HumanoidConnections = {}

	local head = self.Model:FindFirstChild("Head")
	local humanoid = self.Model:FindFirstChildOfClass("Humanoid")
	self.Head = if head and head:IsA("BasePart") then head else nil
	self.Humanoid = humanoid
	self.Billboard.Adornee = self.Head

	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		table.insert(self.HumanoidConnections, humanoid:GetPropertyChangedSignal("DisplayDistanceType"):Connect(function()
			if humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end))
		table.insert(self.HumanoidConnections, humanoid.HealthChanged:Connect(function()
			self:_UpdateShown()
		end))
	end

	self:_UpdateShown()
end

function OverheadName:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for _, connection in self.HumanoidConnections do
		connection:Disconnect()
	end
	self.Connections = {}
	self.HumanoidConnections = {}
	self.Billboard:Destroy()
end

return OverheadName
