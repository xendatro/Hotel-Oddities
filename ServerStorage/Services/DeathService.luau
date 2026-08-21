local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local FriendReviveService = require(ServerStorage.Services.FriendReviveService)
local ReviveService = require(ServerStorage.Services.ReviveService)
local RoomService = require(ServerStorage.Services.RoomService)

local Show = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Death")
	:WaitForChild("Show") :: RemoteEvent
local Complete = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Death")
	:WaitForChild("Complete") :: RemoteEvent
local existingKill = ReplicatedStorage.Communication.Death:FindFirstChild("Kill")
local Kill: RemoteEvent
if existingKill and existingKill:IsA("RemoteEvent") then
	Kill = existingKill
else
	Kill = Instance.new("RemoteEvent")
	Kill.Name = "Kill"
	Kill.Parent = ReplicatedStorage.Communication.Death
end

local existingStrike = ReplicatedStorage.Communication.Death:FindFirstChild("Strike")
local Strike: RemoteEvent
if existingStrike and existingStrike:IsA("RemoteEvent") then
	Strike = existingStrike
else
	Strike = Instance.new("RemoteEvent")
	Strike.Name = "Strike"
	Strike.Parent = ReplicatedStorage.Communication.Death
end

local DeathService = {}

type Record = {
	CauseId: string,
	At: number,
}

local Records: { [Player]: Record } = {}
local Killers: { [Player]: Model } = {}

Kill.OnServerEvent:Connect(function(player: Player, enemy: Instance?)
	if RoomService:IsInRoom(player) then return end
	if not enemy or not enemy:IsA("Model") or not enemy:IsDescendantOf(workspace) then return end
	if not enemy:HasTag("Enemy") then return end
	if enemy:GetAttribute("Harmless") then return end
	if enemy:GetAttribute("EnemyId") == "Mimic" and enemy:GetAttribute("MimicAttackActive") ~= true then
		return
	end
	Killers[player] = enemy
	local causeId = enemy:GetAttribute("EnemyId")
	if type(causeId) == "string" then
		DeathService:RecordCause(player, causeId)
	end
end)

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
	if not enemy:IsDescendantOf(workspace) then return end

	self:RecordCause(player, causeId or enemy:GetAttribute("EnemyId") :: string?)
	Killers[player] = enemy
	Strike:FireClient(player, enemy)
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

		Records[player] = nil
		Killers[player] = nil
	end)
end

Complete.OnServerEvent:Connect(function(player: Player, token: any)
	if type(token) ~= "number" then return end
end)

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
