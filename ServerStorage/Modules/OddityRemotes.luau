local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OddityRemotes = {}

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then return existing :: Folder end

	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

function OddityRemotes.Event(name: string): RemoteEvent
	local oddities = folder(folder(ReplicatedStorage, "Communication"), "Oddities")

	local existing = oddities:FindFirstChild(name)
	if existing then return existing :: RemoteEvent end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = oddities
	return remote
end

return OddityRemotes
