--- @class Watcher
--- Ambient dread with nothing behind it. It has no target, no path, no attack and no opinion about
--- where anybody is going: it waits out of sight beside a distant corner, leans far enough past it to
--- be caught at the edge of your vision, and is gone once you actually look at it.
---
--- Where it stands is the entire trick, and that question belongs to `PeekSpotService`, which hands
--- back a pair of floor positions either side of some corner near a player -- one blind to them, one
--- seen. This class only performs: park on the blind one, slide onto the seen one, hold the pose
--- while nobody is looking, and leave once somebody is.
---
--- Being seen is terminal, and being seen doing anything other than posing is what it exists to
--- avoid. Moving between corners is a teleport, and a teleport somebody watches reads as a bug rather
--- than a fright -- so every state checks first, and a Watcher that is being looked at when it wanted
--- to be somewhere else despawns instead of moving. The effect is that you never get a second look at
--- the same one, which is the point.
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
local REST_POLL = 0.1 -- seconds between checks that it is still unseen while waiting between peeks
local PEEK_VIEW_CONE = 100 -- degrees of camera view that count as actively watching the peek point

local Watcher = NPC.extend("Watcher")

local function isWithinView(eye: Vector3, look: Vector3, point: Vector3): boolean
	local offset = point - eye
	if offset.Magnitude < 1e-3 or look.Magnitude < 1e-3 then return true end
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(look.Unit), -1, 1))) <= PEEK_VIEW_CONE / 2
end

-- A Watcher must not start its slide while somebody is already watching the place it will appear.
-- `IsObserved` cannot answer that while the rig is still behind the corner, so use the reported camera
-- view and a server raycast against the actual peek position instead.
local function isPeekWatched(floorPosition: Vector3): boolean
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

	local point = floorPosition + Vector3.yAxis * (ROOT_HEIGHT + 1.5)
	for _, player in Players:GetPlayers() do
		local eye, look = EnemyObservationService:GetView(player)
		if eye and look and isWithinView(eye, look, point) then
			local direction = point - eye
			if workspace:Raycast(eye, direction, params) == nil then return true end
		end
	end
	return false
end

local function randomBetween(minimum: number, maximum: number): number
	return math.random() * (maximum - minimum) + minimum
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

	local character = player.Character
	local target = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
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
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and humanoid and humanoid.Health > 0 then
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
	if not (player and player.Character) then
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
	return "Peek", npc, spot, player
end

--- Leans out and holds. Looked at, it waits a beat and then goes for good; ignored, it tucks back to
--- try somewhere else.
local function peek(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	-- The model is hidden at this point, so a sight report cannot tell us whether the player is already
	-- watching the place it is about to occupy. Stay tucked away and choose again until that location
	-- is clear; emerging into a camera that is fixed on the corner defeats the whole effect.
	if isPeekWatched(spot.Peek) then
		npc:_placeAt(spot.Hide, spot, player, 0)
		task.wait(npc.Config.RetryInterval)
		return "Seek", npc
	end

	local function isCaught()
		return npc:IsObserved()
	end

	local unseen = npc:_slide(spot, player, npc.Config.LeanTime, true, isCaught)
		and npc:_hold(spot, player, randomBetween(npc.Config.HoldTimeMin, npc.Config.HoldTimeMax), isCaught)

	if not unseen then
		-- Caught. It does not bolt on the frame it is spotted: a figure that vanishes the instant you
		-- focus on it is a flicker, and a flicker is easy to talk yourself out of having seen. No
		-- predicate here on purpose -- once seen it commits to being seen for a moment.
		npc:_hold(spot, player, npc.Config.SeenGrace)
		return "Flee", npc, spot, player
	end

	npc.PeeksLeft -= 1
	if npc.PeeksLeft <= 0 then
		return "Flee", npc, spot, player
	end
	return "Rest", npc, spot, player
end

--- Pulls back behind the corner and is gone. The retreat still plays: it should look like something
--- stepping out of view, not something switched off.
local function flee(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	npc:_slide(spot, player, npc.Config.RetreatTime, false)
	return "Despawn", npc
end

--- Tucks back behind the corner and waits there for its next go. Found in the meantime, it leaves --
--- waiting out of sight is the whole arrangement, and there is nothing to wait for once that is over.
local function rest(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	npc:_slide(spot, player, npc.Config.RetreatTime, false)

	local expiresAt = os.clock() + randomBetween(npc.Config.RestTimeMin, npc.Config.RestTimeMax)
	while os.clock() < expiresAt do
		if npc:IsObserved() then
			return "Despawn", npc
		end
		task.wait(REST_POLL)
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
		Peek = peek,
		Rest = rest,
		Flee = flee,
		Despawn = NPC.SharedStates.Despawn,
	}, {
		-- Mapped to nothing on purpose: it does not fight, so a bear trap or a paper ball has
		-- nothing of its behaviour to interrupt, and an unmapped reason warns every time one lands.
		Impact = {},
	}, {}, "Seek", self)
end

return Watcher
