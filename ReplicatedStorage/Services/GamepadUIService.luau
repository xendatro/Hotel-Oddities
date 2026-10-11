local CollectionService = game:GetService("CollectionService")
local GamepadService = game:GetService("GamepadService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GamepadUIConfig = require(ReplicatedStorage.Configs.GamepadUIConfig)

local GamepadUIService = {}

if not RunService:IsClient() then
	return GamepadUIService
end

export type FocusOptions = {
	OnBack: (() -> ())?,
	Replace: boolean?,
	Select: boolean?,
}

type Layer = {
	Root: GuiObject,
	OnBack: (() -> ())?,
	Select: boolean,
}

local layers: { Layer } = {}
local cursorKeys: { [string]: true } = {}
local lastBack = 0

local changed = Instance.new("BindableEvent")
GamepadUIService.Changed = changed.Event

local function isGamepad(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

local function shownWithin(object: GuiObject, root: GuiObject): boolean
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") and not current.Visible then return false end
		if current:IsA("LayerCollector") then return current.Enabled end
		current = current.Parent
	end
	return false
end

local function prepare(root: GuiObject)
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant:GetAttribute(GamepadUIConfig.SkipAttribute) ~= true then
			descendant.Selectable = true
		end
	end
end

local function before(a: GuiObject, b: GuiObject): boolean
	local left, right = a.AbsolutePosition, b.AbsolutePosition
	if math.abs(left.Y - right.Y) > 4 then
		return left.Y < right.Y
	end
	return left.X < right.X
end

local function pickDefault(root: GuiObject): GuiObject?
	local best: GuiObject? = nil
	local close: GuiObject? = nil

	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("GuiButton") or not descendant.Selectable then continue end
		if not shownWithin(descendant, root) then continue end

		if descendant:GetAttribute(GamepadUIConfig.DefaultAttribute) == true then
			return descendant
		end
		if CollectionService:HasTag(descendant, GamepadUIConfig.CloseTag) then
			close = close or descendant
			continue
		end
		if not best or before(descendant, best) then
			best = descendant
		end
	end

	return best or close
end

local function refreshCursor()
	local wanted = next(cursorKeys) ~= nil and isGamepad()
	if wanted == GamepadService.GamepadCursorEnabled then return end
	pcall(function()
		if wanted then
			GamepadService:EnableGamepadCursor(nil)
		else
			GamepadService:DisableGamepadCursor()
		end
	end)
end

local function topLayer(): Layer?
	return layers[#layers]
end

local function selectTop()
	local layer = topLayer()
	if not layer or not layer.Select or not isGamepad() then return end
	if not layer.Root.Parent then return end

	local current = GuiService.SelectedObject
	if current and current:IsDescendantOf(layer.Root) and shownWithin(current, layer.Root) then return end

	prepare(layer.Root)
	GuiService.SelectedObject = pickDefault(layer.Root)
end

local function clearSelectionIn(root: GuiObject)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

local function removeLayer(root: GuiObject)
	for index = #layers, 1, -1 do
		if layers[index].Root == root then
			table.remove(layers, index)
		end
	end
end

function GamepadUIService:IsGamepad(): boolean
	return isGamepad()
end

function GamepadUIService:KeyText(keyCode: Enum.KeyCode): string
	return GamepadUIConfig.KeyText[keyCode] or keyCode.Name
end

function GamepadUIService:Focus(root: GuiObject, options: FocusOptions?)
	local settings = options or {}
	if settings.Replace then
		for _, layer in layers do
			if layer.Root ~= root then
				clearSelectionIn(layer.Root)
			end
		end
		table.clear(layers)
	else
		removeLayer(root)
	end

	table.insert(layers, {
		Root = root,
		OnBack = settings.OnBack,
		Select = settings.Select ~= false,
	})
	task.delay(GamepadUIConfig.SelectDelay, selectTop)
end

function GamepadUIService:Release(root: GuiObject)
	removeLayer(root)
	clearSelectionIn(root)
	task.delay(GamepadUIConfig.SelectDelay, selectTop)
end

function GamepadUIService:SetCursor(key: string, enabled: boolean)
	if (cursorKeys[key] == true) == enabled then return end
	cursorKeys[key] = if enabled then true else nil
	refreshCursor()
end

function GamepadUIService:IsFocused(): boolean
	return #layers > 0
end

function GamepadUIService:IsCapturing(): boolean
	return #layers > 0
		or GuiService.SelectedObject ~= nil
		or os.clock() - lastBack < GamepadUIConfig.BackWindow
end

UserInputService.InputBegan:Connect(function(input: InputObject)
	if not table.find(GamepadUIConfig.BackKeys, input.KeyCode) then return end

	local layer = topLayer()
	if not layer then return end

	local selected = GuiService.SelectedObject
	if selected and not selected:IsDescendantOf(layer.Root) then return end

	lastBack = os.clock()
	if layer.OnBack then
		task.spawn(layer.OnBack)
	else
		GamepadUIService:Release(layer.Root)
	end
end)

GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
	if GuiService.SelectedObject ~= nil or #layers == 0 then return end

	task.delay(GamepadUIConfig.SelectDelay, function()
		if GuiService.SelectedObject ~= nil then return end
		if os.clock() - lastBack < GamepadUIConfig.BackWindow then return end
		selectTop()
	end)
end)

UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
	if isGamepad() then
		selectTop()
	else
		for _, layer in layers do
			clearSelectionIn(layer.Root)
		end
	end
	refreshCursor()
	changed:Fire(isGamepad())
end)

GamepadService:GetPropertyChangedSignal("GamepadCursorEnabled"):Connect(function()
	if GamepadService.GamepadCursorEnabled or next(cursorKeys) == nil then return end
	task.delay(GamepadUIConfig.CursorRestoreDelay, refreshCursor)
end)

return GamepadUIService
