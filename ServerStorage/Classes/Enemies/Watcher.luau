--- @class Watcher
--- Ambient dread with nothing behind it. It has no target, no path, no attack and no opinion about
--- where anybody is going -- it cannot hurt you and never tries. It waits out of sight around a
--- corner somebody has already walked past, leans far enough out to be found there, and is gone the
--- moment they actually look at it.
---
--- Everything it does follows from one rule: it is never in view. Not when it spawns, not when it
--- leans out, not for a second after somebody turns round and sees it. So it only ever works a
--- corner *behind* a player, and the only way to catch it is to turn round -- which is the moment
--- this thing exists to produce, and the moment it ducks back around the corner.
---
--- Where it stands belongs to `PeekSpotService`, which hands back a pair of floor positions either
--- side of some corner behind a player: one nobody can see at all, one clear of them but off their
--- screen. This class only performs: lurk on the blind one until the seen one is still off every
--- screen, slide onto it, hold the pose, and tuck back the instant somebody has it.
---
--- Relocating is a teleport, and a teleport somebody watches reads as a bug rather than a fright, so
--- every move between corners happens from behind one, and a Watcher found while hiding leaves
--- instead of moving.
---
--- Spawn it through `WatcherService`, which finds a corner before the model exists and places it
--- there. Spawned bare through `EnemyService`, it lands wherever it was told and has to go and find a
--- corner itself, which is one relocation it should not have needed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NPC = require(ServerStorage.Classes.NPC)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local ROOT_HEIGHT = 3 -- studs from the floor to an R15 root; peek spots are floor positions
local POLL = 0.1 -- seconds between checks that it is still unseen while waiting behind a corner
local REST_SETTLE = 1.5 -- seconds after tucking away before being seen counts as being found
-- Heights above the floor the emergence check asks about, so a camera trained on the corner at head
-- height is not answered by a clear line to a pair of ankles.
local EMERGENCE_HEIGHTS = { 4.4, 2.5 }
-- How much closer than the tuned minimum a player may get to the peek point before the corner is
-- abandoned. Somebody who has walked up to it is somebody about to get a good look.
local ABANDON_DISTANCE_SCALE = 0.6

local Watcher = NPC.extend("Watcher")

local function randomBetween(minimum: number, maximum: number): number
	return math.random() * (maximum - minimum) + minimum
end

--- Whether the place a Watcher is about to occupy is on anybody's screen.
---
--- `IsObserved` cannot answer this while the rig is still behind the corner -- there is nothing on
--- screen to report -- so it is asked of the reported cameras and a server raycast against the peek
--- position instead.
---
--- The spot was chosen behind the player in the first place, so the usual answer is no and the wait
--- in `Lurk` is short. What this catches is the player who has since turned round, or the second one
--- who has wandered into the far end of that corridor: either way the corner is now somewhere a
--- Watcher would be watched arriving, and it stays put until that stops being true.
local function isPeekOnScreen(config, floorPosition: Vector3): boolean
	local filter = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, model in CollectionService:GetTagged("Enemy") do
		table.insert(filter, model)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	for _, view in EnemyObservationService:GetViews() do
		for _, height in EMERGENCE_HEIGHTS do
			local point = floorPosition + Vector3.yAxis * height
			if EnemyObservationService.IsWithinCone(view, point, config.ViewCone)
				and workspace:Raycast(view.Eye, point - view.Eye, params) == nil
			then
				return true
			end
		end
	end
	return false
end

local function getAliveRoot(player: Player?): BasePart?
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and humanoid and humanoid.Health > 0 then return root end
	return nil
end

--- The corner-search settings this enemy's tuning describes. A spawner needs these before any
--- Watcher exists, which is why they hang off the class rather than an instance.
function Watcher.GetFindOptions(config): PeekSpotService.FindOptions
	return {
		MinDistance = config.MinPeekDistance,
		MaxDistance = config.MaxPeekDistance,
		RearArc = config.RearArc,
		ViewCone = config.ViewCone,
	}
end

