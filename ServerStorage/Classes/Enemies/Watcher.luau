--- @class Watcher
--- Ambient dread with nothing behind it. It has no target, no path, no attack and no opinion about
--- where anybody is going: it waits out of sight beside a distant corner, leans far enough past it to
--- be caught at the edge of your vision, and is gone once you actually look at it.
---
--- Where it stands is the entire trick, and that question belongs to `PeekSpotService`, which hands
--- back a pair of floor positions either side of some corner near a player -- one blind to them, one
--- seen. This class only performs: lurk on the blind one until they are not staring at the place it
--- would appear, slide onto the seen one, hold the pose, and tuck back once somebody has had their
--- look.
---
--- The timing rule that shapes everything here is that it must never be *watched arriving*, and must
--- always be *findable once arrived*. Those pull in opposite directions, and the resolution is that
--- only the moment of emerging is gated. It waits for the peek point to fall outside the narrow cone
--- somebody is actually looking down -- not merely outside their screen, which in a corridor is
--- almost never true and is what makes a Watcher that stands behind a corner forever -- and once it
--- has begun leaning it commits. Being seen mid-lean is the intended outcome. Cutting the lean short
--- on the first sight report turns the one moment this thing exists for into a flicker, and a flicker
--- is easy to talk yourself out of having seen.
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

local function isWithinCone(eye: Vector3, look: Vector3, point: Vector3, cone: number): boolean
	local offset = point - eye
	if offset.Magnitude < 1e-3 or look.Magnitude < 1e-3 then return true end
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(look.Unit), -1, 1))) <= cone / 2
end

--- Whether somebody is looking straight down the barrel at the place a Watcher is about to occupy.
---
--- `IsObserved` cannot answer this while the rig is still behind the corner -- there is nothing on
--- screen to report -- so it is asked of the reported camera and a server raycast against the peek
--- position instead.
---
--- The cone is deliberately narrow. It is not "would this be on their screen": a peek point down the
--- corridor somebody is walking along is on their screen the entire time, and gating emergence on
--- that leaves a Watcher tucked behind a corner for its whole life. It is "are they looking at it",
--- which leaves the edges of vision open -- which is exactly where this wants to appear.
local function isPeekWatched(config, floorPosition: Vector3): boolean
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

	local cone = config.ActiveLookAngle
	for _, player in Players:GetPlayers() do
		local eye, look = EnemyObservationService:GetView(player)
		if not (eye and look) then continue end

		for _, height in EMERGENCE_HEIGHTS do
			local point = floorPosition + Vector3.yAxis * height
			if isWithinCone(eye, look, point, cone) and workspace:Raycast(eye, point - eye, params) == nil then
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
		Arc = config.PeekArc,
	}
end

--- Puts the rig on `floorPosition`, staring at `player`, leaned `lean` of the way out -- 0 tucked
--- back behind the corner, 1 fully committed. The tilt goes along the spot's lateral axis, so it
--- always leans past the corner rather than into it.
function Watcher:_placeAt(floorPosition: Vector3, spot: PeekSpotService.PeekSpot, player: Player, lean: number)
	local position = floorPosition + Vector3.new(0, ROOT_HEIGHT, 0)

	local target = getAliveRoot(player)
	local lookAt = if target
		then Vector3.new(target.Position.X, position.Y, target.Position.Z)
		else position + self.RootPart.CFrame.LookVector
	if (lookAt - position).Magnitude < 1e-3 then
		lookAt = position + self.RootPart.CFrame.LookVector
	end

	local tilt = math.tan(math.rad(self.Config.PeekTilt * lean))
	self.RootPart.CFrame = CFrame.lookAt(position, lookAt, (Vector3.yAxis + spot.Lateral * tilt).Unit)
end

--- Slides the rig between the two sides of `spot` over `duration`, leaning as it goes. Returns false
--- if `shouldStop` cut the slide short, which leaves the rig wherever it had got to.
function Watcher:_slide(
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	towardsPeek: boolean,
	shouldStop: (() -> boolean)?
): boolean
	local from = if towardsPeek then spot.Hide else spot.Peek
	local to = if towardsPeek then spot.Peek else spot.Hide
	local startedAt = os.clock()

	while true do
		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		self:_placeAt(from:Lerp(to, alpha), spot, player, if towardsPeek then alpha else 1 - alpha)
		if alpha >= 1 then return true end
		if shouldStop and shouldStop() then return false end
		RunService.Heartbeat:Wait()
	end
end

--- Holds the pose for `duration`, still staring. Returns false if `shouldStop` cut it short. Passing
--- no predicate holds the pose come what may, which is what the grace after being spotted needs --
--- gating that on not being looked at would end it on the frame it began.
function Watcher:_hold(
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	shouldStop: (() -> boolean)?
): boolean
	local expiresAt = os.clock() + duration

	while os.clock() < expiresAt do
		if shouldStop and shouldStop() then return false end
		self:_placeAt(spot.Peek, spot, player, 1) -- keeps staring while they move
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

--- Finds a corner and parks on its blind side. Leaves rather than move in front of anybody, and
--- leaves rather than stand around in the open once its budget of quiet peeks is spent.
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

	npc:_placeAt(spot.Hide, spot, player, 0)
	return "Lurk", npc, spot, player
end

--- Waits behind the corner for a moment where emerging will not be watched happening. Gives the
--- corner up rather than wait forever: somebody parked facing it, or one who has wandered up close
--- enough to get a proper look, has made this corner useless, and there are others.
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

		if not isPeekWatched(npc.Config, spot.Peek) then break end

		npc:_placeAt(spot.Hide, spot, player, 0) -- keeps it aimed, so the lean opens already staring
		task.wait(POLL)
	end

	-- Re-checked here rather than only at spawn: a door has opened or somebody has moved since this
	-- corner was chosen, and leaning out of a spot that is no longer around a corner is the failure
	-- this whole class is arranged to avoid.
	if not PeekSpotService:IsStillValid(spot, player) then
		return "Seek", npc
	end

	return "Peek", npc, spot, player
end

--- Leans out and holds the pose. Committed once begun: being seen is what it leaned out for.
local function peek(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	npc:_slide(spot, player, npc.Config.LeanTime, true)

	local function isCaught()
		return npc:IsObserved()
	end

	local caught = not npc:_hold(spot, player, randomBetween(npc.Config.HoldTimeMin, npc.Config.HoldTimeMax), isCaught)
	if caught then
		-- It does not bolt on the frame it is spotted. No predicate here on purpose -- once seen it
		-- commits to being seen, and lets you have your look before it goes.
		npc:_hold(spot, player, npc.Config.SeenGrace)
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
	npc:_slide(spot, player, npc.Config.RetreatTime, false)

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
--- @param player Player? -- who that corner was found for
function Watcher.new(model: Model, config, spot: PeekSpotService.PeekSpot?, player: Player?)
	local self = NPC.new(model, config, Watcher)
	self.Spot = spot
	self.Audience = player
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
