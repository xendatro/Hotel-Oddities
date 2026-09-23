local LocalOverride = {}
LocalOverride.__index = LocalOverride

type Entry = {
	Authoritative: any,
	Value: any,
	Written: any,
	Applying: boolean,
	Active: boolean,
}

type Target = {
	Properties: { [string]: Entry },
	Connections: { [string]: RBXScriptConnection },
}

export type LocalOverride = typeof(setmetatable({} :: {
	Targets: { [Instance]: Target },
	Destroyed: boolean,
}, LocalOverride))

local function index(object: any, property: string): any
	return object[property]
end

local function assign(object: any, property: string, value: any)
	object[property] = value
end

local function same(a: any, b: any): boolean
	return a == b or (a ~= a and b ~= b)
end

local function write(instance: Instance, property: string, entry: Entry): boolean
	entry.Applying = true
	local ok, message = pcall(assign, instance, property, entry.Value)
	entry.Applying = false
	if not ok then
		warn(`LocalOverride: could not set {instance:GetFullName()}.{property}: {message}`)
		return false
	end
	entry.Written = index(instance, property)
	return true
end

local function onChanged(instance: Instance, property: string, entry: Entry)
	if entry.Applying or not entry.Active then return end

	local ok, current = pcall(index, instance, property)
	if not ok or same(current, entry.Written) then return end

	entry.Authoritative = current
	write(instance, property, entry)
end

local function drop(self: LocalOverride, instance: Instance)
	local target = self.Targets[instance]
	if not target then return end

	self.Targets[instance] = nil
	for _, entry in target.Properties do
		entry.Active = false
	end
	for _, connection in target.Connections do
		connection:Disconnect()
	end
	table.clear(target.Connections)
end

local function releaseEntry(instance: Instance, target: Target, property: string)
	local entry = target.Properties[property]
	if not entry then return end

	target.Properties[property] = nil
	entry.Active = false
	local connection = target.Connections[property]
	if connection then
		connection:Disconnect()
		target.Connections[property] = nil
	end

	local ok, current = pcall(index, instance, property)
	if ok and not same(current, entry.Written) then return end
	pcall(assign, instance, property, entry.Authoritative)
end

local function setUpConnections(self: LocalOverride, instance: Instance): { [string]: RBXScriptConnection }
	return {
		Destroying = instance.Destroying:Connect(function()
			drop(self, instance)
		end),
	}
end

function LocalOverride.new(): LocalOverride
	return setmetatable({
		Targets = {},
		Destroyed = false,
	}, LocalOverride)
end

function LocalOverride:Set(instance: Instance, property: string, value: any)
	if self.Destroyed then return end

	local target = self.Targets[instance]
	local entry = target and target.Properties[property]
	if target and entry then
		local current = index(instance, property)
		if not same(current, entry.Written) then
			entry.Authoritative = current
		elseif same(value, entry.Value) then
			return
		end
		entry.Value = value
		write(instance, property, entry)
		return
	end

	local readable, current = pcall(index, instance, property)
	local listenable, signal = pcall(instance.GetPropertyChangedSignal, instance, property)
	if not readable or not listenable then
		warn(`LocalOverride: {instance:GetFullName()} has no overridable property "{property}"`)
		return
	end

	local owner: Target = target or {
		Properties = {},
		Connections = setUpConnections(self, instance),
	}
	self.Targets[instance] = owner

	local created: Entry = {
		Authoritative = current,
		Value = value,
		Written = current,
		Applying = false,
		Active = true,
	}
	owner.Properties[property] = created
	owner.Connections[property] = (signal :: RBXScriptSignal):Connect(function()
		onChanged(instance, property, created)
	end)

	if not write(instance, property, created) then
		self:Release(instance, property)
	end
end

function LocalOverride:Release(instance: Instance, property: string?)
	local target = self.Targets[instance]
	if not target then return end

	if property then
		releaseEntry(instance, target, property)
	else
		for name in target.Properties do
			releaseEntry(instance, target, name)
		end
	end

	if next(target.Properties) == nil then
		drop(self, instance)
	end
end

function LocalOverride:Restore()
	for instance in self.Targets do
		self:Release(instance)
	end
end

function LocalOverride:Destroy()
	self:Restore()
	self.Destroyed = true
end

return LocalOverride
