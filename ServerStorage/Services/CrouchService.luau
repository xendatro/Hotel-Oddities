local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)

local CrouchService = {}

local ATTRIBUTE = CrouchConfig.Stealth.Attribute
local MIN_REPORT_INTERVAL = 0.05

local communication = ReplicatedStorage:FindFirstChild("Communication")
if not communication then
	communication = Instance.new("Folder")
	communication.Name = "Communication"
	communication.Parent = ReplicatedStorage
end

local folder = communication:FindFirstChild("Crouch")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Crouch"
	folder.Parent = communication
end

local Update = folder:FindFirstChild("Update") :: RemoteEvent?
if not Update then
	Update = Instance.new("RemoteEvent")
	Update.Name = "Update"
	Update.Parent = folder
end

local lastReportAt: { [Player]: number } = {}

Update.OnServerEvent:Connect(function(player: Player, crouched: any)
	if type(crouched) ~= "boolean" then return end

	local now = os.clock()
	if now - (lastReportAt[player] or 0) < MIN_REPORT_INTERVAL then return end
	lastReportAt[player] = now

	local character = player.Character
	if not character then return end

	character:SetAttribute(ATTRIBUTE, crouched or nil)
end)

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:SetAttribute(ATTRIBUTE, nil)
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastReportAt[player] = nil
end)

return CrouchService
