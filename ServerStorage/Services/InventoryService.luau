local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local Tools = ReplicatedStorage.Tools
local Communication = ReplicatedStorage.Communication.Inventory

local CAPACITY = InventoryConfig.HotbarSlots + InventoryConfig.BackpackSlots
local SAVED_ATTRIBUTES = { "uses" }

--- Owns what every player is carrying: the stacks themselves and the order they sit in.
---
--- Tools stack rather than duplicate -- one Tool instance per kind, carrying a `quantity`
--- attribute -- so a player holding three bandages holds one Tool. That makes a tool's name a
--- unique key within one player's inventory, which is what lets slots be tracked by name safely.
---
--- Slot order lives HERE, not on the client. The client may reorder optimistically for
--- responsiveness, but the server's list is what any later join, respawn or save reads back, and
--- every reorder request is re-validated before it is accepted.
local InventoryService = {}

-- [player] = { [slotIndex] = toolName }, sparse: a hole is an empty slot.
local Order: { [Player]: { [number]: string } } = {}
local Ready: { [Player]: boolean } = {}
local AttributeConnections: { [Tool]: RBXScriptConnection } = {}

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

local function trackAttributes(player: Player, tool: Tool)
	if AttributeConnections[tool] then return end

	local connections = {}
	for _, attribute in SAVED_ATTRIBUTES do
		table.insert(connections, tool:GetAttributeChangedSignal(attribute):Connect(function()
			save(player)
		end))
	end

	AttributeConnections[tool] = tool.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		for _, connection in connections do
			connection:Disconnect()
		end
		local ancestry = AttributeConnections[tool]
		if ancestry then ancestry:Disconnect() end
		AttributeConnections[tool] = nil
	end)
end

--- The player's Tool of that name, whether stowed or equipped, or nil if they have none.
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

--- Every tool the player is carrying, stowed or equipped, keyed by name.
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

--- Total number of items carried, counting stacks.
function InventoryService:GetQuantity(player: Player): number
	local total = 0
	for _, tool in InventoryService:GetAll(player) do
		total += tool:GetAttribute("quantity") or 0
	end
	return total
end

--- The slot a tool occupies, or nil if it has none yet.
function InventoryService:GetSlot(player: Player, toolName: string): number?
	for index, name in getOrder(player) do
		if name == toolName then return index end
	end
	return nil
end

--- The player's slot layout, safe for the caller to keep.
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

-- Lowest free slot, or nil when the inventory is completely full.
local function findFreeSlot(player: Player): number?
	local order = getOrder(player)
	for index = 1, CAPACITY do
		if order[index] == nil then return index end
	end
	return nil
end

--- Pushes the player's current layout and stack counts to their client.
---
--- The payload is a DENSE list whose entries each name their own slot, never a table indexed by
--- slot. An inventory with a gap in it -- slots 1, 2 and 5 filled -- is a sparse array, and remote
--- serialisation silently truncates those at the first hole, so everything past the first empty
--- slot would simply never arrive.
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

	Communication.Update:FireClient(player, payload)
end

--- Grants `n` of a tool, creating the Tool instance and claiming a slot on the player's first one.
--- Returns false when no template of that name exists or the inventory is full.
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

--- Consumes `n` of a tool, destroying it and freeing its slot once the stack empties.
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

--- Consumes the player's whole stack of a tool and returns how many were taken.
function InventoryService:RemoveAll(player: Player, toolName: string): number
	local tool = InventoryService:Get(player, toolName)
	if not tool then return 0 end

	local amount = tool:GetAttribute("quantity") or 0
	InventoryService:Remove(player, toolName, amount)
	return amount
end

--- Strips everything the player is carrying and empties their layout.
function InventoryService:Clear(player: Player)
	for _, tool in InventoryService:GetAll(player) do
		tool:Destroy()
	end
	Order[player] = {}
	InventoryService:Sync(player)
	save(player)
end

--- Moves whatever is in `from` into `to`, swapping if `to` is occupied. Returns whether it applied.
--- Syncs on success, like every other mutating method here -- a caller should never have to
--- remember to push the change itself.
function InventoryService:Move(player: Player, from: number, to: number): boolean
	if from == to then return false end
	if from < 1 or from > CAPACITY or to < 1 or to > CAPACITY then return false end

	local order = getOrder(player)
	if order[from] == nil then return false end -- nothing to move

	order[from], order[to] = order[to], order[from]
	InventoryService:Sync(player)
	save(player)
	return true
end

-- Drops slots whose tool no longer exists and gives a slot to any tool that somehow lacks one.
-- Running this on spawn is what replaces FFM's "purge, then purge again 1.5s later" guesswork:
-- the layout is rebuilt from what is actually there instead of from connections that may never
-- have fired.
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

	-- Alphabetical rather than hash order, so a tool that arrived without a slot lands in the same
	-- place every time instead of the layout reshuffling on each rejoin.
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
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then return end

	humanoid.Died:Once(function()
		-- Revives and Keep Items take their snapshots in their own Died callbacks. Delaying the clear
		-- lets every snapshot finish before the authoritative inventory is emptied and saved.
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
		if Ready[player] then task.defer(reconcile, player) end
	end)
	task.spawn(restore, player)
end

-- Client-driven consumption. Tools whose activation plays out on the client (the ball, the shovel)
-- report the spend here; server-side tools call :Remove directly.
ReplicatedStorage.Communication.Backpack.Delete.OnServerEvent:Connect(function(player: Player, toolName: any, n: any)
	-- Never trust the client's amount: a negative n would otherwise INCREASE the stack.
	if type(toolName) ~= "string" then return end
	n = tonumber(n)
	if not n then return end
	n = math.floor(n)
	if n <= 0 then return end

	InventoryService:Remove(player, toolName, n)
end)

-- Reordering is a request, not an instruction: the client moves its own frames immediately so the
-- drag feels instant, but the authoritative swap happens here and is echoed back to correct it.
Communication.Move.OnServerEvent:Connect(function(player: Player, from: any, to: any)
	from, to = tonumber(from), tonumber(to)
	if not from or not to then
		InventoryService:Sync(player)
		return
	end
	if from ~= math.floor(from) or to ~= math.floor(to) then
		InventoryService:Sync(player)
		return
	end

	-- A rejected move still needs an answer: the client already swapped its own frames to keep the
	-- drag responsive, so silence would leave it showing a layout the server never agreed to.
	if not InventoryService:Move(player, from, to) then
		InventoryService:Sync(player)
	end
end)

-- A client asking for its state. The first Sync a player is sent can easily land before their UI
-- has connected its handler, so the UI asks once on startup rather than trusting that race.
--
-- Reconciles rather than merely syncing, which makes the answer self-healing: a Tool that reached
-- a backpack without going through :Add -- StarterGear, an admin command, anything written later --
-- has no slot yet, and a plain Sync would leave it invisible forever.
Communication.Update.OnServerEvent:Connect(function(player: Player)
	reconcile(player)
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	Order[player] = nil
	Ready[player] = nil
end)

return InventoryService
