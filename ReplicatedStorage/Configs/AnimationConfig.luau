--- Every authored animation an NPC can play, and which enemy plays which.
---
--- Shared, because `NpcAnimator` is shared: whichever machine simulates a rig is the one animating it,
--- and a `Mimic` handed to a player's client has to be able to read its own set from there.
---
--- An enemy with no entry here, or an entry that leaves a slot out, animates from the clips its rig
--- already carries under the stock `Animate` script. That is the default rather than a fallback: most
--- rigs are dressed with their own animation package in Studio, and only the ones whose movement has
--- to read as something other than walking need naming here.
---
--- A `Walk` or `Run` clip must be exactly one gait cycle -- one foot out, then the other, then back to
--- the pose it started in -- and may be authored at any pace. `NpcAnimator` reads its length and works
--- the playback rate out from there, so the feet stay on the floor at any walk speed without the clip
--- having to be made for one. An `Idle` clip is under no such rule: it plays at the pace it was made at.
---
--- Standing still is not a clip. An NPC that stops holds the pose it stopped walking in, which is why
--- almost nothing here names an `Idle` -- the two that do are a rig that never walks anywhere and so
--- has no such pose, and one that has to stand like a player rather than like an enemy.

export type AnimationSet = {
	Idle: number?, -- rarely wanted; standing still holds the walk pose unless this says otherwise
	UseRigIdle: boolean?, -- or holds the rig's own idle, for a rig whose stance must not be authored here
	Walk: number?,
	Run: number?,
	Attacks: { number }?, -- one is picked at random per swing; a single-entry list always plays
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

--- Keys match the ModuleScript names under `ServerStorage.Classes.Enemies`, the same as `EnemyConfigs`,
--- which is what reads these: an enemy's set is handed to its animator through its config.
local Sets: { [string]: AnimationSet } = {
	Chaser = {
		Walk = Animations.ChaserWalk,
		Run = Animations.ChaserRun,
		Attacks = { Animations.KnifeSwing },
	},

	-- A Chaser in every other respect, and deliberately not animated as one: what comes out of a vent
	-- should not move like the thing you have already learned to recognise down a corridor.
	CeilingDweller = {
		Walk = Animations.CursedWalk,
		Run = Animations.CursedWalk, -- the same crawl, played faster; there is no separate run clip
		Attacks = { Animations.CursedAttack },
	},

	-- Two punches rather than one, alternated at random, because this is the only enemy that can swing
	-- at you repeatedly without killing you outright often enough for a single clip to become a tell.
	Blind = {
		Walk = Animations.OldManWalk,
		Run = Animations.OldManWalk,
		Attacks = { Animations.Punch1, Animations.Punch2 },
	},

	Stalker = {
		Walk = Animations.SneakyWalk,
	},

	-- The one rig that must not hold a walk pose when it stops. Everything else about a Mimic is a
	-- player's own avatar and a player's own animation package, and a person standing in a corridor
	-- shifts their weight about -- frozen mid-stride it would give itself away across the room.
	Mimic = {
		UseRigIdle = true,
	},

	-- Anchored and placed on a corner rather than walked there, so it has never taken a step and has no
	-- pose to hold. What it stands in is the only thing it ever does.
	Watcher = {
		UseRigIdle = true,
	},

	-- Its root is anchored and moved by hand, so its Humanoid never reports running and it never leaves
	-- the idle slot. The slot is also all that is read: what a player sees is not this rig but the
	-- client-only avatar `GhostRenderService` builds over it, which takes the clip from here and plays
	-- it directly -- the ghost has one thing it does and never stops doing it.
	Ghost = {
		Idle = Animations.Fly,
	},
}

return {
	Animations = Animations,
	Sets = Sets,
}
