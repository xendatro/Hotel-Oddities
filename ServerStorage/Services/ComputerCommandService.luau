local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ComputerChipConfig = require(ReplicatedStorage.Configs.ComputerChipConfig)
local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)
local EndingConfig = require(ReplicatedStorage.Configs.EndingConfig)
local ComputerService = require(ServerStorage.Services.ComputerService)

local ComputerCommandService = {}

local TELEPORT_DISTANCE = 4

local ORDER = { "Memory", "AimTrainer", "Frogger", "Snake", "Simon" }

local function mazeOf(model: Instance): Instance
	local instance: Instance? = model
	while instance and instance ~= workspace do
		if instance.Name:match("^Maze%d+") then
			return instance
		end
		instance = instance.Parent
	end
	return workspace
end

local function sortKey(model: Model): string
	local parent = model.Parent
	return if parent then parent.Name else model.Name
end

local function allComputers(): { Model }
	local computers: { Model } = {}
	for _, tagged in CollectionService:GetTagged(ComputerConfig.Tag) do
		if tagged:IsA("Model") and tagged:IsDescendantOf(workspace) then
			table.insert(computers, tagged)
		end
	end
	table.sort(computers, function(a: Model, b: Model): boolean
		local left, right = sortKey(a), sortKey(b)
		if left == right then
			return a:GetFullName() < b:GetFullName()
		end
		return left < right
	end)
	return computers
end

local function gameOf(model: Model, computers: { Model }): string
	local maze = mazeOf(model)
	local index = 0
	for _, peer in computers do
		if mazeOf(peer) ~= maze then continue end
		index += 1
		if peer == model then
			return ORDER[(index - 1) % #ORDER + 1]
		end
	end
	return ORDER[1]
end

local function colorOf(model: Model): string?
	local maze = workspace:FindFirstChild(ComputerChipConfig.MazeName)
	local rooms = maze and maze:FindFirstChild("Rooms")
	for _, entry in ComputerChipConfig.Colors do
		local room = rooms and rooms:FindFirstChild(entry.RoomName)
		if room and model.Parent == room then return entry.Key end
	end
	return nil
end

local function computerForColor(lowered: string): Model?
	local maze = workspace:FindFirstChild(ComputerChipConfig.MazeName)
	local rooms = maze and maze:FindFirstChild("Rooms")
	if not rooms then return nil end
	for _, entry in ComputerChipConfig.Colors do
		if entry.Key:lower() ~= lowered then continue end
		local room = rooms:FindFirstChild(entry.RoomName)
		local model = room and room:FindFirstChild(ComputerConfig.ModelName)
		if model and model:IsA("Model") then return model end
	end
	return nil
end

local function findComputer(text: string): (Model?, string?)
	local lowered = text:lower()
	local computers = allComputers()

	local byColor = computerForColor(lowered)
	if byColor then
		return byColor, gameOf(byColor, computers)
	end

	for _, model in computers do
		local game_ = gameOf(model, computers)
		if game_:lower():sub(1, #lowered) == lowered then
			return model, game_
		end
	end

	local room = lowered:match("^room_(%S+)$") or lowered
	for _, model in computers do
		local parent = model.Parent
		if parent and parent.Name:lower():match(`^room_{room}$`) then
			return model, gameOf(model, computers)
		end
	end

	return nil, nil
end

local function teleport(player: Player, model: Model)
	local root = CharacterService.GetAliveRoot(player)
	if not root then
		warn("[hack] no character to teleport")
		return
	end

	local screen: Instance? = model
	for _, name in ComputerConfig.ScreenPath do
		if not screen then break end
		screen = screen:FindFirstChild(name)
	end

	local base = if screen and screen:IsA("BasePart") then screen.CFrame else model:GetPivot()
	local outward = base.LookVector
	local at = base.Position + outward * TELEPORT_DISTANCE

	local stand = Vector3.new(at.X, base.Position.Y - 2, at.Z)
	local look = Vector3.new(base.Position.X, stand.Y, base.Position.Z)
	root.CFrame = CFrame.lookAt(stand, look)
end

local function describe(sender: Player): string
	local computers = allComputers()
	local lines = { `[hack] {#computers} computers, for {sender.Name}:` }
	for _, model in computers do
		local room = sortKey(model)
		local done = if ComputerService:IsHacked(sender, model) then "HACKED" else "locked"
		local color = colorOf(model)
		table.insert(lines, `[hack]   {gameOf(model, computers)} -- {room}{if color then " -- " .. color else ""} -- {done}`)
	end
	return table.concat(lines, "\n")
end

local function setAll(sender: Player, hacked: boolean)
	if not hacked then
		ComputerService:ResetProgress(sender)
		return
	end
	for _, model in allComputers() do
		ComputerService:SetHacked(sender, model, true)
	end
end

function ComputerCommandService:Execute(sender: Player, argument: string?): boolean
	argument = argument and argument:match("^%s*(.-)%s*$") or ""
	if argument == "" then
		warn("[hack] usage: /hack list | /hack <color|game|room> | /hack win <color|game|room|all> | /hack reset [color|game|room|all]")
		return false
	end

	local verb, rest = argument:match("^(%S+)%s*(.*)$")
	verb = (verb :: string):lower()

	if verb == "list" then
		warn(describe(sender))
		return true
	end

	if verb == "win" or verb == "reset" then
		local hacked = verb == "win"
		if rest == "" and verb == "reset" then rest = "all" end
		if (rest :: string):lower() == "all" then
			setAll(sender, hacked)
			warn(`[hack] every computer set to {if hacked then "hacked" else "locked"} for {sender.Name}`)
			return true
		end

		local model, game_ = findComputer(rest)
		if not model then
			warn(`[hack] no computer matches "{rest}"`)
			return false
		end
		ComputerService:SetHacked(sender, model, hacked)
		warn(`[hack] {game_} ({sortKey(model)}) set to {if hacked then "hacked" else "locked"} for {sender.Name}`)
		return true
	end

	local model, game_ = findComputer(argument)
	if not model then
		warn(`[hack] no computer matches "{argument}"`)
		return false
	end
	teleport(sender, model)
	warn(`[hack] {sender.Name} -> {game_} ({sortKey(model)})`)
	return true
end

ChatCommandService.Register("hack", {
	AdminOnly = true,
	Handler = function(player: Player, argument: string?)
		ComputerCommandService:Execute(player, argument)
	end,
})

ChatCommandService.Register(EndingConfig.Command, {
	AdminOnly = true,
	Handler = function(player: Player, argument: string?)
		local target = if argument and argument ~= "" then ChatCommandService.FindPlayer(argument) else player
		if not target then
			warn(`[{EndingConfig.Command}] no player matches "{argument}"`)
			return
		end
		ComputerService:ResetProgress(target)
		warn(`[{EndingConfig.Command}] computer progress reset for {target.Name}`)
	end,
})

return ComputerCommandService
