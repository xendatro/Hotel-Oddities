local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerLocatorConfig = require(ReplicatedStorage.Configs.PlayerLocatorConfig)

--- @class LocatorMarker
--- One highlighted player: an outline that reads through walls and a tappable area over them.
---
--- The tap target is a `BillboardGui` rather than a `ClickDetector` because the whole point is the
--- player behind the wall. A click detector needs line of sight and a short distance; an always-on-top
--- billboard is clickable exactly where the outline is drawn, at any range, on touch as well as mouse.
---
--- Follows its player across deaths and respawns. Between them there is nothing to adorn to, so the
--- marker hides itself rather than lingering over the corpse -- teleporting to a dead player is
--- refused by the server anyway, and a marker that offers it is a marker that lies.
local LocatorMarker = {}
LocatorMarker.__index = LocatorMarker

local HIGHLIGHT = PlayerLocatorConfig.Highlight
local MARKER = PlayerLocatorConfig.Marker

--- @param player Player -- who to mark
--- @param parent Instance -- where the marker's instances live
--- @param onActivated (Player) -> () -- called when the marker is tapped
function LocatorMarker.new(player: Player, parent: Instance, onActivated: (Player) -> ())
	local self = setmetatable({}, LocatorMarker)

	self.Player = player
	self.Connections = {}

	local highlight = Instance.new("Highlight")
	highlight.Name = `{player.Name}Outline`
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = HIGHLIGHT.FillColor
	highlight.FillTransparency = HIGHLIGHT.FillTransparency
	highlight.OutlineColor = HIGHLIGHT.OutlineColor
	highlight.OutlineTransparency = HIGHLIGHT.OutlineTransparency
	highlight.Enabled = false
	highlight.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = `{player.Name}Tap`
	billboard.Active = true
	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false
	billboard.Size = UDim2.fromScale(MARKER.Size.X, MARKER.Size.Y)
	billboard.StudsOffsetWorldSpace = MARKER.Offset
	billboard.MaxDistance = MARKER.MaxDistance
	billboard.Enabled = false
	billboard.Parent = parent

	local button = Instance.new("ImageButton")
	button.Name = "Tap"
	button.Active = true
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.ImageTransparency = 1
	button.AutoButtonColor = false
	button.Parent = billboard

	if MARKER.ShowName then
		local label = Instance.new("TextLabel")
		label.Name = "DisplayName"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.5, 0)
		label.Size = UDim2.fromScale(1, 0.2)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = MARKER.NameSize
		label.TextColor3 = MARKER.NameColor
		label.TextStrokeTransparency = 0.4
		label.TextScaled = false
		label.Text = player.DisplayName
		label.Parent = billboard
	end

	self.Highlight = highlight
	self.Billboard = billboard

	table.insert(self.Connections, button.Activated:Connect(function()
		onActivated(player)
	end))

	table.insert(self.Connections, player.CharacterAdded:Connect(function(character)
		self:_Bind(character)
	end))
	table.insert(self.Connections, player.CharacterRemoving:Connect(function()
		self:_Bind(nil)
	end))

	self:_Bind(player.Character)

	return self
end

-- Points both instances at `character`, or switches the marker off when there is nothing to point at.
function LocatorMarker:_Bind(character: Model?)
	if self.Died then
		self.Died:Disconnect()
		self.Died = nil
	end

	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		self:_SetShown(false)
		return
	end

	self.Highlight.Adornee = character
	self.Billboard.Adornee = root
	self:_SetShown(true)

	self.Died = humanoid.Died:Connect(function()
		self:_SetShown(false)
	end)
end

function LocatorMarker:_SetShown(shown: boolean)
	self.Highlight.Enabled = shown
	self.Billboard.Enabled = shown
end

function LocatorMarker:Destroy()
	if self.Died then
		self.Died:Disconnect()
		self.Died = nil
	end
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	self.Highlight:Destroy()
	self.Billboard:Destroy()
end

return LocatorMarker
