--- Owns how much each player knows about each enemy, and is the only thing allowed to change it.
---
--- Knowledge is a number from 0 to 1 per enemy id rather than a flag. Zero is an entry the player
--- has never met and the index draws as UNDISCOVERED; 1 is one they have its whole write-up for.
--- Everything in between is a partly-redacted description, which `ReplicatedStorage.Modules.Redaction`
--- draws and `IndexConfig` tunes.
---
--- Progress is earned four ways, all of them configured per enemy in `Configs.DiscoveryConfig`:
--- looking at something, being near something, a moment an enemy declares about itself, and dying to
--- it. Death is the biggest single payment and the only one the player is shown an animation for.
---
--- ### Why sighting is checked here rather than through `EnemyObservationService`
---
--- That service already answers "can this client see this model", and it is tempting to reuse. It is
--- the wrong tool twice over. It only answers for models tagged `Observable`, which is four enemies
--- -- the ones that *react* to being looked at -- because the client pays a raycast per visible part
--- per model at 20Hz to produce that answer, and `EnemyConfigs` is explicit that this is only worth
--- spending on an enemy that would do something with it. Tagging all twelve would multiply that cost
--- on every client for eight enemies that would ignore it.
---
--- Discovery does not need that answer anyway. It needs "did this player get a good look at it",
--- which is coarse, tolerant of a frame of error, and fine to ask four times a second off a single
--- raycast to the model's middle. So it asks its own question, off the camera the client is already
--- reporting -- which the observation service has already range-checked against the character, so a
--- client cannot claim to have been looking from somewhere it was not.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local DiscoveryConfig = require(ServerStorage.Configs.DiscoveryConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local EnemyService = require(ServerStorage.Services.EnemyService)

local Communication = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("Index")
local Update = Communication:WaitForChild("Update") :: RemoteEvent
local Reveal = Communication:WaitForChild("Reveal") :: RemoteEvent

local EnemyDiscoveryService = {}

--- Live progress per player, keyed by enemy id. Absent means zero; nothing is ever stored at zero,
--- so a save file only carries what has actually been met.
local Progress: { [Player]: { [string]: number } } = {}
--- Seconds of unbroken looking at each enemy id, reset the moment the look breaks. This is what
--- `MinDwell` is measured against, and why glancing across a corridor repeatedly earns nothing.
local Dwell: { [Player]: { [string]: number } } = {}
--- What was last sent to each client, so the sweep only replicates when something has moved far
--- enough to be worth a remote call.
local Replicated: { [Player]: { [string]: number } } = {}
--- A death's gain, held from the moment it lands until the player respawns. The index cannot show a
--- reveal to a corpse: the death screen is up, and the player is not in a position to read anything.
local PendingReveal: { [Player]: { Id: string, Before: number, After: number } } = {}

local accumulator = 0

--- Progress `player` has for `enemyId`. The one place anything reads it from.
function EnemyDiscoveryService:Get(player: Player, enemyId: string): number
	local set = Progress[player]
	return (set and set[enemyId]) or 0
end

function EnemyDiscoveryService:GetAll(player: Player): { [string]: number }
	return table.clone(Progress[player] or {})
end

--- Writes the player's whole set to their client. Called on a load, and afterwards only when the
--- sweep decides something has changed by enough to be worth saying.
local function replicate(player: Player)
	local set = Progress[player]
	if not set then return end

	Replicated[player] = table.clone(set)
	Update:FireClient(player, set)
end

--- Copies live progress back into the profile so it survives the session. Free to call often: this
--- only writes into the table ProfileService already holds in memory, and the actual datastore write
--- is on its own autosave timer.
local function persist(player: Player)
	local profile = DataSaveService:Get(player)
	if not profile then return end
	profile.Data.DiscoveredEnemies = table.clone(Progress[player] or {})
end

--- Adds `amount` to what `player` knows about `enemyId` and returns what it was and what it now is.
--- Every other way of granting progress ends up here.
---
--- Replication is deliberately not automatic. A sighting climbing at 0.055/s calls this four times a
--- second, and firing a remote at every one of those would be sixteen calls a second per player per
--- enemy on screen; the caller decides when the client needs to hear about it, and the sweep batches.
function EnemyDiscoveryService:Grant(player: Player, enemyId: string?, amount: number): (number, number)
	if not enemyId or amount <= 0 then return 0, 0 end

	local set = Progress[player]
	if not set then return 0, 0 end

	local before = set[enemyId] or 0
	if before >= 1 then return before, before end

	local after = math.clamp(before + amount, 0, 1)
	set[enemyId] = after
	persist(player)
	return before, after
end

--- Puts one entry at an exact value, rather than adding to it. Nothing in the game earns progress
--- this way -- every real gain goes through `Grant`, which can only ever move a number up. This is
--- the escape hatch for tooling: a debug command that wants to see the half-redacted states without
--- earning them, or a test that needs a player put back to nothing between runs.
function EnemyDiscoveryService:Set(player: Player, enemyId: string, progress: number)
	local set = Progress[player]
	if not set then return end

	local value = math.clamp(progress, 0, 1)
	set[enemyId] = value > 0 and value or nil
	persist(player)
	replicate(player)
end

--- Everything this player has ever met, forgotten. Same reasoning as `Set`, and the same warning:
--- nothing in the game calls this.
function EnemyDiscoveryService:Clear(player: Player)
	if not Progress[player] then return end

	Progress[player] = {}
	Dwell[player] = {}
	persist(player)
	replicate(player)
end

--- The moment an enemy declares about itself -- a Mimic dropping the act, a Stalker turning somebody
--- around, a Chaos going past close enough to have been survived rather than watched. For the enemies
--- whose encounter cannot be detected by looking, because looking is the thing they defeat.
function EnemyDiscoveryService:GrantEvent(player: Player, enemyId: string?)
	if not enemyId then return end

	local rule = DiscoveryConfig.Resolve(enemyId)
	if not rule.Event then return end

	local before, after = EnemyDiscoveryService:Grant(player, enemyId, rule.Event)
	if after > before then
		replicate(player)
	end
end

--- It killed them. The largest single gain, and the only one that queues a reveal: whatever this
--- uncovers is shown to the player on respawn rather than silently added.
function EnemyDiscoveryService:GrantDeath(player: Player, enemyId: string?)
	if not enemyId then return end

	local rule = DiscoveryConfig.Resolve(enemyId)
	local before, after = EnemyDiscoveryService:Grant(player, enemyId, rule.Death)
	if after <= before then return end

	replicate(player)
	PendingReveal[player] = { Id = enemyId, Before = before, After = after }
end

--- Whether `eye` looking along `look` has a clear view of `model` under `rule`. Range first, then
--- angle, then a single raycast -- cheapest test first, because the overwhelming majority of enemies
--- on any given tick fail on range and never reach the cast.
local function hasView(eye: Vector3, look: Vector3, character: Model, model: Model, rule): boolean
	local bounds = model:GetBoundingBox()
	local offset = bounds.Position - eye
	local distance = offset.Magnitude
	if distance > rule.Range then return false end
	if distance < 1e-3 then return true end

	local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(look), -1, 1)))
	if angle > rule.Angle then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, model }
	params.RespectCanCollide = true

	-- Aimed at the middle of the model rather than at each of its parts. A thing half behind a door
	-- frame does not count as seen, which is the right answer for "did you get a look at it" even
	-- though it is the wrong one for "is any pixel of it visible" -- and the latter is what the
	-- observation service exists to answer, at a cost this has no reason to pay.
	return workspace:Raycast(eye, offset, params) == nil
