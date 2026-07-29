--- Tuning for every enemy type. Keys match the ModuleScript names under `ServerStorage.Classes.Enemies`;
--- `Model` names the template under `ReplicatedStorage.Enemies`.
export type EnemyConfig = {
	Model: string,

	-- Locomotion
	WalkSpeed: number,
	ChaseSpeed: number,
	RepathInterval: number, -- minimum time between moving-target path updates
	RepathDistance: number, -- studs the goal must drift before its path is replaced
	AgentParams: { [string]: any },

	-- Idle / wander
	IdleTimeMin: number,
	IdleTimeMax: number,
	IdleNextState: string, -- state `Idle` hands off to once its timer elapses
	WanderRadius: number, -- studs around the spawn point a wander target may fall in

	-- Perception
	DetectionRange: number, -- studs this enemy can acquire a target from
	GiveUpRange: number, -- studs beyond which an acquired target stops being valid
	FieldOfView: number, -- degrees of the enemy's own view cone; 360 sees all around
	RespectsSafeRooms: boolean, -- when true, players inside a `Room` part are untargetable

	-- Combat
	Damage: number,
	AttackRange: number,
	AttackCooldown: number,

	-- Chaser-specific
	LoseInterestTime: number?, -- seconds spent lingering at a lost target's last position
	SearchLookInterval: number?,

	-- Weeping Angel-specific
	ObservationRange: number?,

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
}

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
}

return EnemyConfigs
