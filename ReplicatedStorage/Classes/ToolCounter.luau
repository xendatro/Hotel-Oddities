local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)

local ToolCounter = {}
ToolCounter.__index = ToolCounter

local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local UNLIMITED = "∞"

function ToolCounter.new(caption: string)
	local self = setmetatable({}, ToolCounter)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ToolCounter"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Count"
	label.AnchorPoint = Vector2.new(1, 1)
	label.Position = UDim2.new(1, -28, 1, -40)
	label.Size = UDim2.fromOffset(240, 34)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextSize = 26
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = InventoryConfig.Colors.Text
	label.TextStrokeTransparency = 0.4
	label.Text = caption
	label.Parent = gui

	self.Gui = gui
	self.Label = label
	self.Caption = caption

	return self
end

function ToolCounter:Set(remaining: number?, total: number?)
	if not self.Label.Parent then return end

	local amount = if remaining then `{remaining}/{total or remaining}` else UNLIMITED
	self.Label.Text = `{self.Caption}  {amount}`
end

function ToolCounter:Destroy()
	self.Gui:Destroy()
end

return ToolCounter
