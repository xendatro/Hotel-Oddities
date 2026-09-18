local Players = game:GetService("Players")

local ChatCommandService = {}

ChatCommandService.GroupId = if game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 0
ChatCommandService.AllowedRoles = {
	owner = true,
	developer = true,
}

local Roles: { [Player]: string } = {}

type Options = {
	Aliases: { string }?,
	Handler: (player: Player, argument: string?) -> (),
}

type Entry = { Name: string, Handler: (player: Player, argument: string?) -> () }

local Commands: { [string]: { Entry } } = {}

local function resolveRole(player: Player): string
	local cached = Roles[player]
	if cached then return cached end

	local role = ""
	if ChatCommandService.GroupId > 0 then
		local ok, result = pcall(player.GetRoleInGroup, player, ChatCommandService.GroupId)
		if ok and type(result) == "string" then role = result end
	end
	if player.Parent == Players then Roles[player] = role end
	return role
end

function ChatCommandService.GetRole(player: Player): string
	return resolveRole(player)
end

function ChatCommandService.IsAllowed(player: Player): boolean
	return ChatCommandService.AllowedRoles[resolveRole(player):lower()] == true
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

	if not ChatCommandService.IsAllowed(player) then
		warn(`[{name}] {player.Name} ({player.UserId}) is not allowed to use chat commands`)
		return
	end

	for _, entry in entries do
		entry.Handler(player, if argument ~= "" then argument else nil)
	end
end

local function watch(player: Player)
	task.spawn(function()
		player:SetAttribute("Admin", ChatCommandService.IsAllowed(player))
	end)
	player.Chatted:Connect(function(message: string)
		onChatted(player, message)
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	Roles[player] = nil
end)

return ChatCommandService
