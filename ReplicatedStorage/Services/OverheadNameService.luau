local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local OverheadName = require(ReplicatedStorage.Classes.OverheadName)
local OverheadNameConfig = require(ReplicatedStorage.Configs.OverheadNameConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local OverheadNameService = {}

function OverheadNameService:GetName(player: Player): string
	return OverheadName.Format(player)
end

if not RunService:IsClient() then
	return OverheadNameService
end

local localPlayer = Players.LocalPlayer
local playerGui = GuiBuilderService.GetPlayerGui()

local Names: { [Model]: any } = {}
local Watchers: { [Model]: RBXScriptConnection } = {}
local host: Folder? = nil

local rebuildAll

local function getHost(): Folder
	local existing = host
	if existing and existing.Parent then return existing end

	local folder = Instance.new("Folder")
	folder.Name = "OverheadNames"
	folder.Parent = playerGui
	host = folder

	folder.AncestryChanged:Connect(function()
		if folder.Parent ~= nil or host ~= folder then return end
		task.defer(rebuildAll)
	end)

	return folder
end

local function drop(model: Model)
	local name = Names[model]
	if not name then return end
	Names[model] = nil
	name:Destroy()
end

local function attach(model: Model, player: Player?)
	local current = Names[model]
	if current and current.Player == player and current.Billboard.Parent then return end
	drop(model)
	if not player or not player.Parent then return end
	Names[model] = OverheadName.new(model, player, getHost())
end

local function identityOf(model: Model): Player?
	local userId = model:GetAttribute(OverheadNameConfig.UserIdAttribute)
	if typeof(userId) ~= "number" then return nil end
	return Players:GetPlayerByUserId(userId)
end

local function trackTagged(instance: Instance)
	if not instance:IsA("Model") or Watchers[instance] then return end
	local model = instance :: Model

	Watchers[model] = model:GetAttributeChangedSignal(OverheadNameConfig.UserIdAttribute):Connect(function()
		attach(model, identityOf(model))
	end)
	attach(model, identityOf(model))
end

local function untrackTagged(instance: Instance)
	local model = instance :: Model
	local watcher = Watchers[model]
	if watcher then
		watcher:Disconnect()
		Watchers[model] = nil
	end
	drop(model)
end

local function trackCharacter(player: Player, character: Model)
	if player == localPlayer then return end
	attach(character, player)
end

local function trackPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		trackCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(drop)
	if player.Character then
		trackCharacter(player, player.Character)
	end
end

function rebuildAll()
	for model, name in Names do
		name:Destroy()
		Names[model] = nil
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			trackCharacter(player, player.Character)
		end
	end
	for model in Watchers do
		attach(model, identityOf(model))
	end
end

Players.PlayerAdded:Connect(function(player)
	trackPlayer(player)
	for model in Watchers do
		attach(model, identityOf(model))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for model, name in Names do
		if name.Player == player then
			drop(model)
		end
	end
end)

for _, player in Players:GetPlayers() do
	trackPlayer(player)
end

CollectionService:GetInstanceAddedSignal(OverheadNameConfig.Tag):Connect(trackTagged)
CollectionService:GetInstanceRemovedSignal(OverheadNameConfig.Tag):Connect(untrackTagged)
for _, instance in CollectionService:GetTagged(OverheadNameConfig.Tag) do
	trackTagged(instance)
end

return OverheadNameService
