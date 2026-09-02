local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local HolePlacementService = require(ReplicatedStorage.Services.HolePlacementService)
local TagService = require(ReplicatedStorage.Services.TagService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local Other = ReplicatedStorage.Props.Other

local HOLE_TAG = "Hole"
local CREATOR_ATTRIBUTE = "CreatorUserId"
local HOLE_LIFETIME = 30
local MAX_HOLE_PAIRS = 5
local HOP_DISTANCE = 12
local HOP_COOLDOWN = 5

local HoleService = {}

type HolePair = {
	Models: { Model },
	Owner: Player?,
}

local Pairs: { HolePair } = {}
local ImmunityRecords: { [Player]: { Character: Model, EndsAt: number } } = {}
local LastHopAt: { [Player]: number } = {}

local function destroyPair(pair: HolePair)
	for _, hole in pair.Models do
		hole:Destroy()
	end
end

local function removePair(pair: HolePair)
	local index = table.find(Pairs, pair)
	if index then table.remove(Pairs, index) end
	destroyPair(pair)
end

function HoleService:CreateHolePair(entryPosition: Vector3, owner: Player?): boolean
	local template = Other:FindFirstChild("Hole")
	if not template then
		warn("HoleService: no Hole model in ReplicatedStorage.Props.Other")
		return false
	end

	local floors = HolePlacementService.GetFloors(workspace)
	if not HolePlacementService.IsFootprintSupported(entryPosition, template, floors) then
		return false
	end

	local exitPosition = HolePlacementService.FindRandomPosition(template, floors)
	if not exitPosition then
		warn("HoleService: no tagged floor has room for a hole")
		return false
	end

	local id = HttpService:GenerateGUID()
	local x, y, z = template:GetPivot():ToOrientation()
	local orientation = CFrame.fromOrientation(x, y, z)

	local entry = template:Clone()
	local exit = template:Clone()

	entry:SetAttribute("ID", id)
	exit:SetAttribute("ID", id)
	entry:SetAttribute(CREATOR_ATTRIBUTE, if owner then owner.UserId else nil)
	exit:SetAttribute(CREATOR_ATTRIBUTE, if owner then owner.UserId else nil)
	entry:PivotTo(CFrame.new(entryPosition) * orientation)
	exit:PivotTo(CFrame.new(exitPosition) * orientation)
	entry.Parent = workspace
	exit.Parent = workspace

	local pair: HolePair = {
		Models = { entry, exit },
		Owner = owner,
	}
	table.insert(Pairs, pair)
	task.delay(HOLE_LIFETIME, function()
		removePair(pair)
	end)

	while #Pairs > MAX_HOLE_PAIRS do
		local oldest = table.remove(Pairs, 1)
		if oldest then
			destroyPair(oldest)
		end
	end

	return true
end

function HoleService:RemoveForPlayer(player: Player)
	for index = #Pairs, 1, -1 do
		local pair = Pairs[index]
		if pair.Owner == player or (pair.Owner and pair.Owner.UserId == player.UserId) then
			table.remove(Pairs, index)
			destroyPair(pair)
		end
	end

	for _, hole in TagService:GetTaggedOfAncestor(workspace, HOLE_TAG) do
		if hole:GetAttribute(CREATOR_ATTRIBUTE) == player.UserId then
			hole:Destroy()
		end
	end
end

local Create = CommunicationService.Get("Hole", "Create") :: RemoteFunction
local Immunity = CommunicationService.Ensure("Hole", "Immunity") :: RemoteEvent

local function isActivePairHole(hole: Model): boolean
	for _, pair in Pairs do
		for _, member in pair.Models do
			if member == hole then
				return true
			end
		end
	end
	return false
end

local function clearImmunity(player: Player, character: Model)
	local record = ImmunityRecords[player]
	if not record or record.Character ~= character then return end

	ImmunityRecords[player] = nil
	Vanished.SetSource(character, Vanished.HoleTag, false)
	character:SetAttribute(Vanished.HoleEndsAtAttribute, nil)
end

Immunity.OnServerEvent:Connect(function(player: Player, hole: any)
	if not hole or not hole:IsA("Model") or not hole:IsDescendantOf(workspace) or not hole:HasTag(HOLE_TAG) then
		return
	end
	if not isActivePairHole(hole) then return end

	local root = CharacterService.GetAliveRoot(player)
	if not root or (root.Position - hole:GetPivot().Position).Magnitude > HOP_DISTANCE then return end

	local now = workspace:GetServerTimeNow()
	if (LastHopAt[player] or -math.huge) + HOP_COOLDOWN > now then return end
	LastHopAt[player] = now

	local character = root.Parent :: Model
	local previous = ImmunityRecords[player]
	if previous and previous.Character ~= character then
		clearImmunity(player, previous.Character)
	end

	local endsAt = now + ToolConfigs.Shovel.HoleImmunityDuration
	local record = { Character = character, EndsAt = endsAt }
	ImmunityRecords[player] = record
	character:SetAttribute(Vanished.HoleEndsAtAttribute, endsAt)
	Vanished.SetSource(character, Vanished.HoleTag, true)

	task.delay(ToolConfigs.Shovel.HoleImmunityDuration, function()
		if ImmunityRecords[player] ~= record then return end
		clearImmunity(player, character)
	end)
end)

local function watchPlayer(player: Player)
	player.CharacterRemoving:Connect(function(character: Model)
		clearImmunity(player, character)
	end)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	ImmunityRecords[player] = nil
	LastHopAt[player] = nil
end)

Create.OnServerInvoke = function(player: Player, entryPosition: any)
	if typeof(entryPosition) ~= "Vector3" then return false end

	local root = CharacterService.GetAliveRoot(player)
	if not root then return false end
	if (root.Position - entryPosition).Magnitude > ToolConfigs.Shovel.MaxDigDistance then return false end

	local floors = HolePlacementService.GetFloors(workspace)
	local ground = HolePlacementService.FindGround(root.Position, ToolConfigs.Shovel.DigDepth, floors)
	if not ground then return false end

	return HoleService:CreateHolePair(ground.Position + Vector3.new(0, 0.5, 0), player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	HoleService:RemoveForPlayer(player)
end)

return HoleService
