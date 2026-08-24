local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vanished = require(ReplicatedStorage.Modules.Vanished)

local ALLOWED_USER_IDS = {
	[265199502] = true,
	[1936118388] = true,
}

local ON_WORDS = { on = true, yes = true, ["true"] = true, enable = true, enabled = true }
local OFF_WORDS = { off = true, no = true, ["false"] = true, disable = true, disabled = true }

local InvincibleCommandService = {}

local Enabled: { [Player]: boolean } = {}

local function apply(player: Player)
	local character = player.Character
	if not character then return end
	if Enabled[player] then
		character:AddTag(Vanished.Tag)
	else
		character:RemoveTag(Vanished.Tag)
	end
end

function InvincibleCommandService:Set(player: Player, enabled: boolean)
	Enabled[player] = if enabled then true else nil
	apply(player)
	warn(`[invincible] {player.Name} is now {if enabled then "invincible and ignored by all entities" else "mortal"}`)
end

function InvincibleCommandService:Is(player: Player): boolean
	return Enabled[player] == true
end

local function execute(player: Player, command: string, argument: string?)
	if not RunService:IsStudio() and not ALLOWED_USER_IDS[player.UserId] then
		warn(`[invincible] {player.Name} ({player.UserId}) is not allowed to use /{command}`)
		return
	end

	if command == "mortal" then
		InvincibleCommandService:Set(player, false)
		return
	end

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
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		local command, argument = message:match("^/(%S+)%s*(.*)$")
		command = command and command:lower()
		if command == "invincible" or command == "mortal" then
			execute(player, command, if argument ~= "" then argument else nil)
		end
	end)
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
