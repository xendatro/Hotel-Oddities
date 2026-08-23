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
local pending: { [Player]: boolean } = {}
local scheduled: { [Player]: boolean } = {}

local function apply(player: Player, crouched: boolean)
	lastReportAt[player] = os.clock()

	local character = player.Character
	if not character then return end

	character:SetAttribute(ATTRIBUTE, crouched or nil)
end

Update.OnServerEvent:Connect(function(player: Player, crouched: any)
	if type(crouched) ~= "boolean" then return end

	local wait = MIN_REPORT_INTERVAL - (os.clock() - (lastReportAt[player] or -math.huge))
	if wait <= 0 then
		apply(player, crouched)
		return
	end

	pending[player] = crouched
	if scheduled[player] then return end

	scheduled[player] = true
	task.delay(wait, function()
		scheduled[player] = nil
		local value = pending[player]
		pending[player] = nil
		if value ~= nil then
			apply(player, value)
		end
	end)
end)

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:SetAttribute(ATTRIBUTE, nil)
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastReportAt[player] = nil
	pending[player] = nil
	scheduled[player] = nil
end)

return CrouchService
