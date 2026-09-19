local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local ComputerChipConfig = require(ReplicatedStorage.Configs.ComputerChipConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local ComputerService = {}

local TAG = ComputerConfig.Tag
local ID_ATTRIBUTE = ComputerConfig.IdAttribute
local REACH = ComputerConfig.Targeting.ServerReach
local MIN_INTERVAL = 0.5
local SYNC_REQUEST_INTERVAL = 1

local LEGACY_ATTRIBUTE = "Hacked"

local Complete = CommunicationService.Ensure(ComputerConfig.Remotes.Folder, ComputerConfig.Remotes.Complete) :: RemoteEvent
local Sync = CommunicationService.Ensure(ComputerConfig.Remotes.Folder, ComputerConfig.Remotes.Sync) :: RemoteEvent

local Hacked: { [Player]: { [Model]: true } } = {}
local SavedIds: { [Player]: { [string]: true } } = {}
local Ready: { [Player]: boolean } = {}
local ResetPending: { [Player]: boolean } = {}
local LastComplete: { [Player]: number } = {}
local LastSyncRequest: { [Player]: number } = {}

local function setOf(player: Player): { [Model]: true }
	local set = Hacked[player]
	if not set then
		set = {}
		Hacked[player] = set
	end
	return set
end

local function idOf(model: Model): string?
	local id = model:GetAttribute(ID_ATTRIBUTE)
	return if type(id) == "string" then id else nil
end

local function generatedId(model: Model): string
	local path = model:GetFullName():gsub("[^%w_]", "_")
	return `Computer_{path}`
end

local function restoreModel(model: Model)
	local id = idOf(model)
	if not id then return end

	for player, saved in SavedIds do
		if Ready[player] and saved[id] then
			setOf(player)[model] = true
		end
	end
end

local sync: (Player) -> ()

local function readSaved(player: Player, profile: any)
	local stored = profile.Data.HackedComputers
	local saved: { [string]: true } = {}
	if type(stored) == "table" then
		for key, value in pairs(stored) do
			if type(key) == "string" and value == true then
				saved[key] = true
			elseif type(value) == "string" then
				saved[value] = true
			end
		end
	end
	if ResetPending[player] then
		table.clear(saved)
		ResetPending[player] = nil
	end
	profile.Data.HackedComputers = saved
	SavedIds[player] = saved
	Ready[player] = true
end

local function loadPlayer(player: Player)
	local profile = DataSaveService:Wait(player)
	if not profile or not player:IsDescendantOf(Players) then return end

	readSaved(player, profile)
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
			restoreModel(instance)
		end
	end
	sync(player)
end

local function totalComputers(): number
	local total = 0
	for _, model in CollectionService:GetTagged(TAG) do
		if model:IsDescendantOf(workspace) then
			total += 1
		end
	end
	return total
end

local function completedColors(player: Player): ({ [string]: boolean }, boolean)
	local colors: { [string]: boolean } = {}
	local allComplete = #ComputerChipConfig.Colors == 5
	local maze = workspace:FindFirstChild(ComputerChipConfig.MazeName)
	local rooms = maze and maze:FindFirstChild("Rooms")
	local hacked = setOf(player)
	for _, entry in ComputerChipConfig.Colors do
		local room = rooms and rooms:FindFirstChild(entry.RoomName)
		local model = room and room:FindFirstChild(ComputerConfig.ModelName)
		local complete = model ~= nil and model:IsA("Model") and CollectionService:HasTag(model, TAG) and hacked[model] == true
		colors[entry.Key] = complete
		allComplete = allComplete and complete
	end
	return colors, allComplete
end

sync = function(player: Player)
	local ids: { string } = {}
	for model in pairs(setOf(player)) do
		if model:IsDescendantOf(workspace) then
			local id = model:GetAttribute(ID_ATTRIBUTE)
			if type(id) == "string" then
				table.insert(ids, id)
			end
		end
	end
	local colors, unlocked = completedColors(player)
	Sync:FireClient(player, { Hacked = ids, Total = totalComputers(), Colors = colors, ExitUnlocked = unlocked })
end

local function syncAll()
	for _, player in Players:GetPlayers() do
		sync(player)
	end
end

local function eligible(instance: Instance): boolean
	return instance:IsA("Model")
		and instance.Name == ComputerConfig.ModelName
		and instance.Parent ~= nil
		and instance.Parent ~= workspace
end

local function register(instance: Instance)
	if not eligible(instance) then return end
	local model = instance :: Model

	if not idOf(model) then
		model:SetAttribute(ID_ATTRIBUTE, generatedId(model))
	end
	if not CollectionService:HasTag(model, TAG) then
		CollectionService:AddTag(model, TAG)
	end
	restoreModel(model)
	if model:GetAttribute(LEGACY_ATTRIBUTE) ~= nil then
		model:SetAttribute(LEGACY_ATTRIBUTE, nil)
	end
end

function ComputerService:IsHacked(player: Player, model: Model): boolean
	local set = Hacked[player]
	return set ~= nil and set[model] == true
end

function ComputerService:IsExitUnlocked(player: Player): boolean
	local _, unlocked = completedColors(player)
	return unlocked
end

function ComputerService:GetProgress(player: Player): (number, number)
	local set = Hacked[player]
	local hacked, total = 0, 0
	for _, model in CollectionService:GetTagged(TAG) do
		if model:IsDescendantOf(workspace) then
			total += 1
			if set and set[model :: Model] then
				hacked += 1
			end
		end
	end
	return hacked, total
end

function ComputerService:SetHacked(player: Player, model: Model, hacked: boolean)
	if not Ready[player] then return end
	local id = idOf(model)
	if not id then return end

	local set = setOf(player)
	local was = set[model] == true
	if was == hacked then return end

	set[model] = if hacked then true else nil
	local saved = SavedIds[player]
	if saved then
		saved[id] = if hacked then true else nil
	end
	sync(player)

	if not hacked then return end
	local colors = completedColors(player)
	local count = 0
	for _, complete in colors do
		if complete then count += 1 end
	end
	if count > 0 then
		AnalyticsService:LogStep(player, `Computers{count}`)
	end
	AnalyticsService:LogEvent(player, "ComputerHacked", (self:GetProgress(player)), { Computer = id })
end

function ComputerService:ResetProgress(player: Player)
	Hacked[player] = nil
	LastComplete[player] = nil
	local saved = SavedIds[player]
	if saved then
		table.clear(saved)
	else
		local profile = DataSaveService:Get(player)
		if profile then
			profile.Data.HackedComputers = {}
		else
			ResetPending[player] = true
		end
	end
	sync(player)
end

Complete.OnServerEvent:Connect(function(player: Player, model: any)
	if not Ready[player] then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if not model:IsDescendantOf(workspace) or not CollectionService:HasTag(model, TAG) then return end
	if ComputerService:IsHacked(player, model) then return end

	local now = os.clock()
	if now - (LastComplete[player] or 0) < MIN_INTERVAL then return end

	local position = CharacterService.GetPosition(player)
	if not position or (model:GetPivot().Position - position).Magnitude > REACH then return end

	LastComplete[player] = now
	ComputerService:SetHacked(player, model, true)
end)

Sync.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if now - (LastSyncRequest[player] or 0) < SYNC_REQUEST_INTERVAL then return end
	LastSyncRequest[player] = now
	sync(player)
end)

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance: Instance)
	if instance:IsA("Model") then restoreModel(instance) end
	syncAll()
end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
	local id = if instance:IsA("Model") then idOf(instance) else nil
	for _, set in Hacked do
		set[instance :: Model] = nil
	end
	if id then
		for _, saved in SavedIds do
			saved[id] = nil
		end
	end
	syncAll()
end)

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(loadPlayer, player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	Hacked[player] = nil
	SavedIds[player] = nil
	Ready[player] = nil
	ResetPending[player] = nil
	LastComplete[player] = nil
	LastSyncRequest[player] = nil
end)

for _, descendant in workspace:GetDescendants() do
	register(descendant)
end

workspace.DescendantAdded:Connect(register)

for _, player in Players:GetPlayers() do
	task.spawn(loadPlayer, player)
end

return ComputerService
