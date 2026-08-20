--- Restricted testing commands for the hacking computers.
---
---   /hack list                    which game runs on which computer, and what YOU have done
---   /hack <game|room>             teleport in front of that computer (e.g. /hack snake, /hack 227)
---   /hack win <game|room|all>     mark it hacked without playing
---   /hack reset [game|room|all]   put it (default: everything) back to unhacked
---
--- Hacking is per player, so every one of these acts on the SENDER's own state and nobody else's:
--- `win all` finishes the hotel for the tester and leaves everyone else's screens exactly as they
--- were, and `list` reports what the tester has done rather than what the server has seen.
---
--- Games can be named by any prefix ("mine", "aim", "frog"), computers by their room number. Only
--- usable in Studio or by the allowed accounts, like /give.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local ComputerService = require(ServerStorage.Services.ComputerService)

local ComputerCommandService = {}

local ALLOWED_USER_IDS = {
	[265199502] = true,
	[1936118388] = true,
}

--- How far in front of the screen the teleport lands, in studs. Inside the prompt's reach, far
--- enough back that the whole monitor is in view.
local TELEPORT_DISTANCE = 4

--- MUST match `MinigameService.ORDER` and its assignment rule (peers of a maze sorted by their
--- parent room's name, dealt out in this order). Duplicated because that service is client-only
--- and returns a stub on the server; a mismatch here sends the tester to the wrong screen but
--- breaks nothing else.
local ORDER = { "Memory", "AimTrainer", "Frogger", "Snake", "Simon" }

--- Finding computers -----------------------------------------------------------------------------

--- The maze a computer belongs to, or the workspace when it stands outside one. Mirrors the
--- client's rule so both deal the same hand.
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

--- Every tagged computer, grouped and sorted the way the client deals games out.
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

--- Which game `model` runs: its position among the computers of its own maze, dealt into ORDER.
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

--- The computer `text` names: a game (any prefix, "mine"/"frog"/"aim") or a room ("227"/"room_227").
local function findComputer(text: string): (Model?, string?)
	local lowered = text:lower()
	local computers = allComputers()

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

--- Doing things ----------------------------------------------------------------------------------

local function teleport(player: Player, model: Model)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		warn("[hack] no character to teleport")
		return
	end

	local screen: Instance? = model
	for _, name in ComputerConfig.ScreenPath do
		if not screen then break end
		screen = screen:FindFirstChild(name)
	end

	-- The Screen's Front points out into the room; without one, fall back to standing off the
	-- model's own front.
	local base = if screen and screen:IsA("BasePart") then screen.CFrame else model:GetPivot()
	local outward = base.LookVector
	local at = base.Position + outward * TELEPORT_DISTANCE

	-- Dropped a little low and left to physics: room floors vary and a teleport buried in the
	-- carpet self-resolves, where one floating over it reads as broken.
	local stand = Vector3.new(at.X, base.Position.Y - 2, at.Z)
	local look = Vector3.new(base.Position.X, stand.Y, base.Position.Z)
	root.CFrame = CFrame.lookAt(stand, look)
end

--- The list as `sender` has it. HACKED/locked is their own answer -- another player reading the same
--- computers would get a different one.
local function describe(sender: Player): string
	local computers = allComputers()
	local lines = { `[hack] {#computers} computers, for {sender.Name}:` }
	for _, model in computers do
		local room = sortKey(model)
		local done = if ComputerService:IsHacked(sender, model) then "HACKED" else "locked"
		table.insert(lines, `[hack]   {gameOf(model, computers)} -- {room} -- {done}`)
	end
	return table.concat(lines, "\n")
end

local function setAll(sender: Player, hacked: boolean)
	for _, model in allComputers() do
		ComputerService:SetHacked(sender, model, hacked)
	end
end

--- The command -----------------------------------------------------------------------------------

function ComputerCommandService:Execute(sender: Player, argument: string?): boolean
	if not RunService:IsStudio() and not ALLOWED_USER_IDS[sender.UserId] then
		warn(`[hack] {sender.Name} ({sender.UserId}) is not allowed to use /hack`)
		return false
	end

	argument = argument and argument:match("^%s*(.-)%s*$") or ""
	if argument == "" then
		warn("[hack] usage: /hack list | /hack <game|room> | /hack win <game|room|all> | /hack reset [game|room|all]")
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

	-- Anything else names a computer to teleport to.
	local model, game_ = findComputer(argument)
	if not model then
		warn(`[hack] no computer matches "{argument}"`)
		return false
	end
	teleport(sender, model)
	warn(`[hack] {sender.Name} -> {game_} ({sortKey(model)})`)
	return true
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		local command, argument = message:match("^/(%S+)%s*(.*)$")
		if command and command:lower() == "hack" then
			ComputerCommandService:Execute(player, if argument ~= "" then argument else nil)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return ComputerCommandService
