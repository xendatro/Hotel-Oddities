--- Tuning for every enemy type. Keys match the ModuleScript names under `ServerStorage.Classes.Enemies`;
--- `Model` names the template under `ReplicatedStorage.Enemies`.
--- Everything past `WalkSpeed` is optional because an ambient enemy has none of it: the Ghost moves
--- itself, hunts nobody and hurts nobody, so it carries only `Model`, `WalkSpeed` and its own block.
export type EnemyConfig = {
	Model: string,

	-- Locomotion
	WalkSpeed: number,
	ChaseSpeed: number?,
	RepathInterval: number?, -- minimum time between moving-target path updates
	RepathDistance: number?, -- studs the goal must drift before its path is replaced
	AgentParams: { [string]: any }?,

	-- Idle / wander
	IdleTimeMin: number?,
	IdleTimeMax: number?,
	IdleNextState: string?, -- state `Idle` hands off to once its timer elapses
	WanderRadius: number?, -- studs around the spawn point a wander target may fall in

	-- Perception
	DetectionRange: number?, -- studs this enemy can acquire a target from
	GiveUpRange: number?, -- studs beyond which an acquired target stops being valid
	FieldOfView: number?, -- degrees of the enemy's own view cone; 360 sees all around
	RespectsSafeRooms: boolean?, -- when true, players inside a `Room` part are untargetable

	-- Combat
	Damage: number?,
	AttackRange: number?,
	AttackCooldown: number?,

	-- Chaser-specific
	LoseInterestTime: number?, -- seconds spent lingering at a lost target's last position
	SearchLookInterval: number?,

	-- Blind-specific
	InvestigateRange: number?, -- distance from the latest noise that counts as reaching it
	SearchTime: number?, -- seconds spent listening at the last sound before wandering again
	HearingAccurateRange: number?, -- noises inside this distance are localized exactly
	HearingErrorMaxDistance: number?, -- distance at which localization error reaches its maximum
	HearingErrorMax: number?, -- studs an estimate is offset at or beyond that distance

	-- Perception of being seen. Setting this at all is what marks an enemy as caring: `NPC:Start`
	-- reads it to decide whether this model should accept client view reports.
	ObservationRange: number?,

	-- Watcher-specific
	MinPeekDistance: number?, -- studs from the player a corner must be to be worth using
	MaxPeekDistance: number?,
	PeekArc: number?, -- degrees around the player's facing a corner must fall within; 360 for anywhere
	LeanTime: number?, -- seconds it takes to slide out from behind a corner
	RetreatTime: number?, -- and to pull back once it has been seen
	SeenGrace: number?, -- seconds it stays put after being looked at, before it pulls back
	HoldTimeMin: number?, -- seconds it will stay out for if nobody ever looks
	HoldTimeMax: number?,
	RestTimeMin: number?, -- seconds spent out of sight between one peek and the next
	RestTimeMax: number?,
	PeekCountMin: number?, -- peeks it performs before it leaves for good
	PeekCountMax: number?,
	PeekTilt: number?, -- degrees it leans past the corner at full extension
	RetryInterval: number?, -- seconds before looking again when the map offered no corner at all

	-- Mimic-specific. How it moves while stalking is not here: that runs on the stalked player's own
	-- client and is tuned in `ReplicatedStorage.Configs.MimicConfig`.
	StalkTimeMin: number?, -- seconds it will keep up the act before committing
	StalkTimeMax: number?,
	StrikeRange: number?, -- studs at which the act ends and the chase begins
	RetreatSlack: number?, -- studs a target may open up beyond its closest approach before it charges
	TurnAwayAngle: number?, -- degrees off it a target must face to count as turning their back
	TurnAwayGrace: number?, -- seconds of that before it charges
	GlanceAngle: number?, -- degrees it turns to look around while idle
	GlanceInterval: number?, -- seconds between those glances
	IdleJumpChance: number?, -- odds of a pointless hop per glance

	-- Ghost-specific. How it looks while it drifts is not here: that is rendered on every client
	-- and is tuned in `ReplicatedStorage.Configs.GhostConfig`.
	DriftSpeed: number?, -- studs/s it travels at; the same going up, down or through a wall
	MinGoalDistance: number?, -- studs a new goal should clear, so it does not hover in one corner

	-- Creep-specific
	LightRange: number?, -- studs around it in which tagged light models are disabled
	DespawnRange: number?, -- studs at which a nearby player makes it disappear

	-- Eye-specific. Damage is a rate rather than a hit: what costs you is how long you look and how
	-- squarely, so both of these are per second of looking. Where it points is not here at all: that
	-- is drawn per viewer on their own client, from `ReplicatedStorage.Configs.EyeConfig`.
	CenterDamage: number?, -- damage per second while it sits dead center on somebody's screen
	EdgeDamage: number?, -- and per second while it is merely on screen, past `FalloffAngle`
	FalloffAngle: number?, -- degrees off center at which the rate has fallen all the way to `EdgeDamage`
	FalloffExponent: number?, -- above 1 concentrates the damage into the middle of the screen
	Lifetime: number?, -- seconds it stays in the world before leaving of its own accord

	-- Shared by the anchored corridor enemies that travel the `MazeFloor` graph, Rush and Sisters
	SpawnPlayerDistance: number?, -- minimum distance from every player at which a route may begin
	KillRange: number?, -- distance from its swept movement path at which an exposed player dies
	RouteHeight: number?, -- studs above a tagged hallway floor part's center it travels at

	-- Rush-specific
	SpawnDelay: number?, -- warning time before the model enters the map
	WarningTime: number?, -- how far ahead of its arrival each route light turns red
	LightRouteRange: number?, -- lights this far from its route receive the warning

	-- Sisters-specific
	SideSpacing: number?, -- studs between the two of them, across the corridor
	LookAhead: number?, -- studs down the route they walk at; also how early they bend into a corner
	TurnSpeed: number?, -- degrees/s the pair's axis rotates, which is which side of it each walks on
	FormationTrim: number?, -- studs/s taken off a sister's walk per stud she is ahead of her sister
	CatchUpSpeed: number?, -- studs/s the trim will never push her past while she is catching up
	StuckTime: number?, -- seconds of getting nowhere down a leg before they give up and take a corner
	LoopMemory: number?, -- corners for which a node stays worth avoiding after they leave it
	LoopPenalty: number?, -- how strongly it is avoided at its freshest, against a straightness score of 1
	ForgetChance: number?, -- odds they simply never round the corner, rolled once per break in sight
	ForgetDelay: number?, -- seconds out of everybody's sight before that roll happens

	-- Stalker-specific
	FleeSpeed: number?, -- studs/s it retreats at once somebody has looked at it
	FollowDistance: number?, -- studs behind a target's back it keeps station at
	FollowSlack: number?, -- studs short of that it will settle for before it stops closing
	StrikeTimeMin: number?, -- seconds of going unlooked-at before it stops following and charges
	StrikeTimeMax: number?,
	RevealTurnTime: number?, -- seconds spent forcing the target's camera around to face it
	RevealHoldTime: number?, -- beat held on it before the charge begins
	FleeTime: number?, -- seconds of being watched without a break before it gives up and leaves

	-- Director. What `EnemyDirectorService` needs to decide whether to put one of these in the world.
	-- An enemy with no `SpawnWeight` is never rolled: the Ghost has its own areas, and the
	-- CeilingDweller comes out of an authored vent rather than off the floor.
	Budget: string?, -- "Pursuit" for anything that comes after you, "Presence" for anything that does not
	Cost: number?, -- what one of these spends out of that budget
	SpawnWeight: number?, -- how often it is rolled at all, against every other enemy in its budget
	DangerBias: number?, -- how strongly it prefers dangerous ground; 0 is anywhere, 3+ is only the worst of it
	MaxAlive: number?, -- hard cap regardless of what the budget could afford
	SpawnGrace: number?, -- seconds after appearing during which it cannot acquire anybody

	-- Temporary `/spawn` command
	CommandSpawnDistance: number?, -- optional override for how far away a hand-spawn lands
	CommandSpawnBehind: boolean?, -- put it behind the caller instead of in front, facing their back
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)

