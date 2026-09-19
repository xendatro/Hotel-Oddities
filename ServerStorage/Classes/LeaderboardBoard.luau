local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EscapeConfig = require(ReplicatedStorage.Configs.EscapeConfig)
local MathService = require(ReplicatedStorage.Services.MathService)

local LeaderboardBoard = {}
LeaderboardBoard.__index = LeaderboardBoard

local Config = EscapeConfig.Leaderboard
local Layout = Config.Layout

export type Entry = {
	UserId: number,
	DisplayName: string,
	Username: string,
	Escapes: number,
}

local function faceSize(part: BasePart, face: Enum.NormalId): (number, number)
	local size = part.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	end
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.X, size.Z
	end
	return size.X, size.Y
end

local function ratioOf(template: GuiObject): number
	local constraint = template:FindFirstChildOfClass("UIAspectRatioConstraint")
	if constraint then
		return constraint.AspectRatio
	end
	local size = template.Size
	if size.Y.Scale > 0 then
		return (size.X.Scale * 16) / (size.Y.Scale * 9)
	end
	return 1
end

local function find(root: Instance, name: string, class: string): GuiObject
	local found = root:FindFirstChild(name, true)
	if not found or not found:IsA(class) then
		error(`LeaderboardBoard: {root:GetFullName()} has no {class} named {name}`)
	end
	return found :: GuiObject
end

local function cloneImage(source: ImageLabel, name: string): ImageLabel
	local clone = source:Clone()
	clone.Name = name
	clone:ClearAllChildren()
	clone.BackgroundTransparency = 1
	clone.Visible = true
	return clone
end

local function cloneText(source: TextLabel, name: string, alignment: Enum.TextXAlignment, textSize: number): TextLabel
	local clone = source:Clone()
	clone.Name = name
	clone:ClearAllChildren()
	clone.BackgroundTransparency = 1
	clone.TextScaled = false
	clone.TextWrapped = false
	clone.TextSize = textSize
	clone.TextTruncate = Enum.TextTruncate.AtEnd
	clone.TextXAlignment = alignment
	clone.TextYAlignment = Enum.TextYAlignment.Center
	clone.Text = ""
	clone.Visible = true
	return clone
end

function LeaderboardBoard.new(part: BasePart, design: Instance)
	local self = setmetatable({}, LeaderboardBoard)

	local templates = Config.Templates
	local plate = find(design, templates.TitlePlate, "ImageLabel") :: ImageLabel
	local title = find(design, templates.TitleText, "TextLabel") :: TextLabel
	local row = find(design, templates.Row, "ImageLabel") :: ImageLabel
	local headshot = find(design, templates.Headshot, "ImageLabel") :: ImageLabel
	local text = find(design, templates.Text, "TextLabel") :: TextLabel

	local width, height = faceSize(part, Config.Face)
	local canvasHeight = height * Config.PixelsPerStud

	local gui = Instance.new("SurfaceGui")
	gui.Name = Config.Gui
	gui.Face = Config.Face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Config.PixelsPerStud
	gui.LightInfluence = Config.LightInfluence
	gui.Brightness = Config.Brightness
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false

	local plateHeight = (Layout.TitleWidth * width / ratioOf(plate)) / height
	local plateClone = cloneImage(plate, "Title")
	plateClone.AnchorPoint = Vector2.new(0.5, 0)
	plateClone.Position = UDim2.fromScale(0.5, Layout.TopMargin)
	plateClone.Size = UDim2.fromScale(Layout.TitleWidth, plateHeight)
	plateClone.Parent = gui

	local titleClone = cloneText(title, "Text", Enum.TextXAlignment.Center, Layout.TitleTextHeight * plateHeight * canvasHeight)
	titleClone.AnchorPoint = Vector2.new(0.5, 0.5)
	titleClone.Position = UDim2.fromScale(0.5, 0.5)
	titleClone.Size = UDim2.fromScale(Layout.TitleTextWidth, Layout.TitleTextHeight)
	titleClone.Text = Config.Title
	titleClone.Parent = plateClone

	local rowHeight = (Layout.RowWidth * width / ratioOf(row)) / height * Layout.RowStretch
	local top = Layout.TopMargin + plateHeight + Layout.TitleGap
	local count = Config.TopCount
	local gap = if count > 1 then (1 - Layout.BottomMargin - top - count * rowHeight) / (count - 1) else 0
	local headshotWidth = Layout.HeadshotHeight * rowHeight * height / (Layout.RowWidth * width)
	local nameLeft = Layout.HeadshotLeft + headshotWidth + Layout.NameGap
	local textSize = Layout.TextHeight * rowHeight * canvasHeight

	self.Rows = {}
	for index = 1, count do
		local rowClone = cloneImage(row, `Row{index}`)
		rowClone.AnchorPoint = Vector2.new(0.5, 0)
		rowClone.Position = UDim2.fromScale(0.5, top + (index - 1) * (rowHeight + gap))
		rowClone.Size = UDim2.fromScale(Layout.RowWidth, rowHeight)
		rowClone.Parent = gui

		local headshotClone = cloneImage(headshot, "Headshot")
		headshotClone.AnchorPoint = Vector2.new(0, 0.5)
		headshotClone.Position = UDim2.fromScale(Layout.HeadshotLeft, 0.5)
		headshotClone.Size = UDim2.fromScale(headshotWidth, Layout.HeadshotHeight)
		headshotClone.Image = ""
		headshotClone.Parent = rowClone

		local nameClone = cloneText(text, "Name", Enum.TextXAlignment.Left, textSize)
		nameClone.AnchorPoint = Vector2.new(0, 0.5)
		nameClone.Position = UDim2.fromScale(nameLeft, 0.5)
		nameClone.Size = UDim2.fromScale(Layout.ScoreLeft - nameLeft - Layout.NameGap, Layout.TextHeight)
		nameClone.Parent = rowClone

		local scoreClone = cloneText(text, "Score", Enum.TextXAlignment.Right, textSize)
		scoreClone.AnchorPoint = Vector2.new(0, 0.5)
		scoreClone.Position = UDim2.fromScale(Layout.ScoreLeft, 0.5)
		scoreClone.Size = UDim2.fromScale(Layout.ScoreRight - Layout.ScoreLeft, Layout.TextHeight)
		scoreClone.Parent = rowClone

		table.insert(self.Rows, {
			Frame = rowClone,
			Headshot = headshotClone,
			Name = nameClone,
			Score = scoreClone,
		})
	end

	gui.Parent = part
	self.Gui = gui
	return self
end

function LeaderboardBoard:SetEntries(entries: { Entry })
	for index, row in self.Rows do
		local entry = entries[index]
		if entry then
			row.Headshot.Image = string.format(Config.Headshot, entry.UserId)
			row.Name.Text = string.format(Config.NameFormat, entry.DisplayName, entry.Username)
			row.Score.Text = MathService.Comma(entry.Escapes)
		else
			row.Headshot.Image = ""
			row.Name.Text = ""
			row.Score.Text = ""
		end
	end
end

function LeaderboardBoard:Destroy()
	self.Gui:Destroy()
	self.Rows = {}
end

return LeaderboardBoard
