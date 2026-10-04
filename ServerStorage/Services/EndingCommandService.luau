local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EndingCutsceneConfig = require(ReplicatedStorage.Configs.EndingCutsceneConfig)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)
local EndingService = require(ServerStorage.Services.EndingService)

local EndingCommandService = {}

local COMMAND = EndingCutsceneConfig.Command

function EndingCommandService:Play(sender: Player, name: string?): boolean
	local target = if name then ChatCommandService.FindPlayer(name) else sender
	if not target then
		warn(`[{COMMAND}] no player matches "{name}"`)
		return false
	end
	if EndingService:IsEnding(target) then
		warn(`[{COMMAND}] {target.Name} is already in the ending`)
		return false
	end
	if not EndingService:Preview(target) then
		warn(`[{COMMAND}] could not start the ending for {target.Name} (no living character or no exit elevator)`)
		return false
	end

	warn(`[{COMMAND}] {target.Name} is watching the ending from the exit elevator; no escape was awarded and no progress was reset`)
	return true
end

local function run(player: Player, argument: string?)
	local name = (argument or ""):match("^%s*(.-)%s*$")
	task.spawn(EndingCommandService.Play, EndingCommandService, player, if name and name ~= "" then name else nil)
end

ChatCommandService.Register(COMMAND, {
	Aliases = EndingCutsceneConfig.CommandAliases,
	Handler = run,
})

return EndingCommandService