--- Puts the rig `lean` of the way out of `spot` -- 0 tucked back behind the corner, 1 fully
--- committed -- staring at `player`. Position and tilt both come from that one number, so a lean
--- interrupted half way through is a pose the retreat can carry on from rather than a place the rig
--- has to be snapped back to. The tilt goes along the spot's lateral axis, so it always leans past
--- the corner rather than into it.
function Watcher:_placeAt(spot: PeekSpotService.PeekSpot, player: Player, lean: number)
	local position = spot.Hide:Lerp(spot.Peek, lean) + Vector3.new(0, ROOT_HEIGHT, 0)

	local target = getAliveRoot(player)
	local lookAt = if target
		then Vector3.new(target.Position.X, position.Y, target.Position.Z)
		else position + self.RootPart.CFrame.LookVector
	if (lookAt - position).Magnitude < 1e-3 then
		lookAt = position + self.RootPart.CFrame.LookVector
	end

	local tilt = math.tan(math.rad(self.Config.PeekTilt * lean))
	self.RootPart.CFrame = CFrame.lookAt(position, lookAt, (Vector3.yAxis + spot.Lateral * tilt).Unit)
	self.Lean = lean
end

--- Moves the lean to `targetLean` over `duration`, which is the time a full 0-to-1 move takes: a
--- retreat from half way out takes half of it. Returns false if `shouldStop` cut the move short,
--- which leaves the rig wherever it had got to.
function Watcher:_slide(
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	targetLean: number,
	shouldStop: (() -> boolean)?
): boolean
	local startLean = self.Lean or 0
	local travel = math.abs(targetLean - startLean)
	if travel < 1e-3 then
		self:_placeAt(spot, player, targetLean)
		return true
	end

	local startedAt = os.clock()
	local scaled = duration * travel

	while true do
		local alpha = math.clamp((os.clock() - startedAt) / scaled, 0, 1)
		self:_placeAt(spot, player, startLean + (targetLean - startLean) * alpha)
		if alpha >= 1 then return true end
		if shouldStop and shouldStop() then return false end
		RunService.Heartbeat:Wait()
	end
end

--- Holds the pose for `duration`, still staring. Returns false if `shouldStop` cut it short.
function Watcher:_hold(
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	shouldStop: (() -> boolean)?
): boolean
	local expiresAt = os.clock() + duration

	while os.clock() < expiresAt do
		if shouldStop and shouldStop() then return false end
		self:_placeAt(spot, player, 1) -- keeps staring while they move
		RunService.Heartbeat:Wait()
	end
	return true
end

--- The nearest living player, who is who it performs for. Nil while nobody is alive to perform to.
function Watcher:_getAudience(): Player?
	local nearest, nearestDistance = nil, math.huge
	local origin = self.RootPart.Position

	for _, player in Players:GetPlayers() do
		local root = getAliveRoot(player)
		if root then
			local distance = (root.Position - origin).Magnitude
			if distance < nearestDistance then
				nearest, nearestDistance = player, distance
			end
		end
	end
	return nearest
end

--- Finds a corner behind somebody and parks on its blind side. Leaves rather than move in front of
--- anybody, and leaves rather than stand around in the open once its budget of quiet peeks is spent.
local function seek(_changeState: StateMachine.ChangeState, npc: any)
	if npc:IsObserved() then
		return "Despawn", npc
	end

	-- A spawner may have handed over the corner it placed this Watcher on. Using it is what keeps a
	-- deliberate placement from being thrown away by a search that would only find another one.
	local spot, player = npc.Spot, npc.Audience
	npc.Spot, npc.Audience = nil, nil
	if not getAliveRoot(player) then
		spot, player = nil, nil
	end

	if not spot then
		player = npc:_getAudience()
		spot = player and PeekSpotService:Find(player, Watcher.GetFindOptions(npc.Config))
	end

	if not player or not spot then
		task.wait(npc.Config.RetryInterval)
		return "Seek", npc
	end

	npc:_placeAt(spot, player, 0)
	return "Lurk", npc, spot, player
end

