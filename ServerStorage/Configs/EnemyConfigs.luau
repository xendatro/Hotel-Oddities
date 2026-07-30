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

	-- Stalker-specific
	FleeSpeed: number?, -- studs/s it retreats at once somebody has looked at it
	FollowDistance: number?, -- studs behind a target's back it keeps station at
	FollowSlack: number?, -- studs short of that it will settle for before it stops closing
	StrikeTimeMin: number?, -- seconds of going unlooked-at before it stops following and charges
	StrikeTimeMax: number?,
	FleeTime: number?, -- seconds of being watched without a break before it gives up and leaves
	LurkTimeMin: number?, -- seconds it waits out of sight before starting again
	LurkTimeMax: number?,

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

		IdleTimeMin = 2,
		IdleTimeMax = 5,
		IdleNextState = "Wander",
		WanderRadius = 70,

		DetectionRange = 60,
		GiveUpRange = 110,
		FieldOfView = 110,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		LoseInterestTime = 5,
		SearchLookInterval = 1,
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

		IdleTimeMin = 2,
		IdleTimeMax = 6,
		IdleNextState = "Wander",
		WanderRadius = 90, -- it roams wide, like a player who is lost rather than a guard on a post

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
		IdleNextState = "Wander",
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

		FleeTime = 15, -- seconds of unbroken watching, not of running: see `Stalker.flee`
		LurkTimeMin = 10,
		LurkTimeMax = 20,

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
	},

	-- Ambient only. It is a single anchored part with no Humanoid and disappears before a player
	-- can reach it.
	Creep = {
		Model = "Creep",

		WalkSpeed = 0, -- unused; Creep does not use the humanoid-backed NPC chassis
		LightRange = CreepConfig.LightRange,
		DespawnRange = 96,
		CommandSpawnDistance = 128,
	},
}

return EnemyConfigs
