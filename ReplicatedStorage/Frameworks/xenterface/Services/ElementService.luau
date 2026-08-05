local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ElementService = {}


local ElementToId = {}
local Connections = {}

local WaitingIds = {}

function ElementService:Get(elementId: string)
	for element, currentId in ElementToId do
		if elementId == currentId then
			return element
		end
	end
end

function ElementService:Wait(elementId: string)
	local element = ElementService:Get(elementId)
	if element then return element end
	local thread = coroutine.running()
	local t = WaitingIds[elementId] 
	if not t then
		t = {}
		WaitingIds[elementId] = t
	end
	table.insert(t, thread)
	
	local element = coroutine.yield()
	return element
end

local function set(element)
	local oldId = ElementToId[element]
	if oldId then
		ElementToId[element] = nil
	end
	
	local elementId = element:GetAttribute("ElementId")
	if elementId == nil or elementId == "" then
		return
	end
	ElementToId[element] = elementId
	if WaitingIds[elementId] then
		for _, thread in WaitingIds[elementId] do
			coroutine.resume(thread, element)
		end
		WaitingIds[elementId] = nil
	end
end

local function register(element)
	if not element:IsDescendantOf(PlayerGui) then 
		return	
	end
	local connections = {}
	connections.AttributeChanged = element:GetAttributeChangedSignal("ElementId"):Connect(function()
		set(element)
	end)
	set(element)
	Connections[element] = connections
end

local function unregister(element)
	local elementId = element:GetAttribute("ElementId")
	if ElementToId[element] then
		ElementToId[element] = nil
	end
	if Connections[element] then
		for _, connection in Connections[element] do
			connection:Disconnect()
		end
		Connections[element] = nil
	end
end

CollectionService:GetInstanceAddedSignal("Element"):Connect(function(element)
	register(element)
end)

CollectionService:GetInstanceRemovedSignal("Element"):Connect(function(element)
	unregister(element)
end)

for _, element in CollectionService:GetTagged("Element") do
	register(element)
end

return ElementService