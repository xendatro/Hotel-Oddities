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
		Ancestor: Instance?,
		TagConnections: {RBXScriptConnection},
	}
}

local Tags: Tags = {}

type AncestorWatch = {
	Added: RBXScriptConnection,
	Removing: RBXScriptConnection,
	Listeners: { [string]: { Apply: (Instance) -> (), Unapply: (Instance) -> () } },
}

local AncestorWatches: { [Instance]: AncestorWatch } = {}

local function watchAncestor(ancestor: Instance, tag: string, apply: (Instance) -> (), unapply: (Instance) -> ())
	local watch = AncestorWatches[ancestor]
	if not watch then
		local listeners: { [string]: { Apply: (Instance) -> (), Unapply: (Instance) -> () } } = {}
		watch = {
			Listeners = listeners,
			Added = ancestor.DescendantAdded:Connect(function(instance: Instance)
				for _, name in instance:GetTags() do
					local listener = listeners[name]
					if listener then listener.Apply(instance) end
				end
			end),
			Removing = ancestor.DescendantRemoving:Connect(function(instance: Instance)
				for _, name in instance:GetTags() do
					local listener = listeners[name]
					if listener then listener.Unapply(instance) end
				end
			end),
		}
		AncestorWatches[ancestor] = watch
	end
	watch.Listeners[tag] = { Apply = apply, Unapply = unapply }
end

local function unwatchAncestor(ancestor: Instance, tag: string)
	local watch = AncestorWatches[ancestor]
	if not watch then return end
	watch.Listeners[tag] = nil
	if next(watch.Listeners) ~= nil then return end
	watch.Added:Disconnect()
	watch.Removing:Disconnect()
	AncestorWatches[ancestor] = nil
end

function TagService:Listen(tag: string, apply: (instance: Instance) -> any, unapply: (instance: Instance, data: any) -> nil, ancestor: Instance?): nil
	if Tags[tag] then
		warn("Attempted to listen to active tag")
		return
	end

	Tags[tag] = {
		Instances = {},
		Data = {},
		InstanceConnections = {},
		Apply = apply,
		Unapply = unapply,
		Ancestor = ancestor,
		TagConnections = {}
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
			if instance.Parent ~= nil then return end

			task.defer(function()
				if instance.Parent == nil then
					unapplyFunction(instance)
				end
			end)
		end)
	end

	Tags[tag].TagConnections.InstanceAdded = CollectionService:GetInstanceAddedSignal(tag):Connect(applyFunction)

	Tags[tag].TagConnections.InstanceRemoved = CollectionService:GetInstanceRemovedSignal(tag):Connect(unapplyFunction)

	if ancestor then
		watchAncestor(ancestor, tag, applyFunction, unapplyFunction)
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
	for _, connection in Tags[tag].InstanceConnections do
		connection:Disconnect()
	end
	local ancestor = Tags[tag].Ancestor
	if ancestor then
		unwatchAncestor(ancestor, tag)
	end
	Tags[tag] = nil
end

function TagService:GetAllApplied(tag: string): {[Instance]: any}
	return table.clone(Tags[tag].Data)
end

function TagService:GetApplied(tag: string, instance: Instance)
	return Tags[tag].Data[instance]
end

function TagService:GetTaggedOfPredicate(tag: string, predicate: (instance: Instance) -> boolean): {Instance}
	local t = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if predicate(instance) then
			table.insert(t, instance)
		end
	end
	return t
end

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
