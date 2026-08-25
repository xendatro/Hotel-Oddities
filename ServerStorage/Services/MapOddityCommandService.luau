local ServerStorage = game:GetService("ServerStorage")

local MapOddityService = require(ServerStorage.Services.MapOddityService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local MapOddityCommandService = {}

local EFFECTS = {
	transparency = "Transparency",
	translucent = "Transparency",
	door = "DoorsOpen",
	doors = "DoorsOpen",
	doorsopen = "DoorsOpen",
	open = "DoorsOpen",
	chaos = "HallwayChaos",
	flicker = "HallwayChaos",
	light = "HallwayChaos",
	lights = "HallwayChaos",
	hallway = "HallwayChaos",
	hallwaychaos = "HallwayChaos",
	hallwayflicker = "HallwayChaos",
	insanity = "HallwayChaos",
	block = "HallwayBlocker",
	blocker = "HallwayBlocker",
	hallwayblock = "HallwayBlocker",
	hallwayblocker = "HallwayBlocker",
	void = "HallwayVoid",
	gap = "HallwayVoid",
	hallwayvoid = "HallwayVoid",
	hallwaygap = "HallwayVoid",
	crush = "HallwayCrush",
	squeeze = "HallwayCrush",
	walls = "HallwayCrush",
	close = "HallwayCrush",
	closing = "HallwayCrush",
	hallwaycrush = "HallwayCrush",
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
		warn("[map oddity] use /mapoddity, /mapoddity doors, /mapoddity chaos, /mapoddity blocker, /mapoddity void, /mapoddity crush, or /mapoddity clear")
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

ChatCommandService.Register("mapoddity", {
	Aliases = { "mapodd" },
	Handler = function(player: Player, argument: string?)
		run(player, argument)
	end,
})

return MapOddityCommandService
