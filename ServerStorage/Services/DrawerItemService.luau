local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local ItemConfig = require(ReplicatedStorage.Configs.DrawerItemConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local CoinService = require(ServerStorage.Services.CoinService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local GemService = require(ServerStorage.Services.GemService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local Tools = ReplicatedStorage.Tools
local Other = ReplicatedStorage.Props.Other
local Pickup = CommunicationService.Get(ItemConfig.Remotes.Folder, ItemConfig.Remotes.Pickup) :: RemoteEvent

local DrawerItemService = {}

local RandomGenerator = Random.new()
local Drawers: { [Model]: true } = {}
local ItemByDrawer: { [Model]: Model } = {}
local DrawerByItem: { [Model]: Model } = {}
local HallwayItems: { [Model]: true } = {}
local LastPickup: { [Player]: number } = {}
local HallwayFolder = Instance.new("Folder")
HallwayFolder.Name = "HallwayDrawerItems"
HallwayFolder.Parent = workspace

local LastDrawer: Model? = nil
local LastItemName: string? = nil
local NextRefillAt = 0
local REFILL_CHECK_INTERVAL = 1
local REFILL_POLL_INTERVAL = 0.25
local PICKUP_DEBOUNCE = 0.15

local function isCode(instance: Instance): boolean
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

local function disableLights(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
end

local function makeDisplay(template: Instance): Model?
	local display = Instance.new("Model")
	display.Name = `DrawerItem_{template.Name}`
	display:SetAttribute(ItemConfig.Attribute, template.Name)
	display.WorldPivot = template:GetPivot()

	if template:IsA("BasePart") then
		template:Clone().Parent = display
	else
		for _, child in template:GetChildren() do
			if isCode(child) then continue end

			local clone = child:Clone()
			for _, descendant in clone:GetDescendants() do
				if isCode(descendant) then
					descendant:Destroy()
				end
			end
			clone.Parent = display
		end
	end
	disableLights(display)

	display:PivotTo(CFrame.new())

	local hasPart = false
	for _, descendant in display:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end

		hasPart = true
		descendant.Anchored = true
		descendant.CanCollide = false
		descendant.CanTouch = false
		descendant.CanQuery = true
	end

	if not hasPart then
		display:Destroy()
		return nil
	end

	return display
end

local function belongsToItem(instance: Instance): boolean
	local ancestor = instance.Parent
	while ancestor and ancestor ~= workspace do
		if CollectionService:HasTag(ancestor, ItemConfig.Tag) then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function outwardAxis(drawer: Model): Vector3
	local pivot = drawer:GetPivot()
	local keyword = DrawerConfig.HandleKeyword:lower()

	for _, descendant in drawer:GetDescendants() do
		if not descendant:IsA("BasePart")
			or belongsToItem(descendant)
			or not descendant.Name:lower():find(keyword, 1, true)
		then
			continue
		end

		local offset = pivot:PointToObjectSpace(descendant.Position)
		if math.abs(offset.X) >= math.abs(offset.Z) then
			if math.abs(offset.X) > DrawerConfig.HandleThreshold then
				return Vector3.new(math.sign(offset.X), 0, 0)
			end
		elseif math.abs(offset.Z) > DrawerConfig.HandleThreshold then
			return Vector3.new(0, 0, math.sign(offset.Z))
		end
	end

	return DrawerConfig.OutwardAxis.Unit
end

local function drawerBounds(drawer: Model): (CFrame, Vector3)
	local pivot = drawer:GetPivot()
	local keyword = DrawerConfig.HandleKeyword:lower()
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, descendant in drawer:GetDescendants() do
		if not descendant:IsA("BasePart")
			or belongsToItem(descendant)
			or descendant.Name:lower():find(keyword, 1, true)
		then
			continue
		end

		local part = pivot:ToObjectSpace(descendant.CFrame)
		local right = part.RightVector * descendant.Size.X / 2
		local up = part.UpVector * descendant.Size.Y / 2
		local look = part.LookVector * descendant.Size.Z / 2
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local corner = part.Position + right * x + up * y + look * z
					minimum = Vector3.new(
						math.min(minimum.X, corner.X),
						math.min(minimum.Y, corner.Y),
						math.min(minimum.Z, corner.Z)
					)
					maximum = Vector3.new(
						math.max(maximum.X, corner.X),
						math.max(maximum.Y, corner.Y),
						math.max(maximum.Z, corner.Z)
					)
				end
			end
		end
	end

	local center = (minimum + maximum) / 2
	return pivot * CFrame.new(center), maximum - minimum
end

local function extentAlong(cframe: CFrame, size: Vector3, axis: Vector3): number
	return math.abs(axis:Dot(cframe.RightVector)) * size.X / 2
		+ math.abs(axis:Dot(cframe.UpVector)) * size.Y / 2
		+ math.abs(axis:Dot(cframe.LookVector)) * size.Z / 2
end

local function placeOnDrawer(drawer: Model, display: Model)
	local drawerCFrame, drawerSize = drawerBounds(drawer)
	local axis = outwardAxis(drawer)
	display.Parent = drawer
	display:PivotTo(drawerCFrame)

	local itemCFrame, itemSize = display:GetBoundingBox()
	local itemOffset = drawerCFrame:PointToObjectSpace(itemCFrame.Position)
	local drawerDepth = if math.abs(axis.X) > 0 then drawerSize.X else drawerSize.Z
	local itemDepth = extentAlong(itemCFrame, itemSize, drawerCFrame:VectorToWorldSpace(axis))
	local itemHalfHeight = extentAlong(itemCFrame, itemSize, Vector3.yAxis)
	local padding = ItemConfig.Spawn.SurfacePadding
	local floor = if itemHalfHeight * 2 <= drawerSize.Y - padding * 2
		then -drawerSize.Y / 2 + itemHalfHeight + padding
		else drawerSize.Y / 2 - itemHalfHeight - padding
	local depth = drawerDepth / 2 - itemDepth - padding
	local target = drawerCFrame * CFrame.new(axis * depth + Vector3.yAxis * floor - itemOffset)

	display:PivotTo(target)
	CollectionService:AddTag(display, ItemConfig.Tag)
end

local function templateFor(itemName: string): Instance?
	local tool = Tools:FindFirstChild(itemName)
	if tool and tool:IsA("Tool") then return tool end

	local currency = Other:FindFirstChild(itemName)
	if currency and currency:IsA("BasePart") then return currency end
	return nil
end

local function spawnItem(drawer: Model, itemName: string): Model?
	if ItemByDrawer[drawer] then return nil end

	local template = templateFor(itemName)
	if not template then return nil end

	local display = makeDisplay(template)
	if not display then return nil end

	placeOnDrawer(drawer, display)
	ItemByDrawer[drawer] = display
	DrawerByItem[display] = drawer
	LastDrawer = drawer
	LastItemName = itemName
	return display
end

local function surveyDrawers(): (number, number, { Model }, { Model })
	local itemCount = 0
	for drawer, item in ItemByDrawer do
		if not drawer:IsDescendantOf(workspace) or item.Parent ~= drawer or not CollectionService:HasTag(item, ItemConfig.Tag) then
			ItemByDrawer[drawer] = nil
			DrawerByItem[item] = nil
			continue
		end

		local itemName = item:GetAttribute(ItemConfig.Attribute)
		if type(itemName) ~= "string" or not ItemConfig.Currencies[itemName] then
			itemCount += 1
		end
	end

	local drawerCount = 0
	local candidates: { Model } = {}
	local fallback: { Model } = {}
	for drawer in Drawers do
		if not drawer:IsDescendantOf(workspace) then continue end
		drawerCount += 1
		if ItemByDrawer[drawer] then continue end
		table.insert(fallback, drawer)
		if drawer ~= LastDrawer then
			table.insert(candidates, drawer)
		end
	end

	local target = if drawerCount == 0
		then 0
		else math.min(drawerCount, math.max(1, math.ceil(drawerCount * ItemConfig.Spawn.TargetPercentage)))
	return itemCount, target, candidates, fallback
end

local function surveyCurrencyDrawers(): (number, number, { Model }, { Model })
	local currencyCount = 0
	for drawer, item in ItemByDrawer do
		local itemName = item:GetAttribute(ItemConfig.Attribute)
		if drawer:IsDescendantOf(workspace)
			and item.Parent == drawer
			and CollectionService:HasTag(item, ItemConfig.Tag)
			and type(itemName) == "string"
			and ItemConfig.Currencies[itemName]
		then
			currencyCount += 1
		end
	end

	local drawerCount = 0
	local candidates: { Model } = {}
	local fallback: { Model } = {}
	for drawer in Drawers do
		if not drawer:IsDescendantOf(workspace) then continue end
		drawerCount += 1
		if ItemByDrawer[drawer] then continue end
		table.insert(fallback, drawer)
		if drawer ~= LastDrawer then
			table.insert(candidates, drawer)
		end
	end

	local target = if drawerCount == 0
		then 0
		else math.min(drawerCount, math.max(1, math.ceil(drawerCount * ItemConfig.Spawn.CurrencyTargetPercentage)))
	return currencyCount, target, candidates, fallback
end

local function pickDrawer(candidates: { Model }, fallback: { Model }): Model?
	local pool = if #candidates > 0 then candidates else fallback
	if #pool == 0 then return nil end

	local index = RandomGenerator:NextInteger(1, #pool)
	local drawer = pool[index]
	table.remove(pool, index)
	local other = if pool == candidates then fallback else candidates
	local otherIndex = table.find(other, drawer)
	if otherIndex then
		table.remove(other, otherIndex)
	end
	return drawer
end

local function chooseItemName(): string?
	local candidates = {}
	local fallback = {}
	local totalWeight = 0
	local fallbackWeight = 0

	for toolName, rarityName in ItemConfig.Items do
		local rarityWeight = ItemConfig.Rarities[rarityName]
		local template = Tools:FindFirstChild(toolName)
		if type(rarityName) ~= "string" or type(rarityWeight) ~= "number" or rarityWeight <= 0 then continue end
		if not template or not template:IsA("Tool") then continue end

		fallbackWeight += rarityWeight
		table.insert(fallback, { Name = toolName, Weight = rarityWeight })
		if toolName ~= LastItemName then
			totalWeight += rarityWeight
			table.insert(candidates, { Name = toolName, Weight = rarityWeight })
		end
	end

	local pool = if #candidates > 0 then candidates else fallback
	local weight = if #candidates > 0 then totalWeight else fallbackWeight
	if #pool == 0 or weight <= 0 then return nil end

	local roll = RandomGenerator:NextNumber(0, weight)
	for _, entry in pool do
		roll -= entry.Weight
		if roll <= 0 then return entry.Name end
	end
	return pool[#pool].Name
end

local function chooseCurrencyName(): string?
	local candidates = {}
	local fallback = {}
	local totalWeight = 0
	local fallbackWeight = 0

	for currencyName, entry in ItemConfig.Currencies do
		if type(currencyName) ~= "string" or type(entry) ~= "table" then continue end
		local weight = entry.Weight
		local template = Other:FindFirstChild(currencyName)
		if type(weight) ~= "number" or weight <= 0 or not template or not template:IsA("BasePart") then continue end

		fallbackWeight += weight
		table.insert(fallback, { Name = currencyName, Weight = weight })
		if currencyName ~= LastItemName then
			totalWeight += weight
			table.insert(candidates, { Name = currencyName, Weight = weight })
		end
	end

	local pool = if #candidates > 0 then candidates else fallback
	local weight = if #candidates > 0 then totalWeight else fallbackWeight
	if #pool == 0 or weight <= 0 then return nil end

	local roll = RandomGenerator:NextNumber(0, weight)
	for _, entry in pool do
		roll -= entry.Weight
		if roll <= 0 then return entry.Name end
	end
	return pool[#pool].Name
end

local function floorTarget(position: Vector3, itemCFrame: CFrame, itemSize: Vector3): CFrame
	local itemHalfHeight = extentAlong(itemCFrame, itemSize, Vector3.yAxis)
	return CFrame.new(
		position.X - itemCFrame.Position.X,
		position.Y + itemHalfHeight - itemCFrame.Position.Y,
		position.Z - itemCFrame.Position.Z
	)
end

local function hallwaySurface(position: Vector3): Vector3?
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.RespectCanCollide = true
	raycast.FilterDescendantsInstances = { HallwayFolder }

	local result = workspace:Raycast(position + Vector3.yAxis * 2, Vector3.yAxis * -4, raycast)
	if not result then return nil end
	if not CollectionService:HasTag(result.Instance, "MazeFloor")
		and not CollectionService:HasTag(result.Instance, "HallwayRoomFloor")
		and not ItemConfig.Hallway.SupportSurfaceNames[result.Instance.Name]
	then
		return nil
	end
	return result.Position
end

local function overlapsWorldGeometry(cframe: CFrame, size: Vector3): boolean
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.RespectCanCollide = false
	overlap.FilterDescendantsInstances = { HallwayFolder }

	for _, part in workspace:GetPartBoundsInBox(cframe, size, overlap) do
		if CollectionService:HasTag(part, "MazeFloor")
			or CollectionService:HasTag(part, "HallwayRoomFloor")
			or ItemConfig.Hallway.SupportSurfaceNames[part.Name]
		then
			continue
		end
		return true
	end
	return false
end

local function isNearPlayer(position: Vector3): boolean
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root and (root.Position - position).Magnitude < ItemConfig.Hallway.MinimumPlayerDistance then
			return true
		end
	end
	return false
end

local function isNearHallwayItem(position: Vector3): boolean
	for item in HallwayItems do
		if not item.Parent then
			HallwayItems[item] = nil
		elseif (item:GetPivot().Position - position).Magnitude < ItemConfig.Hallway.MinimumSpacing then
			return true
		end
	end
	return false
end

local function trySpawnHallway(): boolean
	local activeCount = 0
	for item in HallwayItems do
		if item.Parent then
			activeCount += 1
		else
			HallwayItems[item] = nil
		end
	end
	if activeCount >= ItemConfig.Hallway.MaxAlive then return false end

	local currencyName = chooseCurrencyName()
	local template = currencyName and templateFor(currencyName)
	if not template then return false end

	local display = makeDisplay(template)
	if not display then return false end

	local itemCFrame, itemSize = display:GetBoundingBox()
	local point = DangerMapService:PickPoint(0, function(candidate)
		local surface = hallwaySurface(candidate.Position)
		if not Hallways.At(candidate.Position)
			or not surface
			or isNearPlayer(candidate.Position)
			or isNearHallwayItem(candidate.Position)
		then
			return false
		end

		return not overlapsWorldGeometry(floorTarget(surface, itemCFrame, itemSize), itemSize)
	end, ItemConfig.Hallway.PlacementAttempts)
	if not point then
		display:Destroy()
		return false
	end

	local surface = hallwaySurface(point.Position)
	if not surface then
		display:Destroy()
		return false
	end
	display:PivotTo(floorTarget(surface, itemCFrame, itemSize))
	display.Parent = HallwayFolder
	CollectionService:AddTag(display, ItemConfig.Tag)
	HallwayItems[display] = true
	LastItemName = currencyName
	return true
end

local function fillCurrencies()
	local _, target, candidates, fallback = surveyCurrencyDrawers()
	for _ = 1, target do
		local drawer = pickDrawer(candidates, fallback)
		local currencyName = chooseCurrencyName()
		if not drawer or not currencyName or not spawnItem(drawer, currencyName) then break end
	end
end

local function fillItems()
	local _, target, candidates, fallback = surveyDrawers()
	for _ = 1, target do
		local drawer = pickDrawer(candidates, fallback)
		local toolName = chooseItemName()
		if not drawer or not toolName or not spawnItem(drawer, toolName) then break end
	end
end

local function fillInitial()
	for _ = 1, ItemConfig.Hallway.InitialAlive do
		if not trySpawnHallway() then break end
	end

	fillCurrencies()
	fillItems()
end

local function registerDrawer(instance: Instance)
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then return end
	Drawers[instance] = true
end

local function unregisterDrawer(instance: Instance)
	if not instance:IsA("Model") then return end

	local item = ItemByDrawer[instance]
	if item then
		DrawerByItem[item] = nil
		ItemByDrawer[instance] = nil
	end
	Drawers[instance] = nil
end

local function drawerOf(item: Model): Model?
	local instance: Instance? = item.Parent
	while instance and instance ~= workspace do
		if instance:IsA("Model") and Drawers[instance] then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

Pickup.OnServerEvent:Connect(function(player: Player, item: any)
	if typeof(item) ~= "Instance" or not item:IsA("Model") then return end
	if not item:IsDescendantOf(workspace) or not CollectionService:HasTag(item, ItemConfig.Tag) then return end

	local drawer = drawerOf(item)
	local isHallwayItem = HallwayItems[item] == true
	if not isHallwayItem and (not drawer or ItemByDrawer[drawer] ~= item or DrawerByItem[item] ~= drawer) then return end
	if isHallwayItem and drawer then return end

	local itemName = item:GetAttribute(ItemConfig.Attribute)
	if type(itemName) ~= "string" then return end
	local currency = ItemConfig.Currencies[itemName]
	if not ItemConfig.Items[itemName] and not currency then return end

	local now = os.clock()
	if now - (LastPickup[player] or 0) < PICKUP_DEBOUNCE then return end

	local position = CharacterService.GetPosition(player)
	if not position or (item:GetPivot().Position - position).Magnitude > DrawerConfig.Targeting.ServerReach then return end

	LastPickup[player] = now
	local collected = false
	if currency then
		if currency.Currency == "Coins" then
			collected = CoinService:Award(player, currency.Amount)
		elseif currency.Currency == "Gems" then
			collected = GemService:Award(player, currency.Amount)
		end
	else
		if not InventoryService:Wait(player, 10) then return end
		collected = InventoryService:Add(player, itemName, 1)
	end
	if not collected then return end

	if drawer then
		ItemByDrawer[drawer] = nil
		DrawerByItem[item] = nil
		LastDrawer = drawer
		NextRefillAt = math.max(NextRefillAt, now + ItemConfig.Spawn.RefillDelay)
	else
		HallwayItems[item] = nil
		NextRefillAt = math.max(NextRefillAt, now + ItemConfig.Hallway.RefillDelay)
	end
	LastItemName = itemName
	item:Destroy()
end)

for _, instance in CollectionService:GetTagged(DrawerConfig.Tag) do
	registerDrawer(instance)
end

CollectionService:GetInstanceAddedSignal(DrawerConfig.Tag):Connect(registerDrawer)
CollectionService:GetInstanceRemovedSignal(DrawerConfig.Tag):Connect(unregisterDrawer)

fillInitial()

local Accumulator = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < REFILL_POLL_INTERVAL then return end
	Accumulator = 0

	local now = os.clock()
	if now < NextRefillAt then return end

	local itemCount, itemTarget, itemCandidates, itemFallback = surveyDrawers()
	local currencyCount, currencyTarget, currencyCandidates, currencyFallback = surveyCurrencyDrawers()
	local hallwayCount = 0
	for item in HallwayItems do
		if item.Parent then
			hallwayCount += 1
		else
			HallwayItems[item] = nil
		end
	end

	if itemCount >= itemTarget and currencyCount >= currencyTarget and hallwayCount >= ItemConfig.Hallway.MaxAlive then
		NextRefillAt = now + REFILL_CHECK_INTERVAL
		return
	end

	local drawer
	local itemName
	if itemCount < itemTarget then
		drawer = pickDrawer(itemCandidates, itemFallback)
		itemName = chooseItemName()
	end
	if (not drawer or not itemName) and currencyCount < currencyTarget then
		drawer = pickDrawer(currencyCandidates, currencyFallback)
		itemName = chooseCurrencyName()
	end

	local spawned = drawer and itemName and spawnItem(drawer, itemName)
	if spawned then
		NextRefillAt = now + ItemConfig.Spawn.RefillDelay
	elseif hallwayCount < ItemConfig.Hallway.MaxAlive and trySpawnHallway() then
		NextRefillAt = now + ItemConfig.Hallway.RefillDelay
	else
		NextRefillAt = now + 1
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastPickup[player] = nil
end)

return DrawerItemService
