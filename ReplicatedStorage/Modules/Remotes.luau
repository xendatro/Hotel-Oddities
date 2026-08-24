local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FolderName = "Communication"

local function getCommunication(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FolderName)
		if existing then return existing :: Folder end
		local folder = Instance.new("Folder")
		folder.Name = FolderName
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FolderName) :: Folder
end

function Remotes.Get(folderName: string, remoteName: string): any
	local communication = getCommunication()
	local folder = communication:WaitForChild(folderName)
	return folder:WaitForChild(remoteName)
end

function Remotes.Find(folderName: string, remoteName: string): any
	local communication = ReplicatedStorage:FindFirstChild(FolderName)
	local folder = communication and communication:FindFirstChild(folderName)
	return if folder then folder:FindFirstChild(remoteName) else nil
end

function Remotes.Ensure(folderName: string, remoteName: string, className: string?): any
	local communication = getCommunication()
	local folder = communication:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = communication
	end
	local remote = folder:FindFirstChild(remoteName)
	if not remote then
		remote = Instance.new(className or "RemoteEvent")
		remote.Name = remoteName
		remote.Parent = folder
	end
	return remote
end

return Remotes
