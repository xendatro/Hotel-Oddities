local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)

export type EnemyConfig = {
	Model: string,
	Animations: AnimationConfig.AnimationSet?,

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
	HearingAccurateRange: number?,
	HearingErrorMaxDistance: number?,
	HearingErrorMax: number?,
	HearingErrorMinScale: number?,
	AlertThreshold: number?,
	FrenzyThreshold: number?,
	DeterminationPerNoiseMin: number?,
	DeterminationPerNoiseMax: number?,
	DeterminationSilenceGrace: number?,
	DeterminationDecay: number?,
	TrailSilenceTime: number?,
	PursueRange: number?,
	PursuitGiveUpRange: number?,
	HearingCooldown: number?,
	PursuitHearingCooldown: number?,
	NoticeTurnTime: number?,
	OvershootRange: number?,
	OvershootMinimum: number?,

	ObservationRange: number?,
	ObservationHold: number?,

	-- Watcher-specific
	MinPeekDistance: number?,
	MaxPeekDistance: number?,
	RearArc: number?,
	ViewCone: number?,
	PeekWaitTime: number?,
	LeanTime: number?,
	RetreatTime: number?,
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
	AfkAmbientChance: number?,
	AfkAmbientRollMin: number?,
	AfkAmbientRollMax: number?,
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

	-- Creep-specific
	LightRange: number?,
	ConnectedHallwayLightRange: number?,
	DespawnRange: number?,

	HitDamage: number?,
	CenterDamage: number?,
	EdgeDamage: number?,
	FalloffAngle: number?,
	FalloffExponent: number?,
	Lifetime: number?,

	-- Shared by the corridor hazards Chaos and Sisters
	SpawnPlayerDistance: number?,
	KillRange: number?,
	RouteHeight: number?,

	-- Chaos-specific
	SpawnDelay: number?,
	WarningTime: number?,
	LightRouteRange: number?,

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
	StrikeTimeMin: number?,
	StrikeTimeMax: number?,
	RevealTurnTime: number?,
	RevealHoldTime: number?,
	FleeTime: number?,
	FleeCoverRange: number?,
	FleeCoverMinDistance: number?,

	Budget: string?,
	Cost: number?,
	SpawnWeight: number?,
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

		Budget = "Pursuit",
		Cost = 3,
		SpawnWeight = 10,
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
		SearchTime = 1,
		HearingAccurateRange = 12,
		HearingErrorMaxDistance = 45,
		HearingErrorMax = 10,
		HearingErrorMinScale = 0.65,

		AlertThreshold = 0.35,
		FrenzyThreshold = 0.75,
		DeterminationPerNoiseMin = 0.18,
		DeterminationPerNoiseMax = 0.4,
		DeterminationSilenceGrace = 0.35,
		DeterminationDecay = 0.45,
		TrailSilenceTime = 0.65,

		PursueRange = 17,
		PursuitGiveUpRange = 30,

		HearingCooldown = 1,
		PursuitHearingCooldown = 0.4,

		NoticeTurnTime = 0.25,

		OvershootRange = 7,
		OvershootMinimum = 1.5,

		Budget = "Pursuit",
		Cost = 1,
		SpawnWeight = 8,
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

		Budget = "Pursuit",
		Cost = 4,
		SpawnWeight = 2,
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
		AfkAmbientChance = 0.25,
		AfkAmbientRollMin = 6,
		AfkAmbientRollMax = 12,
		AfkNoticeRange = 18,
		AfkNoticeTime = 10,
		AfkTurnTime = 7.5,
		AfkChaseTurnFraction = 0.8,
		AfkRoomBuffer = 18,
		AfkWallDistance = 16,

		AfkFaceWallChance = 0.45,
		AfkSettleTurnRate = 2.2,
		AfkDriftChance = 0.6,
		AfkDriftMin = 2,
		AfkDriftMax = 5.5,

		RunSpeed = 18,
		GlanceAngle = 22,
		GlanceInterval = 0.9,
		IdleJumpChance = 0.15,
		PatrolTurnAheadDistance = 5,
		CommandSpawnDistance = 48,

		Budget = "Pursuit",
		Cost = 4,
		SpawnWeight = 4,
		DangerBias = 2,
		MaxAlive = 1,
		SpawnGrace = 3,
	},

	Stalker = {
		Model = "Stalker",
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

		FollowDistance = 7,
		FollowSlack = 2.5,

		StrikeTimeMin = 25,
		StrikeTimeMax = 40,
		RevealTurnTime = 0.35,
		RevealHoldTime = 0.4,

		FleeTime = 15,

		FleeCoverRange = 70,
		FleeCoverMinDistance = 12,

		Budget = "Pursuit",
		Cost = 5,
		SpawnWeight = 4,
		DangerBias = 2.5,
		MaxAlive = 1,
		SpawnGrace = 3,

		CommandSpawnDistance = 14,
		CommandSpawnBehind = true,
	},

	Ghost = {
		Model = "Ghost",
		Animations = AnimationConfig.Sets.Ghost,

		WalkSpeed = 0,
		DriftSpeed = 7,
		MinGoalDistance = 30,

		HoverHeight = 5.5,
		DriftMargin = 10,
		SpawnInterval = 20,
		MaxAlive = 3,

	},

	Watcher = {
		Model = "Watcher",
		Animations = AnimationConfig.Sets.Watcher,

		WalkSpeed = 0,
		Harmless = true,

		ObservationRange = 200,
		ObservationHold = 0.35,

		-- Keep the Watcher far enough away that a player cannot walk into it by accident.
		MinPeekDistance = 60,
		MaxPeekDistance = 120,
		RearArc = 300,

		ViewCone = 140,
		PeekWaitTime = 12,

		LeanTime = 1.1,
		RetreatTime = 0.3,

		HoldTimeMin = 4,
		HoldTimeMax = 9,
		RestTimeMin = 8,
		RestTimeMax = 20,
		PeekCountMin = 3,
		PeekCountMax = 6,
		RetryInterval = 1.5,

		Budget = "Presence",
		Cost = 1,
		SpawnWeight = 8,
		DangerBias = 2,
		MaxAlive = 2,
	},

	Creep = {
		Model = "Creep",

		WalkSpeed = 0,
		LightRange = CreepConfig.LightRange,
		ConnectedHallwayLightRange = CreepConfig.ConnectedHallwayLightRange,
		DespawnRange = 96,
		CommandSpawnDistance = 128,

		Budget = "Presence",
		Cost = 1,
		SpawnWeight = 10,
		DangerBias = 3,
		MaxAlive = 3,
	},

	Eye = {
		Model = "Eye",

		WalkSpeed = 0,

		ObservationRange = 150,
		RespectsSafeRooms = true,

		HitDamage = 20,
		CenterDamage = 35,
		EdgeDamage = 8,
		FalloffAngle = 45,
		FalloffExponent = 2,

		Lifetime = 60,

		Budget = "Presence",
		Cost = 3,
		SpawnWeight = 5,
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
		LightRouteRange = 40,
		RouteHeight = 3,

		Budget = "Pursuit",
		Cost = 3,
		SpawnWeight = 3,
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

		Budget = "Pursuit",
		Cost = 2,
		SpawnWeight = 2,
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

ceilingDwellerConfig.Cost = 4
ceilingDwellerConfig.MaxAlive = 1
ceilingDwellerConfig.SpawnWeight = nil
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
