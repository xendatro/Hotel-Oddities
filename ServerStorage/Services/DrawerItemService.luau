local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local ItemConfig = require(ReplicatedStorage.Configs.DrawerItemConfig)
local InventoryService = require(script.Parent.InventoryService)

local Tools = ReplicatedStorage.Tools
local Pickup = ReplicatedStorage.Communication[ItemConfig.Remotes.Folder][ItemConfig.Remotes.Pickup] :: RemoteEvent

local DrawerItemService = {}

local RandomGenerator = Random.new()
local Drawers: { [Model]: true } = {}
local ItemByDrawer: { [Model]: Model } = {}
local DrawerByItem: { [Model]: Model } = {}
local LastPickup: { [Player]: number } = {}

local LastDrawer: Model? = nil
local LastItemName: string? = nil
local NextRefillAt = 0

local function isCode(instance: Instance): boolean
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

local function makeDisplay(template: Tool): Model?
	local display = Instance.new("Model")
	display.Name = `DrawerItem_{template.Name}`
	display:SetAttribute(ItemConfig.Attribute, template.Name)
	display.WorldPivot = template:GetPivot()

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

local function spawnItem(drawer: Model, toolName: string): Model?
	if ItemByDrawer[drawer] then return nil end

	local template = Tools:FindFirstChild(toolName)
	if not template or not template:IsA("Tool") then return nil end

	local display = makeDisplay(template)
	if not display then return nil end

	placeOnDrawer(drawer, display)
	ItemByDrawer[drawer] = display
	DrawerByItem[display] = drawer
	LastDrawer = drawer
	LastItemName = toolName
	return display
end

local function cleanItems(): number
	local count = 0
	for drawer, item in ItemByDrawer do
		if drawer:IsDescendantOf(workspace) and item.Parent == drawer and CollectionService:HasTag(item, ItemConfig.Tag) then
			count += 1
		else
			ItemByDrawer[drawer] = nil
			DrawerByItem[item] = nil
		end
	end
	return count
end

local function chooseDrawer(): Model?
	local candidates = {}
	local fallback = {}

	for drawer in Drawers do
		if not drawer:IsDescendantOf(workspace) or ItemByDrawer[drawer] then continue end
		table.insert(fallback, drawer)
		if drawer ~= LastDrawer then
			table.insert(candidates, drawer)
		end
	end

	local pool = if #candidates > 0 then candidates else fallback
	if #pool == 0 then return nil end
	return pool[RandomGenerator:NextInteger(1, #pool)]
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

local function targetCount(): number
	local count = 0
	for drawer in Drawers do
		if drawer:IsDescendantOf(workspace) then
			count += 1
		end
	end
	if count == 0 then return 0 end

	return math.min(count, math.max(1, math.ceil(count * ItemConfig.Spawn.TargetPercentage)))
end

local function fillInitial()
	for _ = 1, targetCount() do
		local drawer = chooseDrawer()
		local toolName = chooseItemName()
		if not drawer or not toolName or not spawnItem(drawer, toolName) then break end
	end
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

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return nil end
	return root.Position
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
	if not drawer or ItemByDrawer[drawer] ~= item or DrawerByItem[item] ~= drawer then return end

	local toolName = item:GetAttribute(ItemConfig.Attribute)
	if type(toolName) ~= "string" or not ItemConfig.Items[toolName] then return end

	local now = os.clock()
	if now - (LastPickup[player] or 0) < 0.15 then return end

	local position = characterPosition(player)
	if not position or (item:GetPivot().Position - position).Magnitude > DrawerConfig.Targeting.ServerReach then return end

	LastPickup[player] = now
	if not InventoryService:Wait(player, 10) then return end
	if not InventoryService:Add(player, toolName, 1) then return end

	ItemByDrawer[drawer] = nil
	DrawerByItem[item] = nil
	LastDrawer = drawer
	LastItemName = toolName
	NextRefillAt = math.max(NextRefillAt, now + ItemConfig.Spawn.RefillDelay)
	item:Destroy()
end)

for _, instance in CollectionService:GetTagged(DrawerConfig.Tag) do
	registerDrawer(instance)
end

CollectionService:GetInstanceAddedSignal(DrawerConfig.Tag):Connect(registerDrawer)
CollectionService:GetInstanceRemovedSignal(DrawerConfig.Tag):Connect(unregisterDrawer)

fillInitial()

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < NextRefillAt then return end
	if cleanItems() >= targetCount() then return end

	local drawer = chooseDrawer()
	local toolName = chooseItemName()
	if drawer and toolName and spawnItem(drawer, toolName) then
		NextRefillAt = now + ItemConfig.Spawn.RefillDelay
	else
		NextRefillAt = now + 1
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastPickup[player] = nil
end)

return DrawerItemService
