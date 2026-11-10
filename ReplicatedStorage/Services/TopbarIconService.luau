local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TopbarIconService = {}

if not RunService:IsClient() then
	return TopbarIconService
end

local Icon = require(ReplicatedStorage.Classes.Icon)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local TopbarConfig = require(ReplicatedStorage.Configs.TopbarConfig)
local xenterface = require(ReplicatedStorage.Frameworks.xenterface)

local controller = xenterface:Controller(TopbarConfig.PageGroup)
local icons: { [string]: any } = {}
local compact: boolean? = nil
local highlightBlocks: { [string]: true } = {}
local savedHighlightKey: any = nil

local function buildIcon(entry)
	local icon = Icon.new()
		:setName(entry.Name)
		:setImage(entry.Image)
		:setImageScale(TopbarConfig.ImageScale)
		:setLabel(entry.Label)
		:setOrder(entry.Order)
		:align(TopbarConfig.Alignment)
		:autoDeselect(false)

	icon:bindEvent("selected", function()
		if InterfaceService:GetActive() == entry.PageId then return end
		InterfaceService:Open(entry.PageId)
	end)

	icon:bindEvent("deselected", function()
		if InterfaceService:GetActive() ~= entry.PageId then return end
		InterfaceService:Close()
	end)

	icons[entry.PageId] = icon
	return icon
end

local function syncSelection(activeId: string?)
	for pageId, icon in icons do
		if pageId == activeId then
			icon:select()
		else
			icon:deselect()
		end
	end
end

function TopbarIconService:GetIcon(pageId: string)
	return icons[pageId]
end

function TopbarIconService:SetHighlightBlocked(key: string, blocked: boolean)
	local wasBlocked = next(highlightBlocks) ~= nil
	highlightBlocks[key] = if blocked then true else nil
	local isBlocked = next(highlightBlocks) ~= nil
	if isBlocked == wasBlocked then return end

	if isBlocked then
		savedHighlightKey = Icon.highlightKey
		Icon.highlightKey = false
	else
		Icon.highlightKey = savedHighlightKey
	end
end

for _, entry in TopbarConfig.Icons do
	buildIcon(entry)
end

local function refreshLayout()
	local camera = workspace.CurrentCamera
	if not camera then return end

	local nextCompact = camera.ViewportSize.X < TopbarConfig.CompactWidth
	if nextCompact == compact then return end
	compact = nextCompact

	for _, entry in TopbarConfig.Icons do
		icons[entry.PageId]:setLabel(if compact then "" else entry.Label)
	end
end

RunService.RenderStepped:Connect(refreshLayout)
refreshLayout()

controller.Fired:Connect(function(data)
	syncSelection(data.ActiveId)
end)

return TopbarIconService
