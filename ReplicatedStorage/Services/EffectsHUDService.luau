local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EffectsHUDConfig = require(ReplicatedStorage.Configs.EffectsHUDConfig)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

--- Draws the right-side stack of active-effect tiles: one per effect currently running on the
--- local player, each with the item's icon, a drain sheet that covers the spent share of its time,
--- and a countdown in tenths of a second. Instant consumables flash for a moment just to say
--- "used one". Re-triggering an effect that is already shown (a second Energy Drink mid-boost)
--- refreshes the existing tile rather than adding a twin.
---
--- Nothing here owns game state. Every tile is driven by a signal another system already emits:
--- the speed boost attributes, the Vanished tag, hole models appearing with the local player's
--- CreatorUserId, the inventory snapshot shrinking, or the Pathfinder spending a charge.
local EffectsHUDService = {}

if not RunService:IsClient() then
	return EffectsHUDService
end

local COLORS = EffectsHUDConfig.Colors
local TRANSPARENCY = EffectsHUDConfig.Transparency

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--- Building the interface ------------------------------------------------------------------------

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

--- Tiles ------------------------------------------------------------------------------------------

type Entry = {
	Frame: Frame,
	-- Clips the full-colour icon to the remaining share of time; nil for the text fallback.
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

	-- No backing card: the tile is an invisible layout cell and only the icon itself shows.
	local frame = Instance.new("Frame")
	frame.Name = effectName
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundTransparency = 1

	local bright: Frame? = nil
	local iconId = EffectsHUDConfig.Icons[effectName] or ""
	if iconId ~= "" then
		-- Two copies of the icon: a dimmed one underneath showing the spent share, and a
		-- full-colour one clipped from the bottom up to exactly the remaining share -- the drain
		-- reads on the icon's own silhouette instead of on a sheet over a card.
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

		-- Pinned to the tile's bottom so the image never moves while its window shrinks.
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
		-- Stands in until real art exists, so a tile is never blank.
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

	-- Text floats straight on the world now, so it carries its own contrast.
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = COLORS.TextStroke
	textStroke.Thickness = 2
	textStroke.Parent = countdown

	nextOrder += 1
	frame.LayoutOrder = nextOrder
	frame.Parent = panel

	return { Frame = frame, Bright = bright, Label = countdown, EndsAt = 0, Duration = 1 }
end

--- Shows `effectName` for `duration` seconds, or refreshes its clock if it is already up.
--- `endsAt` (server time) pins the exact expiry when the server has already decided it, which is
--- what keeps a second drink mid-boost from drifting off the authoritative timer.
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

--- Speed boosts (Soda, Energy Drink) --------------------------------------------------------------

-- SpeedBoostService stamps the winning boost's name and server-time expiry on the player. Reading
-- those instead of watching consumption means the tile always matches the boost actually applied,
-- including a re-drink resetting the clock.
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

--- SpellBook vanish -------------------------------------------------------------------------------

-- The cast's real length is the reading animation, which only the caster's tool knows; the tag is
-- the truth of when it ends. The tile counts down from the cast's hard cap and leaves early the
-- moment the tag does.
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

--- Shovel holes -----------------------------------------------------------------------------------

-- A dig parents an entry/exit pair into workspace, each stamped with the digger's UserId before it
-- arrives. One dig therefore fires ChildAdded twice; showing is idempotent so the pair collapses
-- into a single refreshed tile.
workspace.ChildAdded:Connect(function(child)
	if child:GetAttribute("CreatorUserId") == player.UserId and child:GetAttribute("ID") ~= nil then
		show("Shovel", EffectsHUDConfig.HoleLifetime)
	end
end)

--- Instant consumables ----------------------------------------------------------------------------

-- The inventory snapshot is the one place every consumption already reports to. A drop in an
-- item's total between snapshots is read as "used one"; timed items are excluded via FlashItems so
-- their real tiles are never shadowed by a flash.
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

--- Pathfinder charges -----------------------------------------------------------------------------

-- One Pathfinder is one device spending charges, so quantity never moves on placement; the tool's
-- "uses" attribute is what ticks down. The unlimited gamepass spends nothing and correctly never
-- flashes. Watching every tool that enters the character keeps this alive across respawns.
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
