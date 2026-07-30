local CollectionService = game:GetService("CollectionService")

local TagService = {}

type Tags = {
	[string]: {
		Instances: {},
		Data: {any},
		InstanceConnections: {
			[Instance]: RBXScriptConnection
		},
		Apply: (instance: Instance) -> any,
		Unapply: (instance: Instance, data: any) -> any,
		TagConnections: {RBXScriptConnection},
	}
}

local Tags: Tags = {}

--- Wires a class to a tag. A nil `ancestor` means GLOBAL scope -- needed for tools, which move
--- between a player's Backpack and their Character and so have no single ancestor to scope to.
function TagService:Listen(tag: string, apply: (instance: Instance) -> any, unapply: (instance: Instance, data: any) -> nil, ancestor: Instance?): nil
	if Tags[tag] then
		warn("Attempted to listen to active tag")
		return
	end
	
	
	Tags[tag] = {
		Instances = {}, -- If the instance has been registered
		Data = {}, -- Return values from the apply function
		InstanceConnections = {}, -- Instance connections
		Apply = apply, -- Function to apply when active
		Unapply = unapply, -- Function to unapply when inactive
		TagConnections = {} -- Signals to listen to when to go active or inactive
	}
	
	local function unapplyFunction(instance: Instance)
		if Tags[tag].Instances[instance] == nil then return end

		Tags[tag].Instances[instance] = nil
		local data = Tags[tag].Data[instance] 
		Tags[tag].Data[instance] = nil
		local connection = Tags[tag].InstanceConnections[instance]
		if connection then
			connection:Disconnect()
			Tags[tag].InstanceConnections[instance] = nil
		end
		unapply(instance, data)
	end
	
	local function applyFunction(instance)
		if Tags[tag].Instances[instance] then return end
		if ancestor and not instance:IsDescendantOf(ancestor) then return end
		if not instance:HasTag(tag) then return end
		
		Tags[tag].Instances[instance] = true
		Tags[tag].Data[instance] = apply(instance)
		
		Tags[tag].InstanceConnections[instance] = instance.AncestryChanged:Connect(function(instance: Instance)
			if instance.Parent == nil then
				unapplyFunction(instance)
			end
		end)
	end
	
	
	Tags[tag].TagConnections.InstanceAdded = CollectionService:GetInstanceAddedSignal(tag):Connect(applyFunction)

	Tags[tag].TagConnections.InstanceRemoved = CollectionService:GetInstanceRemovedSignal(tag):Connect(unapplyFunction)

	-- Only a scoped listen needs these: they catch already-tagged instances reparented into the
	-- ancestor. A global listen is fully covered by the added signal plus the sweep below.
	if ancestor then
		Tags[tag].TagConnections.DescendantAdded = ancestor.DescendantAdded:Connect(applyFunction)
		Tags[tag].TagConnections.DescendantRemoving = ancestor.DescendantRemoving:Connect(unapplyFunction)
	end

	for _, instance in CollectionService:GetTagged(tag) do
		applyFunction(instance)
	end
end

function TagService:Unlisten(tag: string): nil
	local unapply = Tags[tag].Unapply
	if unapply ~= nil then
		for instance: Instance, data: any in Tags[tag].Data do
			unapply(instance, data)
		end		
	end
	for _, connection in Tags[tag].TagConnections do
		connection:Disconnect()
	end
	Tags[tag] = nil
end

function TagService:GetAllApplied(tag: string): {[Instance]: any}
	return table.clone(Tags[tag].Data)
end

function TagService:GetApplied(tag: string, instance: Instance)
	return Tags[tag].Data[instance]
end

--- Every instance carrying `tag` that satisfies `predicate`. Unlike GetAllApplied this reads
--- CollectionService directly, so it sees tagged instances nothing has Listened to.
function TagService:GetTaggedOfPredicate(tag: string, predicate: (instance: Instance) -> boolean): {Instance}
	local t = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if predicate(instance) then
			table.insert(t, instance)
		end
	end
	return t
end

--- Every instance carrying `tag` that lives under `ancestor`.
function TagService:GetTaggedOfAncestor(ancestor: Instance, tag: string): {Instance}
	return TagService:GetTaggedOfPredicate(tag, function(instance: Instance)
		return instance:IsDescendantOf(ancestor)
	end)
end

function TagService:GetListenedTags()
	local t = {}
	for tag, _ in Tags do
		table.insert(t, tag)
	end
	return t
end

function TagService:GetListenedTagsOfInstance(instance: Instance)
	local t = {}
	for tag, data in Tags do
		if data.Instances[instance] then
			table.insert(t, tag)
		end
	end
	return t
end


return TagService