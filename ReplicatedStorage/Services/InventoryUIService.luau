local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)
local InventorySlot = require(ReplicatedStorage.Classes.InventorySlot)

--- Draws the inventory and turns input into intent. Everything visible is built here in code, so
--- there is no StarterGui asset to keep in sync with the layout.
---
--- The one genuinely delicate part is telling a tap apart from a drag. A press does not commit to
--- being either until it has travelled `DragThreshold` pixels from where it went DOWN. Under that,
--- releasing equips; over it, the press becomes a drag and releasing drops. Measuring from the
--- press origin rather than from the slot's own position is what keeps a stationary tap on a
--- shifting layout from registering as an accidental drag.
local InventoryUIService = {}

if not RunService:IsClient() then
	return InventoryUIService
end

local COLORS = InventoryConfig.Colors
local CAPACITY = InventoryConfig.HotbarSlots + InventoryConfig.BackpackSlots

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Communication = ReplicatedStorage.Communication.Inventory

local Slots: { InventorySlot.InventorySlot } = {}
local Snapshot: { [number]: { Name: string, Quantity: number, Icon: string? } } = {}

local screenGui, hotbar, panel, panelGrid
local drag = nil :: { Slot: any, Origin: Vector2, Started: boolean, Ghost: ImageButton?, Target: any? }?

--- Building the interface ------------------------------------------------------------------------

local function build()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	local slotSize = InventoryConfig.SlotSize
	local padding = InventoryConfig.SlotPadding
	local hotbarCount = InventoryConfig.HotbarSlots

	hotbar = Instance.new("Frame")
	hotbar.Name = "Hotbar"
	hotbar.BackgroundTransparency = 1
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 1, -12)
	hotbar.Size = UDim2.fromOffset(hotbarCount * slotSize + (hotbarCount - 1) * padding, slotSize)
	hotbar.Parent = screenGui

	local hotbarLayout = Instance.new("UIListLayout")
	hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
	hotbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hotbarLayout.Padding = UDim.new(0, padding)
	hotbarLayout.Parent = hotbar

	-- The overflow panel: everything past the hotbar, hidden until the toggle key.
	panel = Instance.new("Frame")
	panel.Name = "Backpack"
	panel.Visible = false
	panel.BackgroundColor3 = COLORS.Panel
	panel.BackgroundTransparency = InventoryConfig.Transparency.Panel
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -(slotSize + 24))
	panel.Size = UDim2.fromOffset(hotbarCount * slotSize + (hotbarCount + 1) * padding, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, InventoryConfig.CornerRadius)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLORS.Stroke
	panelStroke.Parent = panel

	local panelPadding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		panelPadding[side] = UDim.new(0, padding)
	end
	panelPadding.Parent = panel

	panelGrid = Instance.new("UIGridLayout")
	panelGrid.CellSize = UDim2.fromOffset(slotSize, slotSize)
	panelGrid.CellPadding = UDim2.fromOffset(padding, padding)
	panelGrid.SortOrder = Enum.SortOrder.LayoutOrder
	panelGrid.Parent = panel

	for index = 1, CAPACITY do
		local isHotbar = index <= hotbarCount
		local slot = InventorySlot.new(index, isHotbar)
		slot.Frame.Parent = isHotbar and hotbar or panel
		Slots[index] = slot
	end
end

--- Reading and applying state -------------------------------------------------------------------

-- The Tool instance behind a name, stowed or equipped, or nil if it is gone.
local function findTool(toolName: string): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(toolName)
	if tool and tool:IsA("Tool") then return tool end

	local character = player.Character
	tool = character and character:FindFirstChild(toolName)
	if tool and tool:IsA("Tool") then return tool end
	return nil
end

local function equippedToolName(): string?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool and tool.Name or nil
end

--- Repaints every slot from the last snapshot the server sent.
function InventoryUIService:Refresh()
	local equipped = equippedToolName()

	for index = 1, CAPACITY do
		local slot = Slots[index]
		local entry = Snapshot[index]

		if entry then
			slot:SetTool(entry.Name, entry.Quantity, entry.Icon)
			slot:SetEquipped(entry.Name == equipped)
		else
			slot:SetEmpty()
		end
	end
end

--- Equipping ------------------------------------------------------------------------------------

local function toggleEquip(slot)
	if slot:IsEmpty() then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local tool = findTool(slot.ToolName)
	if not tool or not tool.Enabled then return end

	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end

	InventoryUIService:Refresh()
end

--- Dragging -------------------------------------------------------------------------------------

-- Input positions exclude the top inset; AbsolutePosition includes it. Converting once here is
-- what removes the hardcoded pixel fudge FFM applied at two separate call sites.
local function toScreenSpace(position: Vector3): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(position.X + inset.X, position.Y + inset.Y)
end

