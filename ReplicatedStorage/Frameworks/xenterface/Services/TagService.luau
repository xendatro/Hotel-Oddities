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

function TagService:Listen(tag: string, apply: (instance: Instance) -> any, unapply: (instance: Instance, data: any) -> nil, ancestor: Instance): nil
	if Tags[tag] then
		warn("Attempted to listen to active tag")
		return
	end
	
	
	Tags[tag] = {
		Instances = {}, -- If the instance has been registered
		Data = {}, -- Return values from the apply function
		InstanceConnections = {}, -- Instance connections
		Apply = apply, -- Function to apply when active
		Unapply = apply, -- Function to unapply when inactive
		TagConnections = {} -- Signals to listen to when to go active or inactive
	}
	
	local function unapplyFunction(instance: Instance)
		if Tags[tag].Instances[instance] == nil then return end

		Tags[tag].Instances[instance] = nil
		local data = Tags[tag].Data[instance] 
		Tags[tag].Data[instance] = nil
		for _, connection in Tags[tag].InstanceConnections do
			connection:Disconnect()
		end
		unapply(instance, data)
	end
	
	local function applyFunction(instance)
		if Tags[tag].Instances[instance] then return end
		if not instance:IsDescendantOf(ancestor) then return end
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

	Tags[tag].TagConnections.DescendantAdded = ancestor.DescendantAdded:Connect(applyFunction)
	
	Tags[tag].TagConnections.InstanceRemoved = CollectionService:GetInstanceRemovedSignal(tag):Connect(unapplyFunction)
	
	Tags[tag].TagConnections.DescendantRemoving = ancestor.DescendantRemoving:Connect(unapplyFunction)
	
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