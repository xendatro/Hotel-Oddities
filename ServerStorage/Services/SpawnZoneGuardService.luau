local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local SpawnZoneConfig = require(ReplicatedStorage.Configs.SpawnZoneConfig)
local SpawnZoneService = require(ReplicatedStorage.Services.SpawnZoneService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)
local NPC = require(ServerStorage.Classes.NPC)

local SpawnZoneGuardService = {}

local Shielded: { [Model]: boolean } = {}
local RepelAt = setmetatable({} :: { [Model]: number }, { __mode = "k" })
local Bound = setmetatable({} :: { [BasePart]: boolean }, { __mode = "k" })

local function npcFromPart(part: BasePart): any?
	local ancestor: Instance? = part.Parent
	while ancestor and ancestor ~= workspace do
		local npc = NPC.FromModel(ancestor)
		if npc then
			return npc
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function repel(npc: any)
	local machine = npc.StateMachine
	if not machine or machine.State == "Stunned" then
		return
	end

	local now = os.clock()
	if (RepelAt[npc.Model] or 0) > now then
		return
	end
	RepelAt[npc.Model] = now + SpawnZoneConfig.RepelCooldown

	npc:GiveUpOn(npc.Target)
	if machine.States.Patrol then
		machine:SetState("Patrol", "root", npc)
	elseif machine.States.Idle then
		machine:SetState("Idle", "root", npc)
	end
end

local function buildBorder(zone: BasePart)
	local settings = SpawnZoneConfig.Border
	local thickness = settings.Thickness
	local half = zone.Size / 2

	local faces = {
		{ Offset = Vector3.new(0, 0, half.Z + thickness / 2), Size = Vector3.new(zone.Size.X + thickness * 2, zone.Size.Y, thickness) },
		{ Offset = Vector3.new(0, 0, -(half.Z + thickness / 2)), Size = Vector3.new(zone.Size.X + thickness * 2, zone.Size.Y, thickness) },
		{ Offset = Vector3.new(half.X + thickness / 2, 0, 0), Size = Vector3.new(thickness, zone.Size.Y, zone.Size.Z) },
		{ Offset = Vector3.new(-(half.X + thickness / 2), 0, 0), Size = Vector3.new(thickness, zone.Size.Y, zone.Size.Z) },
	}

	for _, face in faces do
		local wall = Instance.new("Part")
		wall.Name = "SpawnZoneBorder"
		wall.Size = face.Size
		wall.CFrame = zone.CFrame * CFrame.new(face.Offset)
		wall.Anchored = true
		wall.CanCollide = false
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Material = Enum.Material.SmoothPlastic
		wall.Transparency = settings.Transparency
		wall.Color = settings.Color
		wall.Parent = zone
	end

	zone.Transparency = 1
end

local function bindZone(zone: Instance)
	if not zone:IsA("BasePart") or Bound[zone] then
		return
	end
	Bound[zone] = true
	buildBorder(zone)
	zone.Touched:Connect(function(hit: BasePart)
		local npc = npcFromPart(hit)
		if npc and npc.Active then
			repel(npc)
		end
	end)
end

local function updatePlayer(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local inside = root ~= nil
		and root:IsA("BasePart")
		and SpawnZoneService:Contains(root.Position)

	if inside then
		if not Shielded[character] and not character:HasTag(Vanished.Tag) then
			Shielded[character] = true
			character:AddTag(Vanished.Tag)
		end
	elseif Shielded[character] then
		Shielded[character] = nil
		character:RemoveTag(Vanished.Tag)
	end
end

for _, zone in CollectionService:GetTagged(SpawnZoneConfig.Tag) do
	bindZone(zone)
end
CollectionService:GetInstanceAddedSignal(SpawnZoneConfig.Tag):Connect(bindZone)

CharacterService.ForEachPlayer(function(player: Player)
	player.CharacterRemoving:Connect(function(character: Model)
		Shielded[character] = nil
	end)
end)

task.spawn(function()
	while true do
		task.wait(SpawnZoneConfig.PlayerPollInterval)
		for _, player in Players:GetPlayers() do
			updatePlayer(player)
		end
	end
end)

return SpawnZoneGuardService