end

--- Every enemy currently in the world, as id-and-model pairs. Sisters is one enemy with two rigs and
--- reports both, so being shown either of them counts.
local function activeModels(): { { Id: string, Model: Model } }
	local entries = {}
	for _, enemy in EnemyService:GetActive() do
		local id = enemy.EnemyId
		if not id then continue end

		for _, model in (enemy.Models or { enemy.Model }) do
			if typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(workspace) then
				table.insert(entries, { Id = id, Model = model })
			end
		end
	end
	return entries
end

--- One player's worth of a sweep. Returns whether anything moved far enough to be worth telling
--- their client about.
local function sweepPlayer(player: Player, models: { { Id: string, Model: Model } }, delta: number): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and humanoid and root and humanoid.Health > 0) then return false end

	local eye, look = EnemyObservationService:GetView(player)
	if not (eye and look) then return false end

	local dwell = Dwell[player]
	if not dwell then return false end

	-- Which ids were in view this tick, so an enemy that has left it can have its dwell reset. Kept
	-- per id rather than per model because two Sisters are one entry: looking at either of them
	-- should not restart the clock the other one was running.
	local seen: { [string]: boolean } = {}
	local gained = false

	for _, entry in models do
		local rule = DiscoveryConfig.Resolve(entry.Id)
		local current = EnemyDiscoveryService:Get(player, entry.Id)
		if current >= 1 then continue end

		if rule.Sight and hasView(eye, look, character, entry.Model, rule.Sight) then
			seen[entry.Id] = true
			local held = (dwell[entry.Id] or 0) + delta
			dwell[entry.Id] = held

			-- Nothing is paid until the look has been held. Past that the whole tick counts, so a
			-- steady stare is not penalised for the dwell it already served.
			if held >= rule.Sight.MinDwell then
				EnemyDiscoveryService:Grant(player, entry.Id, rule.Sight.GainPerSecond * delta)
				gained = true
			end
		end

		-- Proximity does not care about the dwell or about being looked at, and is checked from the
		-- character rather than the camera: what it measures is having been somewhere, not having
		-- noticed anything.
		if rule.Proximity then
			local distance = (entry.Model:GetPivot().Position - root.Position).Magnitude
			if distance <= rule.Proximity.Range then
				EnemyDiscoveryService:Grant(player, entry.Id, rule.Proximity.GainPerSecond * delta)
				gained = true
			end
		end
	end

	for id in dwell do
		if not seen[id] then
			dwell[id] = nil
		end
	end

	if not gained then return false end

	-- Only worth a remote once the number has moved enough for the index to draw it differently.
	local last = Replicated[player] or {}
	for id, value in Progress[player] or {} do
		if value >= 1 and (last[id] or 0) < 1 then return true end
		if value - (last[id] or 0) >= DiscoveryConfig.ReplicateStep then return true end
	end
	return false
