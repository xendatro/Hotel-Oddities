local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local Tools = ReplicatedStorage.Tools
local UpdateRemote = CommunicationService.Get("Inventory", "Update")
local MoveRemote = CommunicationService.Get("Inventory", "Move")
local DeleteRemote = CommunicationService.Get("Backpack", "Delete")

local CAPACITY = InventoryConfig.HotbarSlots + InventoryConfig.BackpackSlots
local SAVED_ATTRIBUTES = { "uses" }

local InventoryService = {}

local Order: { [Player]: { [number]: string } } = {}
local Ready: { [Player]: boolean } = {}
local AttributeConnections: { [Tool]: { RBXScriptConnection } } = {}

local function getOrder(player: Player): { [number]: string }
	if not Order[player] then
		Order[player] = {}
	end
	return Order[player]
end

local function save(player: Player)
	if not Ready[player] then return end

	local profile = DataSaveService:Get(player)
	if not profile then return end

	local tools = InventoryService:GetAll(player)
	local entries = {}
	for slot = 1, CAPACITY do
		local name = getOrder(player)[slot]
		local tool = name and tools[name]
		if not tool then continue end

		local attributes = {}
		for _, attribute in SAVED_ATTRIBUTES do
			local value = tool:GetAttribute(attribute)
			if value ~= nil then
				attributes[attribute] = value
			end
		end

		table.insert(entries, {
			Name = name,
			Quantity = tool:GetAttribute("quantity") or 1,
			Slot = slot,
			Attributes = attributes,
		})
	end
	profile.Data.Inventory = entries
end

local function untrackAttributes(tool: Tool)
	local connections = AttributeConnections[tool]
	if not connections then return end
	AttributeConnections[tool] = nil
	for _, connection in connections do
		connection:Disconnect()
	end
end

local function trackAttributes(player: Player, tool: Tool)
	if AttributeConnections[tool] then return end

	local connections = {}
	AttributeConnections[tool] = connections
	for _, attribute in SAVED_ATTRIBUTES do
		table.insert(connections, tool:GetAttributeChangedSignal(attribute):Connect(function()
			save(player)
		end))
	end

	table.insert(connections, tool.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		untrackAttributes(tool)
	end))
end

function InventoryService:Get(player: Player, toolName: string): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(toolName)
	if tool and tool:IsA("Tool") then return tool end

	local character = player.Character
	if character then
		tool = character:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") then return tool end
	end
	return nil
end

function InventoryService:GetAll(player: Player): { [string]: Tool }
	local found = {}

	local function collect(container: Instance?)
		if not container then return end
		for _, item in container:GetChildren() do
			if item:IsA("Tool") then
				found[item.Name] = item
			end
		end
	end

	collect(player:FindFirstChildOfClass("Backpack"))
	collect(player.Character)
	return found
end

function InventoryService:GetQuantity(player: Player): number
	local total = 0
	for _, tool in InventoryService:GetAll(player) do
		total += tool:GetAttribute("quantity") or 0
	end
	return total
end

function InventoryService:GetSlot(player: Player, toolName: string): number?
	for index, name in getOrder(player) do
		if name == toolName then return index end
	end
	return nil
end

function InventoryService:GetOrder(player: Player): { [number]: string }
	return table.clone(getOrder(player))
end

function InventoryService:Wait(player: Player, timeout: number?): boolean
	local deadline = timeout and os.clock() + timeout
	while not Ready[player] do
		if player.Parent ~= Players or (deadline and os.clock() >= deadline) then return false end
		task.wait()
	end
	return true
end

local function findFreeSlot(player: Player): number?
	local order = getOrder(player)
	for index = 1, CAPACITY do
		if order[index] == nil then return index end
	end
	return nil
end

function InventoryService:Sync(player: Player)
	local tools = InventoryService:GetAll(player)
	local payload = {}

	for index, toolName in getOrder(player) do
		local tool = tools[toolName]
		if tool then
			table.insert(payload, {
				Slot = index,
				Name = toolName,
				Quantity = tool:GetAttribute("quantity") or 1,
				Icon = tool.TextureId ~= "" and tool.TextureId or nil,
			})
		end
	end

	UpdateRemote:FireClient(player, payload)
end

function InventoryService:Add(player: Player, toolName: string, n: number): boolean
	if n <= 0 then return false end
	local tool = InventoryService:Get(player, toolName)

	if not tool then
		local template = Tools:FindFirstChild(toolName)
		if not template then
			warn(`InventoryService: no tool template "{toolName}" in ReplicatedStorage.Tools`)
			return false
		end

		local slot = findFreeSlot(player)
		if not slot then
			warn(`InventoryService: {player.Name}'s inventory is full, dropped "{toolName}"`)
			return false
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then return false end

		tool = template:Clone()
		tool:SetAttribute("quantity", 0)
		getOrder(player)[slot] = toolName
		trackAttributes(player, tool)
		tool.Parent = backpack
	end

	tool:SetAttribute("quantity", (tool:GetAttribute("quantity") or 0) + n)
	InventoryService:Sync(player)
	save(player)
	return true
end

function InventoryService:EnsureSingle(player: Player, toolName: string): boolean
	if not InventoryService:Wait(player, 10) then return false end

	local tools = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if not container then continue end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == toolName then
				table.insert(tools, child)
			end
		end
	end

	local tool = tools[1]
	if not tool then
		return InventoryService:Add(player, toolName, 1)
	end

	for index = 2, #tools do
		tools[index]:Destroy()
	end
	tool:SetAttribute("quantity", 1)

	local order = getOrder(player)
	local firstSlot
	for slot, name in order do
		if name == toolName then
			if firstSlot then
				order[slot] = nil
			else
				firstSlot = slot
			end
		end
	end
	if not firstSlot then
		local slot = findFreeSlot(player)
		if not slot then return false end
		order[slot] = toolName
	end

	trackAttributes(player, tool)
	InventoryService:Sync(player)
	save(player)
	return true