-- The slot under a screen-space point, ignoring slots inside the hidden panel.
local function slotAt(point: Vector2)
	for _, slot in Slots do
		local frame = slot.Frame
		if frame.Visible and frame.Parent.Visible then
			local topLeft = frame.AbsolutePosition
			local size = frame.AbsoluteSize
			if
				point.X >= topLeft.X and point.X <= topLeft.X + size.X
				and point.Y >= topLeft.Y and point.Y <= topLeft.Y + size.Y
			then
				return slot
			end
		end
	end
	return nil
end

local function threshold(input: InputObject): number
	return input.UserInputType == Enum.UserInputType.Touch
		and InventoryConfig.TouchDragThreshold
		or InventoryConfig.DragThreshold
end

local function beginDrag(position: Vector3)
	local source = drag.Slot
	drag.Started = true

	local ghost = source.Frame:Clone()
	ghost.Name = "DragGhost"
	ghost.Size = UDim2.fromOffset(source.Frame.AbsoluteSize.X, source.Frame.AbsoluteSize.Y)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Position = UDim2.fromOffset(position.X, position.Y)
	ghost.BackgroundTransparency = InventoryConfig.Transparency.Dragging
	ghost.ZIndex = 50
	ghost.Parent = screenGui
	drag.Ghost = ghost

	-- The slot being carried reads as empty underneath the ghost.
	source.Frame.BackgroundTransparency = 0.7
end

local function updateDrag(position: Vector3)
	if not drag.Ghost then return end
	drag.Ghost.Position = UDim2.fromOffset(position.X, position.Y)

	local hovered = slotAt(toScreenSpace(position))
	if hovered == drag.Target then return end

	if drag.Target and drag.Target ~= drag.Slot then
		drag.Target:SetDropTarget(false)
	end
	drag.Target = hovered
	if hovered and hovered ~= drag.Slot then
		hovered:SetDropTarget(true)
	end
end

local function endDrag(position: Vector3)
	local source = drag.Slot
	local started = drag.Started

	if drag.Ghost then
		drag.Ghost:Destroy()
	end
	if drag.Target and drag.Target ~= source then
		drag.Target:SetDropTarget(false)
	end
	source.Frame.BackgroundTransparency = InventoryConfig.Transparency.Slot

	local target = started and slotAt(toScreenSpace(position)) or nil
	drag = nil

	if not started then
		-- Never travelled far enough to be a drag, so it was a tap.
		toggleEquip(source)
		return
	end

	if not target or target == source then
		InventoryUIService:Refresh()
		return
	end

	-- Swap locally so the drag lands instantly, then let the server confirm. Its echo is
	-- authoritative: if it disagrees, the next Refresh silently corrects this.
	Snapshot[source.Index], Snapshot[target.Index] = Snapshot[target.Index], Snapshot[source.Index]
	InventoryUIService:Refresh()
	Communication.Move:FireServer(source.Index, target.Index)
end

--- Wiring ---------------------------------------------------------------------------------------

local function setUpConnections()
	for _, slot in Slots do
		slot.Connections.InputBegan = slot.Frame.InputBegan:Connect(function(input: InputObject)
			if drag then return end
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			if slot:IsEmpty() then return end

			drag = {
				Slot = slot,
				Origin = Vector2.new(input.Position.X, input.Position.Y),
				Started = false,
			}
		end)
	end

	-- Movement and release are watched globally rather than per-slot: once a drag is under way the
	-- pointer is usually no longer over the slot that started it.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not drag then return end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		if not drag.Started then
			local travelled = (Vector2.new(input.Position.X, input.Position.Y) - drag.Origin).Magnitude
			if travelled < threshold(input) then return end
			beginDrag(input.Position)
		end

		updateDrag(input.Position)
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if not drag then return end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		endDrag(input.Position)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		if input.KeyCode == InventoryConfig.ToggleKey then
			panel.Visible = not panel.Visible
			return
		end

		for index, keyCode in InventoryConfig.HotbarKeys do
			if input.KeyCode == keyCode and Slots[index] then
				toggleEquip(Slots[index])
				return
			end
		end
	end)

	-- Arrives as a dense list of entries that each name their slot; re-indexed here so the rest of
	-- this file can treat the snapshot as slot -> entry.
	Communication.Update.OnClientEvent:Connect(function(entries)
		Snapshot = {}
		for _, entry in entries or {} do
			Snapshot[entry.Slot] = entry
		end
		InventoryUIService:Refresh()
	end)

	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then InventoryUIService:Refresh() end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then InventoryUIService:Refresh() end
		end)
	end

	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
build()
setUpConnections()
InventoryUIService:Refresh()

-- Ask for the current state now that the handler above is live. Without this the inventory stays
-- blank until the next thing that happens to change it.
Communication.Update:FireServer()

return InventoryUIService
