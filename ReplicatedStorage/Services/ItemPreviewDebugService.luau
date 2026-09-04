local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.ItemPreviewDebugConfig)
local ItemPreviewConfig = require(ReplicatedStorage.Configs.ItemPreviewConfig)
local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local ItemPreviewService = require(ReplicatedStorage.Services.ItemPreviewService)
local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local ItemPreviewDebugService = {}

if not (FLAGS.ItemPreviewDebug and RunService:IsClient()) then
	return ItemPreviewDebugService
end

local KEYS = { "Yaw", "Pitch", "Zoom", "Padding", "OffsetX", "OffsetY" }
local DEFAULTS = ItemPreviewConfig.Default :: any

local panel = DebugPanel.new("item preview", Config.ToggleKey)
local resetters: { () -> () } = {}
local targetButton: TextButton? = nil
local output = panel:AddTextBox("")

local currentItem: string? = nil
local editingDefault = false
local values: { [string]: number } = {}
local fieldOfView = ItemPreviewConfig.FieldOfView

local function items(): { string }
	local names = {}
	for _, entry in ItemShopConfig.Entries do
		table.insert(names, entry.Id)
	end
	table.sort(names)
	return names
end

local function target(): { [string]: number }?
	if editingDefault then return DEFAULTS end
	if not currentItem then return nil end
	return ItemPreviewService:GetOverride(currentItem)
end

local function readState()
	local resolved = if editingDefault or not currentItem
		then DEFAULTS
		else ItemPreviewService:GetFraming(currentItem) :: any
	for _, key in KEYS do
		values[key] = resolved[key]
	end
end

local function formatNumber(value: number): string
	if value == math.floor(value) then return string.format("%d", value) end
	return string.format("%.2f", value)
end

local function keyText(name: string): string
	if string.match(name, "^[%a_][%w_]*$") then return name end
	return string.format("[%q]", name)
end

local function updateOutput()
	if editingDefault then
		local lines = { "\tFieldOfView = " .. formatNumber(fieldOfView) .. "," }
		table.insert(lines, "")
		table.insert(lines, "\tDefault = {")
		for _, key in KEYS do
			table.insert(lines, `\t\t{key} = {formatNumber(DEFAULTS[key])},`)
		end
		table.insert(lines, "\t},")
		output.Text = table.concat(lines, "\n")
		return
	end

	if not currentItem then
		output.Text = "Open the item shop and click a card, or use the item buttons."
		return
	end

	local entry = ItemPreviewConfig.Items[currentItem]
	local parts = {}
	for _, key in KEYS do
		local value = entry and entry[key]
		if value ~= nil and value ~= DEFAULTS[key] then
			table.insert(parts, `{key} = {formatNumber(value)}`)
		end
	end

	if #parts == 0 then
		output.Text = `{currentItem} matches the defaults - no Items entry needed.`
		return
	end
	output.Text = `\t\t{keyText(currentItem)} = \{ {table.concat(parts, ", ")} },`
end

local function apply()
	local into = target()
	if not into then return end
	for _, key in KEYS do
		into[key] = values[key]
	end
	ItemPreviewService:Refresh(if editingDefault then nil else currentItem)
	updateOutput()
end

local function refreshPanel()
	panel:SetTitle(if editingDefault
		then "item preview: defaults"
		else `item preview: {currentItem or "none"}`)
	if targetButton then
		targetButton.Text = if editingDefault
			then "editing: defaults (click for item)"
			else "editing: this item (click for defaults)"
	end
	readState()
	for _, reset in resetters do reset() end
	updateOutput()
end

local function setItem(itemName: string?)
	if itemName == currentItem then return end
	currentItem = itemName
	refreshPanel()
end

local function step(direction: number)
	local names = items()
	if #names == 0 then return end
	local index = table.find(names, currentItem) or 0
	setItem(names[(index - 1 + direction) % #names + 1])
	ItemPreviewService:SetFocus(currentItem)
end

targetButton = panel:AddButton("", function()
	editingDefault = not editingDefault
	refreshPanel()
end)

panel:AddButton("previous item", function()
	step(-1)
end)

panel:AddButton("next item", function()
	step(1)
end)

local function addSlider(key: string, label: string, minimum: number, maximum: number, increment: number)
	local display = panel:AddSlider(label, minimum, maximum, values[key] or 0, increment, function(value)
		values[key] = value
		apply()
	end)
	table.insert(resetters, function()
		display(values[key] or 0)
	end)
end

addSlider("Yaw", "Yaw", -180, 180, Config.AngleStep)
addSlider("Pitch", "Pitch", -89, 89, Config.AngleStep)
addSlider("Zoom", "Zoom", 0.3, 3, Config.Step)
addSlider("Padding", "Padding", 1, 3, Config.Step)
addSlider("OffsetX", "Offset X", -1, 1, Config.Step)
addSlider("OffsetY", "Offset Y", -1, 1, Config.Step)

local fovDisplay = panel:AddSlider("Field of view (all items)", 10, 90, fieldOfView, 1, function(value)
	fieldOfView = value
	ItemPreviewConfig.FieldOfView = value
	ItemPreviewService:Refresh()
	updateOutput()
end)

panel:AddButton("reset this item", function()
	if editingDefault or not currentItem then return end
	ItemPreviewConfig.Items[currentItem] = nil
	readState()
	for _, reset in resetters do reset() end
	ItemPreviewService:Refresh(currentItem)
	updateOutput()
end)

panel:AddLabel(
	"Every viewport showing this item updates live - inventory slots, shop cards and kit previews."
		.. " Clicking a card in the item shop selects it here. Changes are local to this session;"
		.. " paste the generated line into the Items table of ItemPreviewConfig, or the whole block"
		.. " when editing the defaults."
)

RunService.RenderStepped:Connect(function()
	if editingDefault then return end
	local focus = ItemPreviewService:GetFocus()
	if focus then setItem(focus) end
end)

fovDisplay(fieldOfView)
currentItem = items()[1]
refreshPanel()

return ItemPreviewDebugService