--- Waits behind the corner for a moment where emerging will not be watched happening. Gives the
--- corner up rather than wait forever: somebody who has turned round and parked facing it, or one
--- who has wandered up close enough to get a proper look, has made this corner useless, and the map
--- has others.
local function lurk(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	local expiresAt = os.clock() + npc.Config.PeekWaitTime
	local abandonDistance = npc.Config.MinPeekDistance * ABANDON_DISTANCE_SCALE

	while true do
		if npc:IsObserved() then
			return "Despawn", npc
		end

		local root = getAliveRoot(player)
		if not root then
			return "Seek", npc
		end
		if (root.Position - spot.Peek).Magnitude < abandonDistance then
			return "Seek", npc
		end
		if os.clock() >= expiresAt then
			return "Seek", npc
		end

		if not isPeekOnScreen(npc.Config, spot.Peek) then break end

		npc:_placeAt(spot, player, 0) -- keeps it aimed, so the lean opens already staring
		task.wait(POLL)
	end

	-- Re-checked here rather than only at spawn: a door has opened or somebody has moved since this
	-- corner was chosen, and leaning out of a spot that is no longer around a corner -- or no longer
	-- behind anybody -- is the failure this whole class is arranged to avoid.
	if not PeekSpotService:IsStillValid(spot, player, Watcher.GetFindOptions(npc.Config)) then
		return "Seek", npc
	end

	return "Peek", npc, spot, player
end

--- Leans out and holds the pose, and hides the moment anybody has it. Being caught is the point of
--- the exercise and the end of it: no grace, no standing there being looked at. Cut short mid-lean,
--- the retreat carries on from whatever pose it had reached.
local function peek(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	local function isCaught()
		return npc:IsObserved()
	end

	local caught = not npc:_slide(spot, player, npc.Config.LeanTime, 1, isCaught)
	if not caught then
		local hold = randomBetween(npc.Config.HoldTimeMin, npc.Config.HoldTimeMax)
		caught = not npc:_hold(spot, player, hold, isCaught)
	end

	npc.PeeksLeft -= 1
	return "Retreat", npc, spot, player, caught
end

--- Pulls back behind the corner. The retreat plays out rather than cutting: it should look like
--- something stepping out of view, not something switched off.
local function retreat(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	caught: boolean
)
	npc:_slide(spot, player, npc.Config.RetreatTime, 0)

	if npc.PeeksLeft <= 0 then
		return "Despawn", npc
	end
	return "Rest", npc, caught
end

--- Waits out of sight before going anywhere. Longer after being caught -- the pause is what makes the
--- next one read as a second sighting rather than as the same thing bobbing in and out. Found in the
--- meantime, it leaves: waiting out of sight is the whole arrangement, and there is nothing to wait
--- for once that is over.
---
--- That last rule cannot apply immediately, which is what `REST_SETTLE` is for. Arriving here having
--- just been stared at means arriving still counting as observed: `ObservationHold` keeps the last
--- sighting alive for a moment by design, and the reports covering the retreat are still in flight
--- behind it. Checking on the first frame reads all of that as "they can still see me" and leaves,
--- so a Watcher that gets caught despawns instead of hiding -- the one behaviour this state exists to
--- provide. The window only has to outlast the hold and the age of a report.
local function rest(_changeState: StateMachine.ChangeState, npc: any, caught: boolean)
	local duration = if caught
		then randomBetween(npc.Config.SeenRestMin, npc.Config.SeenRestMax)
		else randomBetween(npc.Config.RestTimeMin, npc.Config.RestTimeMax)

	local startedAt = os.clock()
	local expiresAt = startedAt + duration
	while os.clock() < expiresAt do
		if os.clock() - startedAt > REST_SETTLE and npc:IsObserved() then
			return "Despawn", npc
		end
		task.wait(POLL)
	end
	return "Seek", npc
end

--- @param spot PeekSpotService.PeekSpot? -- the corner a spawner already placed it on
--- @param player Player? -- who that corner was found behind
function Watcher.new(model: Model, config, spot: PeekSpotService.PeekSpot?, player: Player?)
	local self = NPC.new(model, config, Watcher)
	self.Spot = spot
	self.Audience = player
	self.Lean = 0
	return self
end

function Watcher:Start()
	-- This rig is held together by physics constraints rather than motors, so an unanchored root
	-- sags out of whatever pose it is put in, and the humanoid's own state machine would spend every
	-- frame fighting a root that is being placed by hand.
	self.Humanoid.EvaluateStateMachine = false
	self.RootPart.Anchored = true
	-- No nameplate. Every other enemy can afford one -- you are meant to have already seen those, and
	-- a Mimic arguably wants to look like something with a name over it. This one is a shape at the end
	-- of a corridor, and a caption floating above it answers the only question it exists to ask.
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.PeeksLeft = math.random(self.Config.PeekCountMin, self.Config.PeekCountMax)
	NPC.Start(self)
end

function Watcher:BuildStateMachine(): StateMachine.StateMachine
	return StateMachine.new({
		Seek = seek,
		Lurk = lurk,
		Peek = peek,
		Retreat = retreat,
		Rest = rest,
		Despawn = NPC.SharedStates.Despawn,
	}, {
		-- Mapped to nothing on purpose: it does not fight, so a bear trap or a paper ball has
		-- nothing of its behaviour to interrupt, and an unmapped reason warns every time one lands.
		Impact = {},
	}, {}, "Seek", self)
end

return Watcher
