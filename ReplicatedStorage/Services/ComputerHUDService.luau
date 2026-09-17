local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ComputerHUDService = {}

if not RunService:IsClient() then
	return ComputerHUDService
end

local ComputerAssets = require(ReplicatedStorage.Configs.ComputerAssets)
local ComputerChipConfig = require(ReplicatedStorage.Configs.ComputerChipConfig)
local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local ComputerService = require(ReplicatedStorage.Services.ComputerService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local HUD = ComputerConfig.HUD

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild(HUD.Name) :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local title = design:WaitForChild("Title"):WaitForChild("Label") :: TextLabel
local rowsFrame = design:WaitForChild("Rows") :: Frame
local footer = design:WaitForChild("Footer") :: TextLabel

type Row = {
	Entry: { Key: string, Color: Color3, RoomName: string, ToolName: string },
	Icon: ImageLabel,
	Check: ImageLabel,
	Label: TextLabel,
}

local rows: { Row } = {}
for _, entry in ComputerChipConfig.Colors do
	local frame = rowsFrame:WaitForChild(entry.Key) :: Frame
	local icon = frame:WaitForChild("Icon") :: ImageLabel
	if ComputerAssets.MonitorIcon ~= "" then
		icon.Image = ComputerAssets.MonitorIcon
	end
	icon.ImageColor3 = entry.Color
	table.insert(rows, {
		Entry = entry,
		Icon = icon,
		Check = frame:WaitForChild("Check") :: ImageLabel,
		Label = frame:WaitForChild("Label") :: TextLabel,
	})
end

title.Text = HUD.Title
local footerColor = footer.TextColor3
local complete = false

local function refresh()
	local colors = ComputerService:GetColors()
	local _, total = ComputerService:GetProgress()
	gui.Enabled = total > 0

	local done = 0
	for _, row in rows do
		local finished = colors[row.Entry.Key] == true
		if finished then done += 1 end
		row.Check.Visible = finished
		row.Icon.ImageTransparency = if finished then 0 else HUD.PendingIconTransparency
		row.Label.Text = if finished then `<s>{row.Entry.Key}</s>` else row.Entry.Key
	end

	complete = ComputerService:IsExitUnlocked()
	footer.Text = if complete then HUD.UnlockedText else string.format(HUD.LockedText, done, #rows)
	if not complete then footer.TextColor3 = footerColor end
end

ComputerService.Changed:Connect(refresh)
refresh()

RunService.Heartbeat:Connect(function()
	if not complete or not gui.Enabled then return end
	local pulse = (math.sin(os.clock() * HUD.FlashSpeed * math.pi * 2) + 1) / 2
	footer.TextColor3 = footerColor:Lerp(HUD.Complete, pulse)
end)

function ComputerHUDService:GetProgress(): (number, number)
	return ComputerService:GetProgress()
end

return ComputerHUDService
