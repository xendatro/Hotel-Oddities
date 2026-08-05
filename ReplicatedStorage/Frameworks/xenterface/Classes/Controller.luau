local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")

local Services = script.Parent.Parent.Services

local CollectionService = game:GetService("CollectionService")
local TagService = require(Services.TagService)

local Signal = require(script.Parent.Signal)
local Sequence = require(script.Parent.Sequence)

local Controller = {}
Controller.__index = Controller

function Controller.new(pageGroup: string)	
	local self = setmetatable({}, Controller)
	
	self.PageGroup = pageGroup
	self.Fired = Signal.new()
	self.Active = nil
	
	self.Sequences = {}

	return self
end

local function getObjectData(tag: string, pageGroup: string)
	local objects = CollectionService:GetTagged(tag)
	local objectData = {}
	for _, object in objects do
		if not object:IsDescendantOf(PlayerGui) then continue end
		local currentPageGroup = object:GetAttribute("PageGroup")
		if currentPageGroup ~= pageGroup then continue end
		local guiObject: GuiObject = nil
		if object:IsA("GuiObject") then
			guiObject = object
		elseif object.Parent:IsA("GuiObject") then
			guiObject = object.Parent
		else
			warn(`{object:GetFullName()} does not follow proper hierarchy, it has been skipped`)
			continue
		end
		objectData[guiObject] = object:GetAttribute("PageId")
	end
	return objectData
end

local function playAnimations(activeTabs, inactiveTabs, activePages, inactivePages)
	for _, tab in activeTabs do
		local tabObject = TagService:GetApplied("Tab", tab)
		if tabObject then
			tabObject:Activate()
		end
	end
	
	for _, tab in inactiveTabs do
		local tabObject = TagService:GetApplied("Tab", tab)
		if tabObject then
			tabObject:Deactivate()
		end
	end
	
	for _, page in activePages do
		local pageObject = TagService:GetApplied("Page", page)
		if pageObject then
			pageObject:Activate()
		end
	end
	
	for _, page in inactivePages do
		local pageObject = TagService:GetApplied("Page", page)
		if pageObject then
			pageObject:Deactivate()
		end
	end
end

function Controller:Fire(pageId: string, tab: GuiButton?)	
	if pageId == self.Active then return end
	local tabData = getObjectData("Tab", self.PageGroup)
	local pageData = getObjectData("Page", self.PageGroup)
	
	local selectedTab = tab
	
	local activeTab = nil
	local activeTabs = {}
	local inactiveTab = nil
	local inactiveTabs = {}
	local tabs = {}
	for tab, id in tabData do
		if id == pageId then
			table.insert(activeTabs, tab)
			activeTab = tab
		elseif id == self.Active then -- This is the OLD active, it'll be changed to pageId, that's why we insert into inactive
			table.insert(inactiveTabs, tab)
			inactiveTab = tab
		end
		table.insert(tabs, tab)
	end
	
	local activePage = nil
	local activePages = {}
	local inactivePage = nil
	local inactivePages = {}
	local pages = {}
	for page, id in pageData do
		if id == pageId then
			table.insert(activePages, page)
			activePage = page
		elseif id == self.Active then
			table.insert(inactivePages, page)
			inactivePage = page
		end
		table.insert(pages, page)
	end
	
	local inactive = self.Active
	self.Active = pageId
	
	playAnimations(
		activeTabs,
		inactiveTabs,
		activePages,
		inactivePages
	)
	
	self.Fired:Fire({
		ActiveId = self.Active,
		InactiveId = inactive,
		ActiveTab = activeTab,
		InactiveTab = inactiveTab,
		ActiveTabs = activeTabs,
		InactiveTabs = inactiveTabs,
		ActivePage = activePage,
		InactivePage = inactivePage,
		ActivePages = activePages,
		InactivePages = inactivePages,
		SelectedTab = selectedTab
	})
end

--[[
Active: string,
Inactive: string,
ActiveTab: GuiButton,
ActivePage: GuiObject,
ActiveTabs: {GuiButtons},
InactiveTab: GuiButton
InactiveTabs: {GuiButton},
InactivePage: {GuiObject},
Tabs: {GuiButton},
Pages: {GuiObjects}
]]

	
return Controller