local ReplicatedStorage = game:GetService("ReplicatedStorage")

local communication = ReplicatedStorage:FindFirstChild("Communication")
if not communication then
	communication = Instance.new("Folder")
	communication.Name = "Communication"
	communication.Parent = ReplicatedStorage
end

local enemies = communication:FindFirstChild("Enemies")
if not enemies then
	enemies = Instance.new("Folder")
	enemies.Name = "Enemies"
	enemies.Parent = communication
end

local remote = enemies:FindFirstChild("EyeHit")

if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end

if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "EyeHit"
	remote.Parent = enemies
end

return { Remote = remote :: RemoteEvent }
