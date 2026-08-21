local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EffectsHUDConfig = require(ReplicatedStorage.Configs.EffectsHUDConfig)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

local EffectsHUDService = {}

if not RunService:IsClient() then
	return EffectsHUDService
end

local COLORS = EffectsHUDConfig.Colors
local TRANSPARENCY = EffectsHUDConfig.Transparency

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local panel

local function build()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EffectsHudGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	panel = Instance.new("Frame")
	panel.Name = "Effects"
	panel.BackgroundTransparency = 1
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -EffectsHUDConfig.EdgeMargin, 0.5, 0)
	panel.Size = UDim2.fromOffset(EffectsHUDConfig.TileSize, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, EffectsHUDConfig.TilePadding)
	layout.Parent = panel
end

type Entry = {
	Frame: Frame,
	Bright: Frame?,
	Label: TextLabel,
	EndsAt: number,
	Duration: number,
}

local Entries: { [string]: Entry } = {}
local nextOrder = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function buildTile(effectName: string): Entry
	local size = EffectsHUDConfig.TileSize
	local inset = EffectsHUDConfig.IconInset

	local frame = Instance.new("Frame")
	frame.Name = effectName
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundTransparency = 1

	local bright: Frame? = nil
	local iconId = EffectsHUDConfig.Icons[effectName] or ""
	if iconId ~= "" then
		local dim = Instance.new("ImageLabel")
		dim.Name = "Dim"
		dim.BackgroundTransparency = 1
		dim.Position = UDim2.fromOffset(inset, inset)
		dim.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
		dim.Image = iconId
		dim.ImageColor3 = COLORS.Dim
		dim.ImageTransparency = TRANSPARENCY.Dim
		dim.ScaleType = Enum.ScaleType.Fit
		dim.Parent = frame

		local clip = Instance.new("Frame")
		clip.Name = "Bright"
		clip.BackgroundTransparency = 1
		clip.AnchorPoint = Vector2.new(0, 1)
		clip.Position = UDim2.fromScale(0, 1)
		clip.Size = UDim2.fromScale(1, 1)
		clip.ClipsDescendants = true
		clip.ZIndex = 2
		clip.Parent = frame

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0, 1)
		icon.Position = UDim2.new(0, inset, 1, -inset)
		icon.Size = UDim2.fromOffset(size - inset * 2, size - inset * 2)
		icon.Image = iconId
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 2
		icon.Parent = clip

		bright = clip
	else
		local label = Instance.new("TextLabel")
		label.Name = "Fallback"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.9, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.42)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Font = Enum.Font.GothamMedium
		label.TextColor3 = COLORS.Text
		label.TextScaled = true
		label.TextWrapped = true
		label.Text = effectName
		label.Parent = frame
	end

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.BackgroundTransparency = 1
	countdown.AnchorPoint = Vector2.new(0.5, 1)
	countdown.Position = UDim2.new(0.5, 0, 1, -2)
	countdown.Size = UDim2.fromScale(0.9, 0.3)
	countdown.Font = Enum.Font.GothamBold
	countdown.TextColor3 = COLORS.Text
	countdown.TextScaled = true
	countdown.ZIndex = 3
	countdown.Parent = frame

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = COLORS.TextStroke
	textStroke.Thickness = 2
	textStroke.Parent = countdown

	nextOrder += 1
	frame.LayoutOrder = nextOrder
	frame.Parent = panel

	return { Frame = frame, Bright = bright, Label = countdown, EndsAt = 0, Duration = 1 }
end

local function show(effectName: string, duration: number, endsAt: number?)
	local entry = Entries[effectName]
	if not entry then
		entry = buildTile(effectName)
		Entries[effectName] = entry
	end
	entry.Duration = math.max(duration, 0.05)
	entry.EndsAt = endsAt or (now() + duration)
end

local function dismiss(effectName: string)
	local entry = Entries[effectName]
	if not entry then return end
	Entries[effectName] = nil
	entry.Frame:Destroy()
end

RunService.Heartbeat:Connect(function()
	local time = now()
	for effectName, entry in Entries do
		local remaining = entry.EndsAt - time
		if remaining <= 0 then
			dismiss(effectName)
		else
			if entry.Bright then
				entry.Bright.Size = UDim2.fromScale(1, math.clamp(remaining / entry.Duration, 0, 1))
			end
			entry.Label.Text = string.format("%.1f", remaining)
		end
	end
end)

local lastBoostName: string? = nil

local function refreshBoost()
	local name = player:GetAttribute("SpeedBoostName")
	local endsAt = player:GetAttribute("SpeedBoostEndsAt")

	if lastBoostName and lastBoostName ~= name then
		dismiss(lastBoostName)
	end
	lastBoostName = name

	if type(name) == "string" and type(endsAt) == "number" then
		local config = ToolConfigs[name]
		show(name, (config and config.Duration) or 1, endsAt)
	end
end

player:GetAttributeChangedSignal("SpeedBoostName"):Connect(refreshBoost)
player:GetAttributeChangedSignal("SpeedBoostEndsAt"):Connect(refreshBoost)
refreshBoost()

CollectionService:GetInstanceAddedSignal(Vanished.Tag):Connect(function(instance)
	if instance == player.Character then
		show("SpellBook", ToolConfigs.SpellBook.MaxCastTime)
	end
end)

CollectionService:GetInstanceRemovedSignal(Vanished.Tag):Connect(function(instance)
	if instance == player.Character then
		dismiss("SpellBook")
	end
end)

workspace.ChildAdded:Connect(function(child)
	if child:GetAttribute("CreatorUserId") == player.UserId and child:GetAttribute("ID") ~= nil then
		show("Shovel", EffectsHUDConfig.HoleLifetime)
	end
end)

local lastTotals: { [string]: number } = {}

ReplicatedStorage.Communication.Inventory.Update.OnClientEvent:Connect(function(entries)
	local totals: { [string]: number } = {}
	for _, entry in entries or {} do
		totals[entry.Name] = (totals[entry.Name] or 0) + (entry.Quantity or 0)
	end

	for name, previous in lastTotals do
		if EffectsHUDConfig.FlashItems[name] and (totals[name] or 0) < previous then
			show(name, EffectsHUDConfig.FlashDuration)
		end
	end
	lastTotals = totals
end)

local function watchPathfinder(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "Pathfinder" then return end
	local lastUses = tool:GetAttribute("uses")
	tool:GetAttributeChangedSignal("uses"):Connect(function()
		local uses = tool:GetAttribute("uses")
		if type(uses) == "number" and type(lastUses) == "number" and uses < lastUses then
			show("Pathfinder", EffectsHUDConfig.FlashDuration)
		end
		lastUses = uses
	end)
end

local function watchCharacter(character: Model)
	for _, child in character:GetChildren() do
		watchPathfinder(child)
	end
	character.ChildAdded:Connect(watchPathfinder)
end

if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

build()

return EffectsHUDService
