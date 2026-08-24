local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)

export type EnemyVariant = {
	Hair: string,
	SkinColor: Color3,
}

export type EnemyConfig = {
	Model: string,
	Animations: AnimationConfig.AnimationSet?,
	Variants: { EnemyVariant }?,

	-- Locomotion
	WalkSpeed: number,
	ChaseSpeed: number?,
	DirectPursuitDistance: number?,
	ClosePursuitDistance: number?,
	CommitDistance: number?,
	RepathInterval: number?,
	RepathDistance: number?,
	AgentParams: { [string]: any }?,

	-- Idle / wander
	IdleTimeMin: number?,
	IdleTimeMax: number?,
	IdleNextState: string?,
	WanderRadius: number?,

	-- Perception
	DetectionRange: number?,
	GiveUpRange: number?,
	FieldOfView: number?,
	RespectsSafeRooms: boolean?,

	-- Combat
	Damage: number?,
	AttackRange: number?,
	AttackCooldown: number?,
	Harmless: boolean?,

	-- Blind-specific
	InvestigateRange: number?,
	InvestigateSpeed: number?,
	AlertSpeed: number?,
	SearchTime: number?,
	AlertThreshold: number?,
	FrenzyThreshold: number?,
	DeterminationPerNoiseMin: number?,
	DeterminationPerNoiseMax: number?,
	DeterminationSilenceGrace: number?,
	DeterminationDecay: number?,
	TrailSilenceTime: number?,
	PursueRange: number?,
	PursuitGiveUpRange: number?,
	NoticeTurnTime: number?,
	OvershootRange: number?,
	OvershootMinimum: number?,

	ObservationRange: number?,
	ObservationHold: number?,

	-- Peeking
	SpawnPeeking: boolean?,
	MinPeekDistance: number?,
	MaxPeekDistance: number?,
	RearArc: number?,
	ViewCone: number?,
	PeekWaitTime: number?,
	LeanTime: number?,
	RetreatTime: number?,
	SeenHoldTime: number?,
	HoldTimeMin: number?,
	HoldTimeMax: number?,
	RestTimeMin: number?,
	RestTimeMax: number?,
	PeekCountMin: number?,
	PeekCountMax: number?,
	RetryInterval: number?,

	EngageRange: number?,
	RunawayRange: number?,
	RetreatSpeed: number?,
	CloseTime: number?,
	StrikeRange: number?,
	RetreatSlack: number?,
	TurnAwayAngle: number?,
	TurnAwayGrace: number?,
	BystanderRange: number?,
	BystanderNoticeTime: number?,
	BystanderTurnTime: number?,
	BystanderChaseTurnFraction: number?,
	AfkPatrolTimeMin: number?,
	AfkPatrolTimeMax: number?,
	AfkIdleTimeMin: number?,
	AfkIdleTimeMax: number?,
	AfkNoticeRange: number?,
	AfkNoticeTime: number?,
	AfkTurnTime: number?,
	AfkChaseTurnFraction: number?,
	AfkRoomBuffer: number?,
	AfkWallDistance: number?,
	AfkFaceWallChance: number?,
	AfkSettleTurnRate: number?,
	AfkDriftChance: number?,
	AfkDriftMin: number?,
	AfkDriftMax: number?,
	RunSpeed: number?,
	GlanceAngle: number?,
	GlanceInterval: number?,
	IdleJumpChance: number?,
	PatrolTurnAheadDistance: number?,

	DriftSpeed: number?,
	MinGoalDistance: number?,
	HoverHeight: number?,
	DriftMargin: number?,
	VanishDistance: number?,

	-- Creep-specific
	LightRange: number?,
	ConnectedHallwayLightRange: number?,
	DarkDistance: number?,
	DespawnRange: number?,

	HitDamage: number?,
	CenterDamage: number?,
	EdgeDamage: number?,
	FalloffAngle: number?,
	FalloffExponent: number?,
	-- Shared by the corridor hazards Chaos and Sisters
	SpawnPlayerDistance: number?,
	KillRange: number?,
	RouteHeight: number?,

	-- Chaos-specific
	SpawnDelay: number?,
	WarningTime: number?,
	LightPassDelay: number?,
	LightRouteRange: number?,
	WarnRedCullRange: number?,
	WarnHallwayCullRange: number?,
	WarnCullRecheckInterval: number?,

	-- Sisters-specific
	SideSpacing: number?,
	EndInset: number?,
	WalkOffDistance: number?,
	DespawnPastEnd: number?,
	ForgetChance: number?,
	ForgetDelay: number?,
	LightFlickerDuration: number?,
	LightFlickerInterval: number?,

	-- Stalker-specific
	FleeSpeed: number?,
	FollowDistance: number?,
	FollowSlack: number?,
	StalkTime: number?,
	RevealTurnTime: number?,
	RevealHoldTime: number?,
	FleeTime: number?,
	FleeCoverRange: number?,
	FleeCoverMinDistance: number?,

	DangerBias: number?,
	MaxAlive: number?,
	SpawnGrace: number?,

	-- Temporary `/spawn` command
	CommandSpawnDistance: number?,
	CommandSpawnBehind: boolean?,
}

