--- What earns a player knowledge of an enemy. Keys match `EnemyConfigs`, which is the same id the
--- index lists an entry under and the same id a death is reported as -- so a rule, a spawn and a
--- card all name the enemy the same way and nothing has to be translated between them.
---
--- How the knowledge is *drawn* is not here: that is the index's business and lives in
--- `ReplicatedStorage.Configs.IndexConfig`. This file only decides what fills the bar.
---
--- There are four ways to earn progress, and most enemies use one or two of them:
---
--- * **Sight** -- looking at the thing, for a while, from somewhere it can actually be made out.
---   The default, and correct for anything whose encounter is "you saw it down a corridor".
--- * **Proximity** -- being near it, seen or not. For the enemies there is nothing to look at:
---   a Creep is an invisible slab carrying two particle emitters, and what a player meets is the
---   lights going out around them rather than a model.
--- * **Event** -- a moment the enemy itself declares by calling `EnemyDiscoveryService:Grant`. For
---   the enemies whose whole design is that you do not know what they are until they show you.
--- * **Death** -- it killed you. Always available, always the largest single gain, and the only one
---   the player is shown an animation for.
---
--- Sight is deliberately switched off for the ambush enemies. A Mimic seen across a lobby is a
--- player as far as anyone knows, and unlocking its card for having looked at it would put the word
--- "Mimic" in the index before the disguise had ever worked on anybody -- the index would be
--- spoiling the enemy it is describing. Same for the Stalker, which is only ever a Stalker at the
--- moment it stops following and turns you around. Those two learn you nothing until they commit.

export type SightRule = {
	Range: number, -- studs past which it is too far away to make out
	Angle: number, -- degrees off the middle of the screen it may sit and still count as looked at
	GainPerSecond: number,
	MinDwell: number, -- seconds of unbroken looking before any of it counts at all
}

export type ProximityRule = {
	Range: number,
	GainPerSecond: number,
}

export type DiscoveryRule = {
	Sight: SightRule | false | nil, -- false disables sighting; nil takes the default
	Proximity: ProximityRule?,
	Event: number?, -- granted per `Grant(player, id, "Event")` call
	Death: number?, -- overrides `Defaults.Death`
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)

local DiscoveryConfig = {}

--- How often the sweep runs. Four times a second: this is "did you get a good look at it", not the
--- frame-accurate answer a Stalker needs to decide whether to flee, and asking more often would cost
--- a raycast per enemy per player for an answer that cannot meaningfully change that fast.
DiscoveryConfig.SweepInterval = 0.25

--- How far progress must move before the client is told about it again. Saving is not what this
--- rations -- a save only writes into the table ProfileService already holds in memory, and the
--- datastore write is on its own timer -- it is the remote call. A sighting climbing at 0.055/s
--- would otherwise fire one four times a second per enemy on screen, to move a bar by a hundredth.
--- Progress reaching 1 always replicates regardless, because completing an entry is worth saying
--- immediately.
DiscoveryConfig.ReplicateStep = 0.05

DiscoveryConfig.Defaults = {
	--- 140 studs covers the length of the corridors these are met in without letting a shape three
	--- junctions away count. The angle is a little tighter than a default camera's half-width, so
	--- something caught at the very edge of the screen is not the same as having looked at it.
	Sight = {
		Range = 140,
		Angle = 45,
		--- About forty seconds of cumulative looking to fill an entry from nothing -- roughly a run's
		--- worth of repeated encounters rather than a single long stare. That is a lot, deliberately:
		--- sighting is the slow trickle that eventually completes an entry for a player who never dies
		--- to the thing, not the main way anybody learns anything. Every rate below is scaled to this
		--- one, so halving it here halves the lot.
		GainPerSecond = 0.025,
		--- Three quarters of a second, so a corridor swept past at a run does not silently fill the
		--- index. Being somewhere an enemy happened to be on screen is not the same as having noticed
		--- it, and at a sprint a doorway is on screen for less than this.
		MinDwell = 0.75,
	} :: SightRule,

	--- Three deaths to a thing and you have its entry. Big enough that the reveal animation always
	--- has several words to uncover, which is what makes dying to something new feel like it paid.
	Death = 0.34,
}

