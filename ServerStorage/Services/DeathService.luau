local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local FriendReviveService = require(ServerStorage.Services.FriendReviveService)
local ReviveService = require(ServerStorage.Services.ReviveService)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local EnemyEncounterService = require(ServerStorage.Services.EnemyEncounterService)
local RoomService = require(ServerStorage.Services.RoomService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)

local Show = CommunicationService.Get("Death", "Show") :: RemoteEvent
local Kill = CommunicationService.Ensure("Death", "Kill") :: RemoteEvent
local Strike = CommunicationService.Ensure("Death", "Strike") :: RemoteEvent

local DeathService = {}

type Record = {
	CauseId: string,
	At: number,
}

local Records: { [Player]: Record } = {}
local Killers: { [Player]: Model } = {}
local LastHit: { [Player]: { [Model]: number } } = {}

local function damageOf(enemy: Model): number
	local enemyId = enemy:GetAttribute("EnemyId")
	local config = if type(enemyId) == "string" then EnemyConfigs[enemyId] else nil
	local damage = config and config.Damage
	return if type(damage) == "number" then damage else math.huge
end

Kill.OnServerEvent:Connect(function(player: Player, enemy: Instance?)
	if RoomService:IsInRoom(player) then return end
	if not enemy or not enemy:IsA("Model") or not enemy:IsDescendantOf(workspace) then return end
	if not enemy:HasTag("Enemy") and Killers[player] ~= enemy then return end
	if enemy:GetAttribute("Harmless") then return end
	if enemy:GetAttribute("EnemyId") == "Mimic" and enemy:GetAttribute("MimicAttackActive") ~= true then
		return
	end
	local causeId = enemy:GetAttribute("EnemyId")
	DeathService:Hit(player, enemy, damageOf(enemy), if type(causeId) == "string" then causeId else nil)
end)

function DeathService:Hit(player: Player, enemy: Model, damage: number, causeId: string?): boolean
	if not enemy:IsDescendantOf(workspace) then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	local hits = LastHit[player]
	if not hits then
		hits = setmetatable({}, { __mode = "k" }) :: any
		LastHit[player] = hits
	end
	local now = os.clock()
	if now - (hits[enemy] or -math.huge) < DeathConfig.HitCooldown then return false end
	hits[enemy] = now

	self:RecordCause(player, causeId or enemy:GetAttribute("EnemyId") :: string?)
	Killers[player] = enemy
	Strike:FireClient(player, enemy, damage)
	if damage >= humanoid.Health or damage == math.huge then
		humanoid.Health = 0
	else
		humanoid:TakeDamage(damage)
	end
	return true
end

function DeathService:RecordCause(player: Player, causeId: string?)
	if not causeId then return end

	local record = Records[player]
	if record and record.CauseId == causeId then
		record.At = os.clock()
		return
	end
	Records[player] = { CauseId = causeId, At = os.clock() }
end

function DeathService:Strike(player: Player, enemy: Model, causeId: string?)
	self:Hit(player, enemy, math.huge, causeId)
end

function DeathService:ClearCause(player: Player, causeId: string)
	local record = Records[player]
	if record and record.CauseId == causeId then
		Records[player] = nil
	end
end

function DeathService:GetCause(player: Player): string?
	local record = Records[player]
	if not record or os.clock() - record.At > DeathConfig.CauseMemory then return nil end
	return record.CauseId
end

local function watchCharacter(player: Player, character: Model)
	Records[player] = nil
	LastHit[player] = nil

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Once(function()
		local killer = Killers[player]
		Killers[player] = nil
		local cause = DeathService:GetCause(player)
		if not cause and killer then
			local killerId = killer:GetAttribute("EnemyId")
			if type(killerId) == "string" then
				cause = killerId
			end
		end
		Kill:FireAllClients(player, killer)
		local token = ReviveService:Offer(player, character)
		FriendReviveService:Offer(player)
		Show:FireClient(player, cause, token)

		EnemyDiscoveryService:GrantDeath(player, cause)
		EnemyEncounterService:ResolveDeath(player, killer, cause)
		AnalyticsService:LogEvent(player, "Death", nil, { Enemy = cause or DeathConfig.UnknownId })

		Records[player] = nil
		Killers[player] = nil
	end)
end

local function watchPlayer(player: Player)
	if player.Character then
		watchCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	Records[player] = nil
	Killers[player] = nil
end)

return DeathService