end

local function sweep(delta: number)
	local models = activeModels()
	if #models == 0 then return end

	for _, player in Players:GetPlayers() do
		if sweepPlayer(player, models, delta) then
			replicate(player)
		end
	end
end

if FLAGS.Enemies then
	RunService.Heartbeat:Connect(function(delta: number)
		accumulator += delta
		if accumulator < DiscoveryConfig.SweepInterval then return end

		local elapsed = accumulator
		accumulator = 0
		sweep(elapsed)
	end)
end

--- Loading and respawning -------------------------------------------------------------------------

local function watchCharacter(player: Player)
	local pending = PendingReveal[player]
	if not pending then return end
	PendingReveal[player] = nil

	-- Sent as soon as the character is back. *When* it is shown is the client's problem and not this
	-- one's: the death screen holds a finished hint well past the respawn that triggers this, so any
	-- delay chosen here would be guessing at a length only the client can measure. `PlayReveal`
	-- waits the screen out before it opens anything.
	if not player:IsDescendantOf(Players) then return end
	Reveal:FireClient(player, pending.Id, pending.Before, pending.After)
end

local function watchPlayer(player: Player)
	Progress[player] = {}
	Dwell[player] = {}

	task.spawn(function()
		local profile = DataSaveService:Wait(player)
		if not profile or not player:IsDescendantOf(Players) then return end

		local saved = profile.Data.DiscoveredEnemies
		local loaded = {}
		if type(saved) == "table" then
			for id, value in saved do
				-- Anything that is not a number in range is dropped rather than trusted: a save file
				-- outlives the config that wrote it, and an id that has since been retired should not
				-- come back as a card the index cannot draw.
				if type(id) == "string" and type(value) == "number" then
					loaded[id] = math.clamp(value, 0, 1)
				end
			end
		end

		Progress[player] = loaded
		replicate(player)
	end)

	player.CharacterAdded:Connect(function()
		watchCharacter(player)
	end)
end

-- A client that missed its load -- or reconnected a GUI after one -- can ask for the set again.
Update.OnServerEvent:Connect(function(player: Player)
	replicate(player)
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	persist(player)
	Progress[player] = nil
	Dwell[player] = nil
	Replicated[player] = nil
	PendingReveal[player] = nil
end)

return EnemyDiscoveryService