DiscoveryConfig.Rules = {
	-- The plain pursuit enemies. You meet these by seeing them coming, and you learn the rest of it
	-- the hard way.
	Chaser = {},
	CeilingDweller = {
		-- It drops out of a vent about ten studs away and commits immediately; there is no seeing one
		-- down a corridor. Nearly everything anybody knows about this one was learned by dying to it.
		Sight = { Range = 60, Angle = 55, GainPerSecond = 0.023, MinDwell = 0.4 },
		Death = 0.45,
	},
	Blind = {},
	WeepingAngel = {
		-- Looking at it is the entire interaction, and it is a statue every time you do, so a player
		-- gets a long clear look at this one whether they want it or not.
		Sight = { Range = 200, Angle = 45, GainPerSecond = 0.032, MinDwell = 0.5 },
	},
	Sisters = {
		-- Met at 150 studs and slow enough to study on the way past.
		Sight = { Range = 180, Angle = 45, GainPerSecond = 0.028, MinDwell = 0.7 },
	},

	-- The ambushes. Nothing is learned by looking, because looking is exactly what they defeat.
	Mimic = {
		Sight = false,
		Event = 0.5, -- it dropped the act in front of you, which is the only time you know what it is
		Death = 0.5,
	},
	Stalker = {
		Sight = false,
		Event = 0.45, -- it turned your camera around and showed you what had been back there
		Death = 0.4,
	},

	-- The ambient ones. None of these can kill you, so `Death` never pays out and sight or proximity
	-- is the whole of what they offer -- which is the case the index would have had no answer for if
	-- discovery were only ever recorded on death.
	Watcher = {
		-- Deliberately far off and deliberately brief: it ducks back the moment it is caught, so all
		-- there is to see is the retreat. The dwell has to be short enough that a peek registers.
		Sight = { Range = 160, Angle = 40, GainPerSecond = 0.055, MinDwell = 0.2 },
	},
	Ghost = {
		-- The one enemy that will hold still in front of you for as long as you care to watch, so it
		-- pays slowly and reliably. It is also the first entry most players will complete.
		Sight = { Range = 120, Angle = 45, GainPerSecond = 0.023, MinDwell = 0.7 },
	},
	Eye = {
		-- Staring at it is what it charges for, so this fills fast on purpose: the player is already
		-- paying in health for every second of it, and the entry is the only thing they get back.
		Sight = { Range = 150, Angle = 35, GainPerSecond = 0.065, MinDwell = 0.3 },
		Death = 0.4,
	},
	Creep = {
		-- Nothing to look at. Two red points on an invisible slab, and a `ViewportFrame` cannot even
		-- draw its emitters -- what a player meets is the corridor going dark around them, so that is
		-- what counts. The proximity range stays local to the Creep even though its light claim now
		-- covers the full straight hallway and the rooms attached to it.
		-- Scaled down alongside the sight rates rather than left where it was: proximity is the same
		-- passive trickle by another name, and at the old rate standing in one Creep's dark would have
		-- finished its entry in the time it takes to half-fill anything else's.
		Sight = false,
		Proximity = { Range = CreepConfig.LightRange, GainPerSecond = 0.045 },
	},
	Chaos = {
		-- Seventy studs a second of fire down a corridor. A dwell timer would never catch it, and the
		-- encounter is not looking at it anyway -- it is being somewhere it went past. `ChaosService`
		-- grants this on a near miss.
		Sight = false,
		Event = 0.4,
		Death = 0.45,
	},
} :: { [string]: DiscoveryRule }

--- The rule for `enemyId`, with anything it did not specify filled in from `Defaults`. Sight comes
--- back nil where the enemy opts out of it, which is a different thing from having no rule at all --
--- an id with no entry here is simply an enemy nobody has written a rule for yet, and gets the
--- defaults so a new enemy is discoverable the day it is added rather than the day it is configured.
function DiscoveryConfig.Resolve(enemyId: string): { Sight: SightRule?, Proximity: ProximityRule?, Event: number?, Death: number }
	local rule = DiscoveryConfig.Rules[enemyId] or {}

	local sight: SightRule? = nil
	if rule.Sight == nil then
		sight = DiscoveryConfig.Defaults.Sight
	elseif rule.Sight ~= false then
		sight = rule.Sight :: SightRule
	end

	return {
		Sight = sight,
		Proximity = rule.Proximity,
		Event = rule.Event,
		Death = rule.Death or DiscoveryConfig.Defaults.Death,
	}
end

return DiscoveryConfig
