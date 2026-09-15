local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)
local InventorySlot = require(ReplicatedStorage.Classes.InventorySlot)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local InventoryUIService = {}

export type Entry = {
	Slot: number,
	Name: string,
	Quantity: number,
	Icon: string?,
}

if not RunService:IsClient() then
	return InventoryUIService
end

local HOTBAR = InventoryConfig.HotbarSlots
local CAPACITY = HOTBAR + InventoryConfig.BackpackSlots

local player = Players.LocalPlayer
local Update = CommunicationService.Get("Inventory", "Update") :: RemoteEvent
local Move = CommunicationService.Get("Inventory", "Move") :: RemoteEvent

local changed = Instance.new("BindableEvent")
InventoryUIService.Changed = changed.Event

local Slots: { InventorySlot.InventorySlot } = {}
local Snapshot: { [number]: Entry } = {}

local screenGui, hotbar
local drag = nil :: {
	Slot: any,
	Origin: Vector2,
	PointerOffset: Vector2,
	Started: boolean,
	Ghost: ImageButton?,
	Target: any?,
}?

local function build()
	screenGui = GuiBuilderService.CreateScreenGui("HotbarGui", 10)

	local slotSize = InventoryConfig.SlotSize
	local padding = InventoryConfig.SlotPadding

	hotbar = Instance.new("Frame")
	hotbar.Name = "Hotbar"
	hotbar.BackgroundTransparency = 1
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 1, -12)
	hotbar.Size = UDim2.fromOffset(HOTBAR * slotSize + (HOTBAR - 1) * padding, slotSize)
	hotbar.Parent = screenGui

	local hotbarLayout = Instance.new("UIListLayout")
	hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
	hotbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hotbarLayout.Padding = UDim.new(0, padding)
	hotbarLayout.Parent = hotbar

	for index = 1, HOTBAR do
		local slot = InventorySlot.new(index, true)
		slot.Frame.Parent = hotbar
		Slots[index] = slot
	end
end

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

function InventoryUIService:Refresh()
	local equipped = equippedToolName()

	for index = 1, HOTBAR do
		local slot = Slots[index]
		local entry = Snapshot[index]

		if entry then
			slot:SetTool(entry.Name, entry.Quantity, entry.Icon)
			slot:SetEquipped(entry.Name == equipped)
		else
			slot:SetEmpty()
		end

		slot.Frame.Visible = true
	end
end

function InventoryUIService:SetHotbarVisible(visible: boolean)
	if not visible and drag then
		if drag.Ghost then drag.Ghost:Destroy() end
		if drag.Target and drag.Target ~= drag.Slot then drag.Target:SetDropTarget(false) end
		drag.Slot.Frame.BackgroundTransparency = InventoryConfig.Transparency.Slot
		drag = nil
	end
	screenGui.Enabled = visible
	if visible then InventoryUIService:Refresh() end
end

function InventoryUIService:GetSnapshot(): { [number]: Entry }
	return table.clone(Snapshot)
end

function InventoryUIService:GetEntry(index: number): Entry?
	return Snapshot[index]
end

function InventoryUIService:GetEquipped(): string?
	return equippedToolName()
end

function InventoryUIService:IsHotbarSlot(index: number): boolean
	return index >= 1 and index <= HOTBAR
end

function InventoryUIService:FindFreeSlot(inHotbar: boolean): number?
	local first = if inHotbar then 1 else HOTBAR + 1
	local last = if inHotbar then HOTBAR else CAPACITY

	for index = first, last do
		if Snapshot[index] == nil then return index end
	end
	return nil
end

function InventoryUIService:Move(from: number, to: number): boolean
	if from == to or Snapshot[from] == nil then return false end
	if from < 1 or from > CAPACITY or to < 1 or to > CAPACITY then return false end

	Snapshot[from], Snapshot[to] = Snapshot[to], Snapshot[from]
	if Snapshot[from] then Snapshot[from].Slot = from end
	if Snapshot[to] then Snapshot[to].Slot = to end

	InventoryUIService:Refresh()
	changed:Fire()
	Move:FireServer(from, to)
	return true
end

function InventoryUIService:Equip(toolName: string)
	local character = player.Character
	local humanoid = CharacterService.GetAliveHumanoid(player)
	if not humanoid then return end

	local tool = findTool(toolName)
	if not tool or not tool.Enabled then return end

	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end

	InventoryUIService:Refresh()
end

local function toggleEquip(slot)
	if slot:IsEmpty() then return end
	InventoryUIService:Equip(slot.ToolName)
end

local function slotAt(point: Vector2)
	for _, slot in Slots do
		local frame = slot.Frame
		local topLeft = frame.AbsolutePosition
		local size = frame.AbsoluteSize
		if
			point.X >= topLeft.X and point.X <= topLeft.X + size.X
			and point.Y >= topLeft.Y and point.Y <= topLeft.Y + size.Y
		then
			return slot
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
	ghost.Position = UDim2.fromOffset(
		position.X - drag.PointerOffset.X,
		position.Y - drag.PointerOffset.Y
	)
	ghost.BackgroundTransparency = InventoryConfig.Transparency.Dragging
	ghost.ZIndex = 50
	ghost.Parent = screenGui
	drag.Ghost = ghost

	source.Frame.BackgroundTransparency = 0.7
end

local function updateDrag(position: Vector3)
	if not drag.Ghost then return end
	drag.Ghost.Position = UDim2.fromOffset(
		position.X - drag.PointerOffset.X,
		position.Y - drag.PointerOffset.Y
	)

	local hovered = slotAt(Vector2.new(position.X, position.Y))
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

	local target = started and slotAt(Vector2.new(position.X, position.Y)) or nil
	drag = nil

	if not started then
		toggleEquip(source)
		return
	end

	if not target or target == source then
		InventoryUIService:Refresh()
		return
	end

	InventoryUIService:Move(source.Index, target.Index)
end

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

			local pointer = Vector2.new(input.Position.X, input.Position.Y)
			drag = {
				Slot = slot,
				Origin = pointer,
				PointerOffset = pointer - slot.Frame.AbsolutePosition,
				Started = false,
			}
		end)
	end

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

		for index, keyCode in InventoryConfig.HotbarKeys do
			if input.KeyCode == keyCode and Slots[index] then
				toggleEquip(Slots[index])
				return
			end
		end
	end)

	Update.OnClientEvent:Connect(function(entries)
		Snapshot = {}
		for _, entry in entries or {} do
			Snapshot[entry.Slot] = entry
		end
		InventoryUIService:Refresh()
		changed:Fire()
	end)

	local characterConnections: { RBXScriptConnection } = {}

	local function watchCharacter(character: Model)
		for _, connection in characterConnections do
			connection:Disconnect()
		end
		table.clear(characterConnections)

		table.insert(characterConnections, character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then InventoryUIService:Refresh() end
		end))
		table.insert(characterConnections, character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then InventoryUIService:Refresh() end
		end))
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

Update:FireServer()

return InventoryUIService
