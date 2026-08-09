local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)

--- @class ToolCounter
--- The "MARKERS 15/20" readout in the corner of the screen while a consumable tool is out.
---
--- Client only, and deliberately generic: anything with a stack worth watching while you use it can
--- put one up. Sits bottom right, clear of the hotbar and the backpack panel.
local ToolCounter = {}
ToolCounter.__index = ToolCounter

-- Font.fromEnum does not resolve the Montserrat enums to Montserrat, so the family is named outright.
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local UNLIMITED = "∞"

--- @param caption string -- what is being counted, shown before the number
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

--- Shows `remaining` of `total`, or the infinity mark when called with nothing.
function ToolCounter:Set(remaining: number?, total: number?)
	if not self.Label.Parent then return end

	local amount = if remaining then `{remaining}/{total or remaining}` else UNLIMITED
	self.Label.Text = `{self.Caption}  {amount}`
end

function ToolCounter:Destroy()
	self.Gui:Destroy()
end

return ToolCounter
