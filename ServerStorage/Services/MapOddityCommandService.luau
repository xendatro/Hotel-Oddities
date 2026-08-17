local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local MapOddityService = require(ServerStorage.Services.MapOddityService)

local MapOddityCommandService = {}

-- `/mapoddity` affects the complete hallway containing the caller; `clear` ends all active effects.

local EFFECTS = {
	transparency = "Transparency",
	translucent = "Transparency",
	door = "DoorsOpen",
	doors = "DoorsOpen",
	doorsopen = "DoorsOpen",
	open = "DoorsOpen",
}

local function run(player: Player, argument: string?)
	local command = argument and argument:lower()
	if command == "clear" or command == "stop" or command == "off" then
		if MapOddityService:Clear() then
			warn(`[map oddity] cleared by {player.Name}`)
		else
			warn("[map oddity] nothing is active")
		end
		return
	end

	local effect = if command == nil or command == "" then "Transparency" else EFFECTS[command]
	if not effect then
		warn("[map oddity] use /mapoddity, /mapoddity doors, or /mapoddity clear")
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		warn(`[map oddity] {player.Name} has no character to target`)
		return
	end

	local ok, chosen, reason = MapOddityService:Trigger(root.Position, effect)
	if not ok then
		warn(`[map oddity] {reason}`)
		return
	end
	warn(`[map oddity] applied {chosen} to the hallway containing {player.Name}`)
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		local name, argument = message:match("^/(%a+)%s*(.*)$")
		if name and (name:lower() == "mapoddity" or name:lower() == "mapodd") then
			run(player, if argument ~= "" then argument else nil)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return MapOddityCommandService
