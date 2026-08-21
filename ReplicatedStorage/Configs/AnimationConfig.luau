export type AnimationSet = {
	Idle: number?,
	UseRigIdle: boolean?,
	RateMultiplier: number?,
	Walk: number?,
	Run: number?,
	Attacks: { number }?,
}

--- The raw asset ids, named for what the clip is rather than for who uses it.
local Animations = {
	ChaserWalk = 124403613879188,
	ChaserRun = 130456583127042,
	CursedWalk = 131708679301818,
	CursedAttack = 79774778049507,
	KnifeSwing = 88999892001033,
	OldManWalk = 100940673497574,
	Punch1 = 129975161300040,
	Punch2 = 101989469398162,
	SneakyWalk = 94066930953679,
	Fly = 124677133774216,
}

local Sets: { [string]: AnimationSet } = {
	Chaser = {
		Walk = Animations.ChaserWalk,
		Run = Animations.ChaserRun,
		Attacks = { Animations.KnifeSwing },
	},

	CeilingDweller = {
		Walk = Animations.CursedWalk,
		Run = Animations.CursedWalk,
		Attacks = { Animations.CursedAttack },
		RateMultiplier = 1.5,
	},

	Blind = {
		Walk = Animations.OldManWalk,
		Run = Animations.OldManWalk,
		Attacks = { Animations.Punch1, Animations.Punch2 },
	},

	Stalker = {
		Walk = Animations.SneakyWalk,
	},

	Mimic = {
		UseRigIdle = true,
	},

	Watcher = {
		UseRigIdle = true,
	},

	Ghost = {
		Idle = Animations.Fly,
	},
}

return {
	Animations = Animations,
	Sets = Sets,
}