end

function InventoryService:Remove(player: Player, toolName: string, n: number)
	local tool = InventoryService:Get(player, toolName)
	if not tool then return end

	local remaining = (tool:GetAttribute("quantity") or 0) - n
	tool:SetAttribute("quantity", remaining)

	if remaining <= 0 then
		local slot = InventoryService:GetSlot(player, toolName)
		if slot then
			getOrder(player)[slot] = nil
		end
		tool:Destroy()
	end

	InventoryService:Sync(player)
	save(player)
end

function InventoryService:RemoveAll(player: Player, toolName: string): number
	local tool = InventoryService:Get(player, toolName)
	if not tool then return 0 end

	local amount = tool:GetAttribute("quantity") or 0
	InventoryService:Remove(player, toolName, amount)
	return amount
end

function InventoryService:Clear(player: Player)
	for _, tool in InventoryService:GetAll(player) do
		tool:Destroy()
	end
	Order[player] = {}
	InventoryService:Sync(player)
	save(player)
end

function InventoryService:Move(player: Player, from: number, to: number): boolean
	if from == to then return false end
	if from < 1 or from > CAPACITY or to < 1 or to > CAPACITY then return false end

	local order = getOrder(player)
	if order[from] == nil then return false end

	order[from], order[to] = order[to], order[from]
	InventoryService:Sync(player)
	save(player)
	return true
end

local function reconcile(player: Player)
	local tools = InventoryService:GetAll(player)
	local order = getOrder(player)

	local placed = {}
	for index, toolName in order do
		if tools[toolName] then
			placed[toolName] = true
		else
			order[index] = nil
		end
	end

	local unplaced = {}
	for toolName in tools do
		if not placed[toolName] then
			table.insert(unplaced, toolName)
		end
	end
	table.sort(unplaced)

	for _, toolName in unplaced do
		local slot = findFreeSlot(player)
		if not slot then break end
		order[slot] = toolName
	end

	for _, tool in tools do
		trackAttributes(player, tool)
	end
	InventoryService:Sync(player)
	save(player)
end

local function restore(player: Player)
	local profile = DataSaveService:Wait(player)
	if player.Parent ~= Players then return end

	local backpack = player:FindFirstChildOfClass("Backpack")
		or player:WaitForChild("Backpack", 10)
	if not backpack or not backpack:IsA("Backpack") then return end

	local order = getOrder(player)
	local placed = {}
	for _, entry in profile.Data.Inventory or {} do
		if type(entry) ~= "table" then continue end
		local name = entry.Name
		local slot = entry.Slot
		local quantity = entry.Quantity
		if type(name) ~= "string" or type(slot) ~= "number" or type(quantity) ~= "number" then continue end
		slot = math.floor(slot)
		quantity = math.floor(quantity)
		if slot < 1 or slot > CAPACITY or quantity < 1 or placed[name] or order[slot] then continue end

		local template = Tools:FindFirstChild(name)
		if not template or not template:IsA("Tool") then continue end

		local tool = InventoryService:Get(player, name) or template:Clone()
		tool:SetAttribute("quantity", quantity)
		if type(entry.Attributes) == "table" then
			for _, attribute in SAVED_ATTRIBUTES do
				local value = entry.Attributes[attribute]
				if value ~= nil then tool:SetAttribute(attribute, value) end
			end
		end

		order[slot] = name
		placed[name] = true
		trackAttributes(player, tool)
		if tool.Parent == nil then tool.Parent = backpack end
	end

	Ready[player] = true
	reconcile(player)
	InventoryService:EnsureSingle(player, "Walkie Talkie")
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then return end

	humanoid.Died:Once(function()
		task.delay(0.1, function()
			if player.Parent == Players then InventoryService:Clear(player) end
		end)
	end)
end

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(watchCharacter, player, character)
		if Ready[player] then
			task.defer(reconcile, player)
			task.defer(InventoryService.EnsureSingle, InventoryService, player, "Walkie Talkie")
		end
	end)
	task.spawn(restore, player)
end

DeleteRemote.OnServerEvent:Connect(function(player: Player, toolName: any, n: any)
	if type(toolName) ~= "string" then return end
	n = tonumber(n)
	if not n then return end
	n = math.floor(n)
	if n <= 0 then return end

	InventoryService:Remove(player, toolName, n)
end)

MoveRemote.OnServerEvent:Connect(function(player: Player, from: any, to: any)
	from, to = tonumber(from), tonumber(to)
	if not from or not to then
		InventoryService:Sync(player)
		return
	end
	if from ~= math.floor(from) or to ~= math.floor(to) then
		InventoryService:Sync(player)
		return
	end

	if not InventoryService:Move(player, from, to) then
		InventoryService:Sync(player)
	end
end)

UpdateRemote.OnServerEvent:Connect(function(player: Player)
	reconcile(player)
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	for tool in AttributeConnections do
		if tool.Parent == nil
			or (backpack and tool:IsDescendantOf(backpack))
			or (character and tool:IsDescendantOf(character))
		then
			untrackAttributes(tool)
		end
	end
	Order[player] = nil
	Ready[player] = nil
end)

return InventoryService
