--- Owns what a player is told when they die. Everything that can kill somebody records the enemy id
--- behind it here; this watches every character's Humanoid and, when one dies, sends the last id
--- recorded for that player to their own client, which resolves the name and the hint out of
--- `DeathConfig`.
---
--- A record rather than a kill callback, because the killing blow and the death are not the same
--- event: an enemy sets `Health = 0` and `Humanoid.Died` follows on its own. Recording also survives
--- damage that only nearly kills -- `Eye` bills by the second -- which is what `CauseMemory` is for.
--- Past that window a record stops being credible and the death reads as the hotel's own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local ReviveService = require(ServerStorage.Services.ReviveService)

local Show = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Death")
	:WaitForChild("Show") :: RemoteEvent

local DeathService = {}

type Record = {
	CauseId: string,
	At: number,
}

local Records: { [Player]: Record } = {}

--- Names `causeId` as the thing that just hurt `player`. Called on every damaging hit rather than
--- only on fatal ones, so a chip-damage enemy still gets the credit when its last tick lands.
function DeathService:RecordCause(player: Player, causeId: string?)
	if not causeId then return end

	-- Refreshed in place where the cause has not changed: `Eye` bills its watchers twenty times a
	-- second, and none of that should be a fresh table.
	local record = Records[player]
	if record and record.CauseId == causeId then
		record.At = os.clock()
		return
	end
	Records[player] = { CauseId = causeId, At = os.clock() }
end

--- The enemy id to blame for a death happening now, or nil where nothing recent claimed it.
function DeathService:GetCause(player: Player): string?
	local record = Records[player]
	if not record or os.clock() - record.At > DeathConfig.CauseMemory then return nil end
	return record.CauseId
end

local function watchCharacter(player: Player, character: Model)
	Records[player] = nil

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Once(function()
		local cause = DeathService:GetCause(player)
		ReviveService:Offer(player, character)
		Show:FireClient(player, cause)

		-- Dying to something teaches you more about it than any amount of looking, and it is the only
		-- way to learn anything at all about the two that ambush you. Granted from here rather than
		-- from whatever landed the blow because this is where a death is already attributed, and the
		-- attribution is the hard part -- see `GetCause` for why it is a memory rather than a callback.
		-- Nothing happens for a death nothing claimed: falling down a lift shaft is the hotel's own.
		EnemyDiscoveryService:GrantDeath(player, cause)

		Records[player] = nil
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
end)

return DeathService
