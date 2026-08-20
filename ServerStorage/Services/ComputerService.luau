--- The server's half of the computers: which models are puzzles, and which of those each player has
--- broken into.
---
--- Hacking is PER PLAYER, not per server. It is not a teamwork game -- players can work together to
--- FIND the five computers, but each of them plays the minigames and breaks in on their own. So the
--- state here is a set of models per player, one player finishing a computer changes nothing for
--- anybody else, and the screen colour is not the server's business at all: it is painted by each
--- client from its own set (see the client ComputerService).
---
--- Registration is done here rather than by hand in Studio because the mazes are generated: the
--- rooms carrying computers do not exist until a maze is built, so workspace is swept once at boot
--- and watched afterwards. A `ComputerModel` sitting directly under Workspace is the authoring
--- template and is skipped -- it is furniture nobody is meant to hack.
---
--- A completion is only honoured for a living player standing in front of the computer they named,
--- for a computer THEY have not finished yet. Anything else is dropped without comment: the minigame
--- is played entirely on the client, so this remote is the only place the claim can be checked at all.
---
--- What the rest of the server may call:
---   ComputerService:IsHacked(player, model): boolean
---   ComputerService:SetHacked(player, model, hacked)   -- syncs that player
---   ComputerService:GetProgress(player): (hacked, total)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)

local ComputerService = {}

local TAG = ComputerConfig.Tag
local REACH = ComputerConfig.Targeting.ServerReach
--- Seconds between one player's completions. A minigame takes far longer than this; the limit is
--- only here so a broken or hostile client cannot spray the remote.
local MIN_INTERVAL = 0.5

--- What the shared `Hacked` boolean used to be written to. Nothing reads it any more -- the state is
--- per player and never touches the model -- but place files saved before the split still carry it,
--- so it is stripped at registration rather than left to confuse the next person in the properties
--- panel.
local LEGACY_ATTRIBUTE = "Hacked"

--- Remotes ---------------------------------------------------------------------------------------

--- Built here rather than authored in Studio so the folder cannot go missing from a place file, and
--- so the client's WaitForChild always has something to find. Both remotes exist by the time this
--- module has finished being required, which is what lets the client wait on either of them.
local function ensureRemotes(): (RemoteEvent, RemoteEvent)
	local communication = ReplicatedStorage:FindFirstChild("Communication")
	if not communication then
		communication = Instance.new("Folder")
		communication.Name = "Communication"
		communication.Parent = ReplicatedStorage
	end

	local folder = communication:FindFirstChild(ComputerConfig.Remotes.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ComputerConfig.Remotes.Folder
		folder.Parent = communication
	end

	local function remote(name: string): RemoteEvent
		local existing = folder:FindFirstChild(name)
		if existing then return existing :: RemoteEvent end

		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = folder
		return created
	end

	return remote(ComputerConfig.Remotes.Complete), remote(ComputerConfig.Remotes.Sync)
end

local Complete, Sync = ensureRemotes()

--- The state -------------------------------------------------------------------------------------

--- Which computers each player has broken into. The inner tables hold their models weakly, so a maze
--- that is torn down takes its computers out of everyone's set instead of being pinned alive by it.
local Hacked: { [Player]: { [Model]: true } } = {}
local LastComplete: { [Player]: number } = {}

local function setOf(player: Player): { [Model]: true }
	local set = Hacked[player]
	if not set then
		set = (setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: true }
		Hacked[player] = set
	end
	return set
end

--- Sends `player` everything they have hacked, as one array of models.
---
--- Always the whole set rather than "this one changed": there are at most a handful of computers in
--- a hotel, so a snapshot is the same size as a delta would be, it is idempotent, and a client that
--- missed one message cannot end up quietly disagreeing with the server about what it has done.
local function sync(player: Player)
	local snapshot: { Model } = {}
	-- `pairs` rather than generalized iteration: these sets carry a metatable to make their keys weak,
	-- and Luau refuses to iterate a table with a metatable that has no `__iter`.
	for model in pairs(setOf(player)) do
		table.insert(snapshot, model)
	end
	Sync:FireClient(player, snapshot)
end

--- Registration ----------------------------------------------------------------------------------

--- A model that is one of the hotel's computers rather than the template at the root of Workspace.
local function eligible(instance: Instance): boolean
	return instance:IsA("Model")
		and instance.Name == ComputerConfig.ModelName
		and instance.Parent ~= nil
		and instance.Parent ~= workspace
end

local function register(instance: Instance)
	if not eligible(instance) then return end
	local model = instance :: Model

	if not CollectionService:HasTag(model, TAG) then
		CollectionService:AddTag(model, TAG)
	end
	if model:GetAttribute(LEGACY_ATTRIBUTE) ~= nil then
		model:SetAttribute(LEGACY_ATTRIBUTE, nil)
	end
end

--- Reading and writing the state -------------------------------------------------------------------

--- Whether `player` has broken into `model`.
function ComputerService:IsHacked(player: Player, model: Model): boolean
	local set = Hacked[player]
	return set ~= nil and set[model] == true
end

--- How many of the computers in play `player` has finished, and how many there are. The exit gate,
--- when it is written, asks this rather than counting anything itself.
function ComputerService:GetProgress(player: Player): (number, number)
	local set = Hacked[player]
	local hacked, total = 0, 0
	for _, model in CollectionService:GetTagged(TAG) do
		if model:IsDescendantOf(workspace) then
			total += 1
			if set and set[model :: Model] then
				hacked += 1
			end
		end
	end
	return hacked, total
end

--- Marks `model` hacked (or puts it back) FOR ONE PLAYER, and tells that player's client. Also the
--- way anything else on the server -- an oddity, a round reset, the /hack command -- gets at a
--- computer.
function ComputerService:SetHacked(player: Player, model: Model, hacked: boolean)
	local set = setOf(player)
	local was = set[model] == true
	if was == hacked then return end

	set[model] = if hacked then true else nil
	sync(player)
end

--- Requests --------------------------------------------------------------------------------------

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return nil end
	return root.Position
end

Complete.OnServerEvent:Connect(function(player: Player, model: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if not model:IsDescendantOf(workspace) or not CollectionService:HasTag(model, TAG) then return end
	-- Already done by THIS player is not a failure, just nothing to do: the client marks its own win
	-- the moment it lands and this remote is the confirmation arriving behind it.
	if ComputerService:IsHacked(player, model) then return end

	local now = os.clock()
	if now - (LastComplete[player] or 0) < MIN_INTERVAL then return end

	local position = characterPosition(player)
	if not position or (model:GetPivot().Position - position).Magnitude > REACH then return end

	LastComplete[player] = now
	ComputerService:SetHacked(player, model, true)
end)

--- Players ---------------------------------------------------------------------------------------

-- A join gets an (empty) snapshot straight away rather than nothing at all, so a client can tell
-- "the server says you have hacked none of them" from "the server has not spoken yet".
Players.PlayerAdded:Connect(sync)

Players.PlayerRemoving:Connect(function(player: Player)
	Hacked[player] = nil
	LastComplete[player] = nil
end)

--- Boot ------------------------------------------------------------------------------------------

for _, descendant in workspace:GetDescendants() do
	register(descendant)
end

-- Generated mazes arrive long after this module is required, and a room parented into workspace
-- reports every part of itself through this signal -- including the computer inside it.
workspace.DescendantAdded:Connect(register)

-- In Studio the local player is usually already in before the services are required, so PlayerAdded
-- has been and gone; everyone present at boot gets their snapshot here instead.
for _, player in Players:GetPlayers() do
	sync(player)
end

return ComputerService
