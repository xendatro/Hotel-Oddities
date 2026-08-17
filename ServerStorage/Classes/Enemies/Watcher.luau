--- @class Watcher
--- Ambient dread with nothing behind it. It has no target, no path and no attack -- it cannot hurt
--- you and never tries. It waits out of sight around a corner somebody has already walked past, tips
--- its body out far enough to be found there, and is gone the moment they actually look at it.
---
--- Everything it does follows from one rule: it is never seen arriving. Not when it spawns, not when
--- it leans out, not for a second after. So it only ever works a corner *behind* a player, and the
--- only way to catch it is to turn round -- which is the moment this thing exists to produce, and the
--- moment it ducks back around the corner and goes for good.
---
--- Being caught is terminal, and that is the whole shape of the thing. There is no grace, no second
--- pose, no standing there being looked at: eyes on it and it is already retreating. You get one
--- glimpse of it per Watcher, and never a second look at the same one.
---
--- The pose belongs to `PeekSpotService`, which hands back one place to stand behind a corner and an
--- angle to tip through. The feet never move. What comes into view is the head and shoulders swinging
--- out past the corner, which is what peeking around a corner looks like and is not what walking out
--- from behind one looks like. This class only performs: lurk upright until the arc is off every
--- screen, tip out, hold, and drop back.
---
--- Spawn it through `WatcherService`, which finds a corner before the model exists and places it
--- there. Spawned bare through `EnemyService`, it lands wherever it was told and has to go and find a
--- corner itself, which is one relocation it should not have needed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NPC = require(ServerStorage.Classes.NPC)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local POLL = 0.1 -- seconds between checks that it is still unseen while waiting behind a corner
local SEEN_HOLD_TIME = 0.7 -- seconds it stays exposed after somebody catches the peek
-- How much closer than the tuned minimum a player may get before the corner is abandoned. Somebody
-- who has walked up to it is somebody about to get a good look at it standing still.
local ABANDON_DISTANCE_SCALE = 0.6

local Watcher = NPC.extend("Watcher")

local function randomBetween(minimum: number, maximum: number): number
	return math.random() * (maximum - minimum) + minimum
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

--- Puts the rig `lean` of the way out -- 0 upright behind the corner, 1 tipped all the way -- staring
--- at `player`. Pose and tilt are both that one number, so a lean interrupted half way through is a
--- pose the retreat carries on from rather than a place the rig has to be snapped back to.
function Watcher:_placeAt(spot: PeekSpotService.PeekSpot, player: Player, lean: number)
	local target = getAliveRoot(player)
	self.RootPart.CFrame = PeekSpotService.PoseAt(spot, lean, target and target.Position)
	self.Lean = lean
end

--- Moves the lean to `targetLean` over `duration`, which is what a full 0-to-1 move costs: a retreat
--- from half way out takes half of it. Returns false if `shouldStop` cut the move short, which leaves
--- the rig wherever it had got to.
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

--- Whether the arc this Watcher would tip through is on anybody's screen.
---
--- `IsObserved` cannot answer this while the rig is still upright behind the corner -- there is
--- nothing on screen to report -- so it is asked of the reported cameras against the places the head
--- will pass through. The spot was chosen behind the player to begin with, so the usual answer is no
--- and the wait is short. What this catches is the player who has since turned round, or a second one
--- who has wandered into the far end of that corridor.
function Watcher:_isArcOnScreen(spot: PeekSpotService.PeekSpot): boolean
	local views = EnemyObservationService:GetViews()
	for _, lean in { 0.5, 1 } do
		for _, point in PeekSpotService.LeanPoints(spot, lean) do
			for _, view in views do
				if EnemyObservationService.IsWithinCone(view, point, self.Config.ViewCone) then
					return true
				end
			end
		end
	end
	return false
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

--- Finds a corner behind somebody and stands upright behind it. Leaves rather than move in front of
--- anybody, and leaves rather than keep hunting once its budget of quiet attempts is spent.
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

	if not (player and spot) then
		npc.AttemptsLeft -= 1
		if npc.AttemptsLeft <= 0 then
			return "Despawn", npc
		end
		task.wait(npc.Config.RetryInterval)
		return "Seek", npc
	end

	npc:_placeAt(spot, player, 0)
	return "Lurk", npc, spot, player
end

--- Waits upright behind the corner for a moment where tipping out will not be watched happening.
--- Gives the corner up rather than wait forever: somebody who has turned round and parked facing it,
--- or one who has wandered up close, has made this corner useless, and the map has others.
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
		if (root.Position - spot.Stand).Magnitude < abandonDistance then
			return "Seek", npc
		end
		if os.clock() >= expiresAt then
			return "Seek", npc
		end

		if not npc:_isArcOnScreen(spot) then break end

		npc:_placeAt(spot, player, 0) -- keeps it aimed, so the lean opens already staring
		task.wait(POLL)
	end

	-- Re-checked here rather than only at spawn: a door has opened or somebody has moved since this
	-- corner was chosen, and tipping out of a spot that is no longer around a corner -- or no longer
	-- behind anybody -- is the failure this whole class is arranged to avoid.
	if not PeekSpotService:IsStillValid(spot, player, Watcher.GetFindOptions(npc.Config)) then
		return "Seek", npc
	end

	return "Peek", npc, spot, player
end

--- Tips out and holds the pose, and drops back the moment anybody has it. Being caught is the point
--- of the exercise and the end of it. Cut short mid-lean, the retreat carries on from whatever pose
--- it had reached, so a Watcher caught on the way out is one that never finishes standing up.
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

	return "Retreat", npc, spot, player, caught
end

--- Drops back behind the corner. The retreat plays out rather than cutting: it should read as
--- something pulling itself out of view, not as something switched off.
---
--- Caught, that is the end of it -- one glimpse per Watcher, and the corridor is empty when you get
--- there. Unseen, the pose was wasted on nobody, so it moves on to another corner until its budget of
--- them runs out.
local function retreat(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	caught: boolean
)
	if caught then
		-- Keep the reveal readable instead of snapping behind the corner on the same frame it is seen.
		task.wait(SEEN_HOLD_TIME)
		npc:_slide(spot, player, npc.Config.RetreatTime, 0)
		return "Despawn", npc
	end
	npc:_slide(spot, player, npc.Config.RetreatTime, 0)

	npc.AttemptsLeft -= 1
	if npc.AttemptsLeft <= 0 then
		return "Despawn", npc
	end
	return "Rest", npc
end

--- Waits out of sight before trying another corner. Found while it waits, it leaves: standing unseen
--- is the whole arrangement, and there is nothing to wait for once that is over.
local function rest(_changeState: StateMachine.ChangeState, npc: any)
	local expiresAt = os.clock() + randomBetween(npc.Config.RestTimeMin, npc.Config.RestTimeMax)

	while os.clock() < expiresAt do
		if npc:IsObserved() then
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
	-- sags out of whatever pose it is put in -- and a pose tipped forty-five degrees off vertical is
	-- one it sags out of immediately. The humanoid's own state machine would spend every frame
	-- fighting a root that is being placed by hand, and would call this a fall.
	self.Humanoid.EvaluateStateMachine = false
	self.RootPart.Anchored = true
	-- No nameplate. Every other enemy can afford one -- you are meant to have already seen those, and
	-- a Mimic arguably wants to look like something with a name over it. This one is a shape at the end
	-- of a corridor, and a caption floating above it answers the only question it exists to ask.
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.AttemptsLeft = math.random(self.Config.PeekCountMin, self.Config.PeekCountMax)
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
