local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Vanished = require(ReplicatedStorage.Services.VanishedService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local ON_WORDS = { on = true, yes = true, ["true"] = true, enable = true, enabled = true }
local OFF_WORDS = { off = true, no = true, ["false"] = true, disable = true, disabled = true }

local InvincibleCommandService = {}

local Enabled: { [Player]: boolean } = {}

local function apply(player: Player)
	local character = player.Character
	if not character then return end
	Vanished.SetSource(character, Vanished.InfiniteTag, Enabled[player] == true)
end

function InvincibleCommandService:Set(player: Player, enabled: boolean)
	Enabled[player] = if enabled then true else nil
	apply(player)
	warn(`[invincible] {player.Name} is now {if enabled then "invincible and ignored by all entities" else "mortal"}`)
end

function InvincibleCommandService:Is(player: Player): boolean
	return Enabled[player] == true
end

ChatCommandService.Register("invincible", {
	AdminOnly = true,
	Handler = function(player: Player, argument: string?)
		local word = argument and argument:lower()
		if word and ON_WORDS[word] then
			InvincibleCommandService:Set(player, true)
		elseif word and OFF_WORDS[word] then
			InvincibleCommandService:Set(player, false)
		elseif word then
			warn(`[invincible] usage: /invincible [on|off] or /mortal`)
		else
			InvincibleCommandService:Set(player, not Enabled[player])
		end
	end,
})

ChatCommandService.Register("mortal", {
	AdminOnly = true,
	Handler = function(player: Player)
		InvincibleCommandService:Set(player, false)
	end,
})

local function watch(player: Player)
	player.CharacterAdded:Connect(function()
		apply(player)
	end)
end

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player: Player)
	Enabled[player] = nil
end)
for _, player in Players:GetPlayers() do
	watch(player)
end

return InvincibleCommandService
