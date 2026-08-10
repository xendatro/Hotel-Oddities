--- Selling a friend's way back. When somebody dies, every Roblox friend of theirs in the server is
--- shown a card for `Window` seconds; pressing revive on it opens the `ReviveFriend` product prompt,
--- and the receipt spends the dead player's pending death through `ReviveService`.
---
--- The card's countdown and this side's offer window are the same number out of `PerkConfig`, but
--- they are not the same clock and are not meant to be: the card decides when to stop asking, and
--- this decides when an answer stops being accepted. A purchase that has already been PROMPTED
--- outlives both by `PurchaseGrace`, because a Robux prompt is slow and taking somebody's money for
--- an offer that expired while they were reading it is the one outcome worth engineering against.
---
--- Nothing here does anything until `MarketplaceService.Products.ReviveFriend` has a real id.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local ReviveService = require(ServerStorage.Services.ReviveService)

local Communication = ReplicatedStorage.Communication.Revive
local Offer = Communication.Offer :: RemoteEvent
local Withdraw = Communication.Withdraw :: RemoteEvent
local Request = Communication.Request :: RemoteEvent

local CONFIG = PerkConfig.FriendRevive
local PRODUCT_ID = MarketplaceService.Products.ReviveFriend
local ENABLED = type(PRODUCT_ID) == "number" and PRODUCT_ID > 0

type Claim = {
	Target: Player,
	ExpiresAt: number,
}

local FriendReviveService = {}

-- [dead player] = os.clock() the offer stops being answerable at.
local Offers: { [Player]: number } = {}
-- [buyer] = the revive their open purchase prompt is for.
local Claims: { [Player]: Claim } = {}
-- ["a:b" userId pair] = whether they are friends. A friendship does not change mid-session often
-- enough to be worth a web call per death.
local Friendships: { [string]: boolean } = {}

local function areFriends(player: Player, other: Player): boolean
	local key = `{player.UserId}:{other.UserId}`
	local cached = Friendships[key]
	if cached ~= nil then return cached end

	local success, result = pcall(player.IsFriendsWith, player, other.UserId)
	local friends = success and result == true
	Friendships[key] = friends
	-- Friendship is symmetric and each direction costs its own web call otherwise.
	Friendships[`{other.UserId}:{player.UserId}`] = friends
	return friends
end

local function close(target: Player)
	if Offers[target] == nil then return end
	Offers[target] = nil
	Withdraw:FireAllClients(target)
end

--- Puts `target`'s death in front of every friend of theirs who is here to see it. Called from
--- `DeathService`, which is where a death is already being reported.
function FriendReviveService:Offer(target: Player)
	if not ENABLED then return end

	local expiresAt = os.clock() + CONFIG.Window
	Offers[target] = expiresAt

	-- The cards run their own countdown and close themselves; this is only so a death nobody bought
	-- stops being an entry in `Offers`. Guarded on the expiry it was scheduled for, so a second death
	-- inside the window is not closed by the first one's timer.
	task.delay(CONFIG.Window, function()
		if Offers[target] == expiresAt then
			Offers[target] = nil
		end
	end)

	for _, candidate in Players:GetPlayers() do
		if candidate == target then continue end

		-- One thread each: the friendship lookup yields on its first answer for a pair, and a player
		-- with a slow lookup should not hold up the cards of everyone after them in the list.
		task.spawn(function()
			if not areFriends(candidate, target) then return end
			if Offers[target] == nil then return end -- withdrawn while we were asking
			Offer:FireClient(candidate, target, CONFIG.Window)
		end)
	end
end

--- Wiring -----------------------------------------------------------------------------------------

Request.OnServerEvent:Connect(function(player: Player, target: any)
	if not ENABLED then return end
	if typeof(target) ~= "Instance" or not target:IsA("Player") then return end
	if target == player or target.Parent ~= Players then return end

	local expiresAt = Offers[target]
	if not expiresAt or os.clock() > expiresAt then return end
	if not ReviveService:HasPendingDeath(target) then return end
	if not areFriends(player, target) then return end

	-- Overwrites rather than stacks. A player can only have one Robux prompt open at a time, so a
	-- second request means they dismissed the first and the old claim is dead either way.
	Claims[player] = {
		Target = target,
		ExpiresAt = os.clock() + CONFIG.PurchaseGrace,
	}

	MarketplaceService:PromptProductPurchase(player, PRODUCT_ID)
end)

if ENABLED then
	MarketplaceService:CreateReceipt(PRODUCT_ID, function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local claim = Claims[player]
		Claims[player] = nil

		-- Granted anyway where the revive can no longer happen -- the friend left, or this receipt
		-- followed the buyer across a rejoin and the claim went with the old server. Refusing would
		-- re-fire this on every join they ever make and revive somebody at random years later.
		if not claim or os.clock() > claim.ExpiresAt or claim.Target.Parent ~= Players then
			warn(`FriendReviveService: {player.Name} paid for a revive that can no longer be delivered`)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		close(claim.Target)
		ReviveService:Grant(claim.Target)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end)
end

Players.PlayerRemoving:Connect(function(player: Player)
	close(player)
	Claims[player] = nil

	for buyer, claim in Claims do
		if claim.Target == player then
			Claims[buyer] = nil
		end
	end
end)

return FriendReviveService