local ROOM_COST = { Room = math.huge } -- makes tagged safe rooms impassable to pathfinding

local EnemyConfigs: { [string]: EnemyConfig } = {
	Chaser = {
		Model = "Chaser",

		WalkSpeed = 10,
		ChaseSpeed = 19,
		RepathInterval = 0.5,
		RepathDistance = 8,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 6,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		-- A beat between one job and the next, not a rest. Idle used to be several seconds of standing
		-- still and it read as a prop waiting to be triggered; the walking is `Patrol` now.
		IdleTimeMin = 1,
		IdleTimeMax = 2.5,
		IdleNextState = "Patrol",
		WanderRadius = 70, -- only reached where a map has no tagged corridors to patrol

		DetectionRange = 60,
		GiveUpRange = 110,
		FieldOfView = 110,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		LoseInterestTime = 5,
		SearchLookInterval = 1,

		-- The bread and butter. Twenty seconds of runway between acquisition and contact, and doors
		-- are common enough that fleeing one is a real decision rather than a formality, so this is
		-- the enemy the hotel can afford to keep putting in front of you.
		Budget = "Pursuit",
		Cost = 3,
		SpawnWeight = 10,
		DangerBias = 1, -- linear: turns up in quiet corridors sometimes, in bad ones often
		MaxAlive = 2,
		SpawnGrace = 2,
	},

	Blind = {
		Model = "Blind",

		WalkSpeed = 8,
		ChaseSpeed = 13,
		RepathInterval = 0.25,
		RepathDistance = 4,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 6,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		IdleTimeMin = 1,
		IdleTimeMax = 2.5,
		IdleNextState = "Patrol",
		WanderRadius = 70,

		GiveUpRange = 100,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackCooldown = 1.5,

		InvestigateRange = 2.5,
		SearchTime = 4,
		HearingAccurateRange = 12,
		HearingErrorMaxDistance = 45,
		HearingErrorMax = 10,

		-- Cheap because it cannot catch anybody: 13 against a player's 16 means walking away from it
		-- always works. What it costs you is the right to make noise, which is a different kind of
		-- pressure entirely and one the hotel can carry a lot of.
		Budget = "Pursuit",
		Cost = 1,
		SpawnWeight = 8,
		DangerBias = 1,
		MaxAlive = 2,
		SpawnGrace = 2,
	},

	WeepingAngel = {
		Model = "Weeping Angel",

		WalkSpeed = 8,
		ChaseSpeed = 26,
		RepathInterval = 0.35,
		RepathDistance = 6,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 6,
			AgentCanJump = false,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		IdleTimeMin = 0.5,
		IdleTimeMax = 1.5,
		IdleNextState = "Idle", -- the angel never wanders; acquisition drives it out of Idle
		WanderRadius = 40,

		DetectionRange = 250, -- it always knows where you are
		GiveUpRange = 250,
		FieldOfView = 360, -- and it does not need to be facing you
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		ObservationRange = 200,

		-- Deliberately left out of the patrol rewrite: this one is a statue that waits, not something
		-- milling about, and its perception evaluator drives it straight out of `Idle` the moment
		-- anybody is inside its 250-stud reach. It is almost never idle in practice anyway.
		Budget = "Pursuit",
		Cost = 4,
		SpawnWeight = 2,
		DangerBias = 3.5, -- essentially only the worst regions of the hotel
		MaxAlive = 1,
		SpawnGrace = 2,
	},

	Mimic = {
		Model = "Mimic",

		WalkSpeed = 16, -- exactly a player's walk speed; anything else reads as fake at a glance
		ChaseSpeed = 23, -- once the act is over it stops pretending it has to obey player limits
		RepathInterval = 0.4,
		RepathDistance = 7,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 6,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		-- Its loiter is the act rather than a pause -- glancing about, the odd pointless hop -- so this
		-- one keeps its length. What follows it is a patrol now, which suits the disguise better than
		-- circling a spawn point ever did: a lost player walks corridors.
		IdleTimeMin = 2,
		IdleTimeMax = 6,
		IdleNextState = "Patrol",
		WanderRadius = 90,

		DetectionRange = 70,
		GiveUpRange = 120,
		FieldOfView = 130,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		LoseInterestTime = 5,
		SearchLookInterval = 1,

		-- It has all the patience in the world: locked on, it does nothing but copy you, so the act
		-- ends because you ended it. The timer is only there so a standoff cannot last forever.
		StalkTimeMin = 40,
		StalkTimeMax = 80,
		StrikeRange = 12,
		RetreatSlack = 14,
		TurnAwayAngle = 100,
		TurnAwayGrace = 0.45,
		GlanceAngle = 22,
		GlanceInterval = 0.9,
		IdleJumpChance = 0.15,

		-- An ambush rather than a chase: it commits from `StrikeRange` at a speed you cannot answer,
		-- so there is no runway and nothing to do about it once it drops the act. All the skill was
		-- in reading it earlier, which means its spawn rate is very nearly its kill rate. Expensive
		-- and rare on purpose.
		Budget = "Pursuit",
		Cost = 4,
		SpawnWeight = 4,
		DangerBias = 2,
		MaxAlive = 1,
		SpawnGrace = 3,
	},

	Stalker = {
		Model = "Stalker",

		WalkSpeed = 16, -- exactly a player's, so walking away from it is not a plan
		ChaseSpeed = 24, -- the charge. It has been holding this back the whole time.
		FleeSpeed = 32, -- and it runs from being seen harder than it ever hunted
		RepathInterval = 0.4,
		RepathDistance = 6,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 6,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		IdleTimeMin = 1,
		IdleTimeMax = 2.5, -- it is only ever idle between one attempt and the next
		IdleNextState = "Patrol",
		WanderRadius = 60,

		DetectionRange = 90,
		GiveUpRange = 150, -- it gives up on a follow late; walking away is not an escape
		FieldOfView = 360, -- it approaches from behind, so its own facing has nothing to do with it
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		LoseInterestTime = 4,
		SearchLookInterval = 1,

		ObservationRange = 250,

		-- Close. First person means there is no camera hanging back over your shoulder for it to have to
		-- clear, so the only thing distance would buy is time to react once you turn round -- and not
		-- having that is the point. Far enough back that it is not shoving you along the corridor.
		FollowDistance = 7,
		FollowSlack = 2.5,

		-- Long enough that being followed is a situation rather than an event, and you have to have
		-- gone a while without checking to earn it.
		StrikeTimeMin = 25,
		StrikeTimeMax = 40,
		RevealTurnTime = 0.35,
		RevealHoldTime = 0.4,

		FleeTime = 15, -- seconds of unbroken watching, not of running: see `Stalker.flee`

		-- The most expensive thing in the game, because being stalked *is* the encounter rather than
		-- a component of one. At cost 5 it crowds out nearly everything else, which is correct: a
		-- Stalker and a Chaser at the same time is two unrelated problems, and the answer to this one
		-- -- turn around and look -- stops working the moment you have a reason to be looking forward.
		Budget = "Pursuit",
		Cost = 5,
		SpawnWeight = 4,
		DangerBias = 2.5,
		MaxAlive = 1,
		SpawnGrace = 3,

		CommandSpawnDistance = 14, -- twice the follow distance, so a hand-spawn has to close in first
		CommandSpawnBehind = true, -- in front of the caller it would be seen and flee before it began
	},

	-- Ambient only. It never acquires, chases or attacks, so it has no perception or combat tuning
	-- at all -- what it does is drift between `GhostArea` volumes and never stop.
	Ghost = {
		Model = "Ghost",

		WalkSpeed = 0, -- its root is anchored; nothing about it moves through the humanoid
		DriftSpeed = 7, -- slower than a walk, so it always looks like it is being carried
		MinGoalDistance = 30,

		-- No `SpawnWeight`, so the director never rolls one. Its placement is the authored
		-- `GhostArea` volumes rather than anywhere on the floor, and that service already owns it.
	},

	-- Ambient only. It never targets, chases or attacks: it hides beside a corner, leans out, and
	-- retreats once it is looked at. It has no locomotion tuning because it never walks anywhere --
	-- it is placed, one corner at a time, by `PeekSpotService`.
	Watcher = {
		Model = "Watcher",

		WalkSpeed = 0, -- its root is anchored and moved by hand; nothing goes through the humanoid

		ObservationRange = 200,

		-- Down the far end of a corridor, not around the nearest doorway. Something close enough to
		-- make out properly is close enough to walk up to and find still standing there, and the
		-- whole effect depends on never getting a good look at it.
		-- 18 puts the average peek about 40 studs out, and about 60% of junctions can host one. Pushing
		-- the floor higher does buy distance, but it buys it out of corners that exist: at 30 the
		-- average was 53 studs and half the corridors in the hotel had nothing to offer at all, which
		-- reads as a Watcher that never turns up rather than one that keeps its distance.
		MinPeekDistance = 18,
		MaxPeekDistance = 85,
		-- A wide arc rather than a narrow one: it should be catchable at the edge of vision, not
		-- planted dead ahead. Directly behind a player is cut out, because nobody would ever see it.
		PeekArc = 200,

		-- Out slowly, back quickly. Easing out is what makes it feel like it chose to be seen;
		-- snapping back is what makes being caught feel like catching something. The grace in between
		-- is what stops it vanishing on the same frame it registers -- caught, it lets you have your
		-- look first.
		LeanTime = 1.1,
		SeenGrace = 0.5,
		RetreatTime = 0.3,

		HoldTimeMin = 4,
		HoldTimeMax = 9,
		RestTimeMin = 8,
		RestTimeMax = 20,
		PeekCountMin = 3,
		PeekCountMax = 6,
		PeekTilt = 10,
		RetryInterval = 1.5,

		-- Presence, and the one enemy the director does not place on the floor: a Watcher only works
		-- close and behind, so `WatcherService` keeps positioning it relative to a player and danger
		-- only decides how often one turns up.
		Budget = "Presence",
		Cost = 1,
		SpawnWeight = 8,
		DangerBias = 2,
		MaxAlive = 2,
	},

	-- Ambient only. It is a single anchored part with no Humanoid and disappears before a player
	-- can reach it.
	Creep = {
		Model = "Creep",

		WalkSpeed = 0, -- unused; Creep does not use the humanoid-backed NPC chassis
		LightRange = CreepConfig.LightRange,
		DespawnRange = 96,
		CommandSpawnDistance = 128,

		-- Cheap, common, and strongly drawn to the worst of the map, which is the combination that
		-- makes the danger field visible without anything having to announce it: hot regions put out
		-- their own lights. It costs a player nothing but nerve, so the hotel can be full of them.
		Budget = "Presence",
		Cost = 1,
		SpawnWeight = 10,
		DangerBias = 3,
		MaxAlive = 3,
	},

	-- Ambient only, and the only enemy that hurts you without doing anything. It has no locomotion,
	-- perception or combat tuning because it never moves, never picks anybody and never attacks: it
	-- stands where it was put and charges rent on being looked at.
	Eye = {
		Model = "Eye",

		WalkSpeed = 0, -- unused; Eye has no Humanoid to walk with

		-- Down a corridor rather than across the map. Far enough that it can be the thing you squint at
		-- to work out what it is, which is the mistake it is selling.
		ObservationRange = 150,
		RespectsSafeRooms = true,

		-- Staring straight at it kills a full-health player in about three seconds, and glancing at it
		-- costs a few points. The gap between those two numbers is the whole enemy: it has to be cheap
		-- to notice and ruinous to study.
		CenterDamage = 35,
		EdgeDamage = 3,
		-- 25 degrees is roughly a third of the way out to the edge of a default camera, so the punishing
		-- band is about the middle of the screen rather than the whole of it. Squared on top of that, so
		-- half a screen's worth of turning away sheds three quarters of the rate -- looking off it has to
		-- pay immediately, or the answer to it is to sprint past with your eyes shut rather than to look
		-- somewhere else.
		FalloffAngle = 25,
		FalloffExponent = 2,

		Lifetime = 60,

		-- Presence rather than Pursuit despite being lethal, because the line that matters for
		-- rationing is whether a thing comes after you. This one never moves, never picks anybody,
		-- and stops costing you the instant you look away -- so a Chaser and an Eye at once is one
		-- problem plus a hazard you can decline, where two Chasers is genuinely twice the pressure.
		-- Easily the most dangerous thing in its budget though, so it pays the most and is capped at
		-- one. Note what it does when it lands near a Creep: a glowing thing in a corridor whose
		-- lights just went out is a thing everybody looks at.
		Budget = "Presence",
		Cost = 3,
		SpawnWeight = 5,
		DangerBias = 3,
		MaxAlive = 1,
	},

	-- A fast, non-Humanoid corridor hazard. `RushService` derives its whole route from the parts
	-- tagged `MazeFloor` before it appears, which lets every light warning be scheduled against an
	-- exact arrival time.
	Rush = {
		Model = "Rush",

		WalkSpeed = 70,
		SpawnPlayerDistance = 100,
		SpawnDelay = 4,
		KillRange = 12,
		WarningTime = 15,
		LightRouteRange = 40,
		RouteHeight = 3,

		-- Cheaper than it looks. Fifteen seconds of warning and doors roughly every thirty seconds of
		-- walking make this survivable by anybody who understands what the red lights mean, and it
		-- clears its own route rather than staying in the world -- so what it spends, it gives back.
		Budget = "Pursuit",
		Cost = 3,
		SpawnWeight = 3,
		DangerBias = 3,
		MaxAlive = 1,
	},

	-- The other end of the same idea as Rush: two R15 rigs walking the same corridor graph, with none
	-- of the warning and none of the hurry. They touch no lights and never despawn, so what makes them
	-- survivable is only ever how long you have to see them and how near a door you were.
	Sisters = {
		Model = "Sister", -- one rig. The class takes the second sister from this one.

		-- Well under a player's 16: they can be outrun, walked around at a distance, and left behind
		-- entirely. Being caught by these is a mistake rather than a loss of a race.
		WalkSpeed = 5,
		SpawnPlayerDistance = 150, -- further out than Rush: unannounced, they have to be met at a distance
		KillRange = 12, -- covers `SideSpacing` and then some, so between them is not a gap to stand in
		RouteHeight = 0.5, -- feet on the floor: these are rigs standing on it, not a part flying over it

		SideSpacing = 7,

		-- How far down the route they walk at, and so how wide they take a corner: the point runs on
		-- into the next corridor this far before the junction, and they follow it round. Small enough
		-- that they hold the middle of a corridor rather than cutting across it, large enough that
		-- neither of them can ever reach it and stop -- a Humanoid that arrives drops out of its walk.
		LookAhead = 8,
		TurnSpeed = 90,

		-- What keeps them level. A sister a stud ahead of her sister walks at 4 rather than 5 until she
		-- is not, which is a correction you would have to be looking for to see. The cap only matters
		-- coming out of a corner, where the one on the outside has ground to make up.
		FormationTrim = 1,
		CatchUpSpeed = 8,

		StuckTime = 4, -- long enough that a scrape along a wall is not mistaken for being stuck on it

		-- Twelve corners of memory at a penalty of 1.2 -- more than the whole 0..1 range a straightness
		-- score can offer, so a corridor they have just left loses to any turn at all, and a corridor
		-- from a dozen corners ago costs them nothing. That is the difference between a pair that
		-- wanders the hotel and a pair pacing the same four corridors forever.
		LoopMemory = 12,
		LoopPenalty = 1.2,

		-- The cheapest thing in the Pursuit budget. At a walk speed of 5 against a player's 16 they
		-- can be outpaced, walked around at a distance and left behind entirely -- being caught by
		-- these is a mistake rather than a lost race, so the hotel can keep a pair about at all times.
		Budget = "Pursuit",
		Cost = 2,
		SpawnWeight = 2,
		DangerBias = 3,
		MaxAlive = 1,

		-- Seen, then not seen, and then -- occasionally -- never arriving. Rolled once each time they
		-- drop out of everybody's sight and stay out of it for `ForgetDelay`, which is the moment the
		-- question "are they still coming?" is actually live. One in five, because the other four
		-- times they do come round the corner and that is what makes the fifth land.
		ForgetChance = 0.2,
		ForgetDelay = 5,
	},
}

-- The vent-delivered enemy is mechanically a Chaser with its own authored model. A shallow clone is
-- sufficient because enemy configs are immutable; sharing the nested agent parameters keeps the two
-- variants on exactly the same pathfinding and safe-room rules.
local ceilingDwellerConfig = table.clone(EnemyConfigs.Chaser)
ceilingDwellerConfig.Model = "Ceiling Dweller"

-- It shares the Chaser's behaviour and none of its economics. Dropping out of an authored vent means
-- it commits from about ten studs rather than sixty, so where a Chaser gives you twenty seconds of
-- runway this gives you three -- there is no room to reach that is close enough. It costs more, only
-- one is ever about, and crucially it carries no `SpawnWeight`: the director never rolls one, because
-- `CeilingVentService` is what puts it in the world and the vents are placed by hand.
ceilingDwellerConfig.Cost = 4
ceilingDwellerConfig.MaxAlive = 1
ceilingDwellerConfig.SpawnWeight = nil
ceilingDwellerConfig.DangerBias = nil

EnemyConfigs.CeilingDweller = ceilingDwellerConfig

return EnemyConfigs
