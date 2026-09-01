local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ChatCommandService = {}

ChatCommandService.AdminUserIds = {
	[265199502] = true,
	[1936118388] = true,
	[512253031] = true,
	[91928215] = true
}

type Options = {
	Aliases: { string }?,
	AdminOnly: boolean?,
	Handler: (player: Player, argument: string?) -> (),
}

type Entry = { Name: string, AdminOnly: boolean, Handler: (player: Player, argument: string?) -> () }

local Commands: { [string]: { Entry } } = {}

function ChatCommandService.IsAllowed(player: Player): boolean
	return RunService:IsStudio() or ChatCommandService.AdminUserIds[player.UserId] == true
end

function ChatCommandService.FindPlayer(name: string): Player?
	local lowered = name:lower()
	local userId = tonumber(name)
	for _, player in Players:GetPlayers() do
		if player.Name:lower() == lowered
			or player.DisplayName:lower() == lowered
			or (userId and player.UserId == userId)
		then
			return player
		end
	end
	return nil
end

function ChatCommandService.Register(name: string, options: Options)
	local entry: Entry = {
		Name = name:lower(),
		AdminOnly = options.AdminOnly == true,
		Handler = options.Handler,
	}
	local names = { entry.Name }
	for _, alias in options.Aliases or {} do
		table.insert(names, alias:lower())
	end
	for _, key in names do
		local entries = Commands[key]
		if not entries then
			entries = {}
			Commands[key] = entries
		end
		table.insert(entries, entry)
	end
end

local function onChatted(player: Player, message: string)
	local name, argument = message:match("^/(%S+)%s*(.*)$")
	local entries = name and Commands[name:lower()]
	if not entries then return end

	for _, entry in entries do
		if entry.AdminOnly and not ChatCommandService.IsAllowed(player) then
			warn(`[{entry.Name}] {player.Name} ({player.UserId}) is not allowed to use /{entry.Name}`)
			continue
		end
		entry.Handler(player, if argument ~= "" then argument else nil)
	end
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		onChatted(player, message)
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return ChatCommandService