local ROOM_COST = { Room = math.huge }

local EnemyConfigs: { [string]: EnemyConfig } = {
	Chaser = {
		Model = "Chaser",
		Animations = AnimationConfig.Sets.Chaser,
		Variants = {
			{ Hair = "BlackHair", SkinColor = Color3.fromRGB(231, 187, 148) },
			{ Hair = "BrownHair", SkinColor = Color3.fromRGB(147, 99, 62) },
		},

		WalkSpeed = 10,
		ChaseSpeed = 19,
		DirectPursuitDistance = 60,
		RepathInterval = 1.25,
		RepathDistance = 16,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 6,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		IdleTimeMin = 0,
		IdleTimeMax = 0,
		IdleNextState = "Patrol",
		WanderRadius = 70,

		DetectionRange = 60,
		GiveUpRange = 110,
		FieldOfView = 110,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		DangerBias = 1,
		MaxAlive = 2,
		SpawnGrace = 2,
	},

	Blind = {
		Model = "Blind",
		Animations = AnimationConfig.Sets.Blind,

		WalkSpeed = 8,
		ChaseSpeed = 21,
		RepathInterval = 0.25,
		RepathDistance = 4,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 6,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		IdleTimeMin = 0.15,
		IdleTimeMax = 0.4,
		IdleNextState = "Patrol",
		WanderRadius = 70,

		GiveUpRange = 100,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackCooldown = 1.5,

		InvestigateRange = 2.5,
		InvestigateSpeed = 10,
		AlertSpeed = 14,
		SearchTime = 0.2,
		AlertThreshold = 0.35,
		FrenzyThreshold = 0.75,
		DeterminationPerNoiseMin = 0.18,
		DeterminationPerNoiseMax = 0.4,
		DeterminationSilenceGrace = 0.35,
		DeterminationDecay = 0.45,
		TrailSilenceTime = 0.65,

		PursueRange = 17,
		PursuitGiveUpRange = 30,

		NoticeTurnTime = 0.25,

		OvershootRange = 12,
		OvershootMinimum = 1.5,

		DangerBias = 1,
		MaxAlive = 2,
		SpawnGrace = 2,
	},

	WeepingAngel = {
		Model = "Weeping Angel",

		WalkSpeed = 35,
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
		IdleNextState = "Patrol",
		WanderRadius = 40,

		DetectionRange = 250,
		GiveUpRange = 250,
		FieldOfView = 360,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		ObservationRange = 200,
		ObservationHold = 0.08,

		DangerBias = 3.5,
		MaxAlive = 1,
		SpawnGrace = 2,
	},

	Mimic = {
		Model = "Mimic",
		Animations = AnimationConfig.Sets.Mimic,

		WalkSpeed = 16,
		ChaseSpeed = 23,
		RepathInterval = 0.4,
		RepathDistance = 7,
		AgentParams = {
			AgentRadius = 2.5,
			AgentHeight = 3,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = ROOM_COST,
		},

		IdleTimeMin = 2,
		IdleTimeMax = 6,
		IdleNextState = "Patrol",
		WanderRadius = 90,

		DetectionRange = 80,
		GiveUpRange = 120,
		ChaseLoseSightTime = 4,
		FieldOfView = 360,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		EngageRange = 32,
		RunawayRange = 32,
		CloseTime = 0,
		StrikeRange = 16,
		RetreatSlack = 5,
		RetreatSpeed = 4,
		TurnAwayAngle = 100,
		TurnAwayGrace = 0.45,
		BystanderRange = 10,
		BystanderNoticeTime = 0.35,
		BystanderTurnTime = 1.25,
		BystanderChaseTurnFraction = 0.5,
		--- The ambient AFK cycle: patrol this long, stand around this long, repeat.
		--- Ranged so two Mimics on the map do not fall into lockstep.
		AfkPatrolTimeMin = 135,
		AfkPatrolTimeMax = 165,
		AfkIdleTimeMin = 25,
		AfkIdleTimeMax = 35,
		AfkNoticeRange = 18,
		AfkNoticeTime = 10,
		AfkTurnTime = 7.5,
		AfkChaseTurnFraction = 0.8,
		AfkRoomBuffer = 18,
		AfkWallDistance = 16,

		AfkFaceWallChance = 0.45,
		AfkSettleTurnRate = 2.2,
		--- Always step off the centre line, so it never stands exactly mid-hallway.
		AfkDriftChance = 1,
		AfkDriftMin = 2,
		AfkDriftMax = 5.5,

		RunSpeed = 18,
		GlanceAngle = 22,
		GlanceInterval = 0.9,
		IdleJumpChance = 0.15,
		PatrolTurnAheadDistance = 5,
		CommandSpawnDistance = 48,

		DangerBias = 2,
		MaxAlive = 2,
		SpawnGrace = 3,
	},

	Stalker = {
		Model = "Ceiling Dweller",
		Animations = AnimationConfig.Sets.Stalker,

		WalkSpeed = 16,
		ChaseSpeed = 24,
		FleeSpeed = 32,
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
		IdleTimeMax = 2.5,
		IdleNextState = "Patrol",
		WanderRadius = 60,

		DetectionRange = 90,
		GiveUpRange = 150,
		FieldOfView = 360,
		RespectsSafeRooms = true,

		Damage = math.huge,
		AttackRange = 4.5,
		AttackCooldown = 1.5,

		ObservationRange = 250,
		ObservationHold = 0.35,

		FollowDistance = 7,
		FollowSlack = 2.5,

		StalkTime = 10,
		RevealTurnTime = 0.25,
		RevealHoldTime = 0.4,

		FleeTime = 15,

		-- Every director spawn starts at a corner in watching mode. `/spawn stalker` ignores this
		-- and drops it behind you already hunting.
		SpawnPeeking = true,

		-- Keep it far enough away that a player cannot walk into it by accident. The upper end is
		-- pinned to DiscoveryConfig's Stalker sight range (160) so every peek it can make is one
		-- you can also earn the index card from.
		MinPeekDistance = 45,
		MaxPeekDistance = 80,
		RearArc = 300,

		ViewCone = 140,
		PeekWaitTime = 12,

		LeanTime = 1.1,
		RetreatTime = 0.3,
		-- Beat before it ducks back once you catch it. Keep it short or it reads as posing rather
		-- than being caught; 0 makes it start pulling back the same frame you look.
		SeenHoldTime = 0.4,

		-- One lean, held this long, then the danger roll. Raise PeekCount to get the old
		-- lean-hide-rest-repeat cycle back.
		HoldTimeMin = 10,
		HoldTimeMax = 10,
		RestTimeMin = 8,
		RestTimeMax = 20,
		PeekCountMin = 1,
		PeekCountMax = 1,
		RetryInterval = 1.5,

		FleeCoverRange = 70,
		FleeCoverMinDistance = 12,

		DangerBias = 2,
		MaxAlive = 2,
		SpawnGrace = 3,

		CommandSpawnDistance = 14,
		CommandSpawnBehind = true,
	},

	Ghost = {
		Model = "Ghost",
		Animations = AnimationConfig.Sets.Ghost,
		Harmless = true,

		WalkSpeed = 0,
		DriftSpeed = 7,
		MinGoalDistance = 30,

		HoverHeight = 5.5,
		DriftMargin = 10,
		VanishDistance = 65,
		SpawnInterval = 20,
		MaxAlive = 6,

		ModePeriod = 100,
		LurkChance = 0.5,
		LurkDangerBias = 2,
		LurkHeight = 3,
		LurkHiddenTime = 25,
	},

	Creep = {
		Model = "Creep",

		WalkSpeed = 0,
		LightRange = CreepConfig.LightRange,
		ConnectedHallwayLightRange = CreepConfig.ConnectedHallwayLightRange,
		DarkDistance = CreepConfig.DarkDistance,
		DespawnRange = 106,
		CommandSpawnDistance = 128,

		DangerBias = 3,
		MaxAlive = 3,
	},

	Eye = {
		Model = "Eye",
		Harmless = true,

		WalkSpeed = 0,

		ObservationRange = 150,
		RespectsSafeRooms = true,

		HitDamage = 20,
		CenterDamage = 35,
		EdgeDamage = 8,
		FalloffAngle = 45,
		FalloffExponent = 2,
		DangerBias = 3,
		MaxAlive = 1,
	},

	Chaos = {
		Model = "Chaos",

		WalkSpeed = 70,
		SpawnPlayerDistance = 100,
		SpawnDelay = 4,
		KillRange = 12,
		WarningTime = 15,
		LightPassDelay = 1.5,
		-- Lights within this many studs of Chaos's route turn red. Keep near hallway
		-- half-width so red means "this hallway, right here" (10-20).
		LightRouteRange = 13,
		-- Red route lights only turn on while a living player is within this many studs
		-- of the light. Keep well above a hallway span length so the tell reads from afar (150-300).
		WarnRedCullRange = 200,
		-- Hallway flicker + door chaos only runs while a player is within this many studs of the
		-- closest point on the span. The expensive effect, so it can sit tighter (100-200).
		WarnHallwayCullRange = 150,
		-- Seconds between re-checks while a scheduled warning waits for a player to come into range.
		WarnCullRecheckInterval = 1,
		RouteHeight = 3,

		DangerBias = 3,
		MaxAlive = 1,
	},

	Sisters = {
		Model = "Sister",

		WalkSpeed = 5,
		SpawnPlayerDistance = 150,
		KillRange = 12,
		RouteHeight = 0.5,

		SideSpacing = 5.5,
		EndInset = 2,
		WalkOffDistance = 10,
		DespawnPastEnd = 6,

		DangerBias = 3,
		MaxAlive = 1,

		ForgetChance = 0.2,
		ForgetDelay = 5,

		LightFlickerDuration = 0.15,
		LightFlickerInterval = 0.7,
	},
}

local ceilingDwellerConfig = table.clone(EnemyConfigs.Chaser)
ceilingDwellerConfig.Model = "Ceiling Dweller"
ceilingDwellerConfig.Animations = AnimationConfig.Sets.CeilingDweller
ceilingDwellerConfig.Variants = nil

ceilingDwellerConfig.MaxAlive = 1
ceilingDwellerConfig.DangerBias = nil
ceilingDwellerConfig.RunSpeed = 25
ceilingDwellerConfig.ChaseSpeed = 22
ceilingDwellerConfig.AgentParams = table.clone(EnemyConfigs.Chaser.AgentParams :: any)
ceilingDwellerConfig.AgentParams.AgentRadius = 3.25
-- A ceiling dweller can acquire anyone around it after its first target reaches safety.
ceilingDwellerConfig.FieldOfView = 360
ceilingDwellerConfig.ObservationRange = 300
ceilingDwellerConfig.ObservationHold = 0.08

EnemyConfigs.CeilingDweller = ceilingDwellerConfig

return EnemyConfigs
