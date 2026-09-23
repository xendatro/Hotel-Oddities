local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local IntroCutsceneConfig = require(ReplicatedStorage.Configs.IntroCutsceneConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)
local ElevatorService = require(ServerStorage.Services.ElevatorService)
local IntroCutsceneService = require(ServerStorage.Services.IntroCutsceneService)

local IntroCutsceneCommandService = {}

local COMMAND = IntroCutsceneConfig.Command
local RESET = "reset"

function IntroCutsceneCommandService:Play(player: Player): boolean
	if not CharacterService.GetAliveRoot(player) then
		warn(`[{COMMAND}] {player.Name} has no living character to send through the elevator`)
		return false
	end

	IntroCutsceneService:Queue(player)
	if not ElevatorService:SendToMap(player, false) then
		warn(`[{COMMAND}] could not send {player.Name} through the elevator (already riding, cooling down, or the arrival did not stream); the intro stays queued for their next ride`)
		return false
	end

	warn(`[{COMMAND}] {player.Name} rode the elevator; the intro plays when they walk out of it`)
	return true
end

function IntroCutsceneCommandService:Reset(sender: Player, name: string?): boolean
	local target = if name then ChatCommandService.FindPlayer(name) else sender
	if not target then
		warn(`[{COMMAND}] no player matches "{name}"`)
		return false
	end

	IntroCutsceneService:Reset(target)
	warn(`[{COMMAND}] intro reset for {target.Name}; it plays again on their next walk out of the arrival elevator`)
	return true
end

local function run(player: Player, argument: string?)
	local verb, rest = (argument or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local command = (verb or ""):lower()
	local target = if rest and rest ~= "" then rest else nil

	if command == "" then
		task.spawn(IntroCutsceneCommandService.Play, IntroCutsceneCommandService, player)
		return
	end

	if command == RESET then
		IntroCutsceneCommandService:Reset(player, target)
		return
	end

	warn(`[{COMMAND}] use /{COMMAND} or /{COMMAND} {RESET} [player]`)
end

ChatCommandService.Register(COMMAND, {
	Aliases = IntroCutsceneConfig.CommandAliases,
	Handler = run,
})

return IntroCutsceneCommandService
