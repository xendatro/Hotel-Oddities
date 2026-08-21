export type SightRule = {
	Range: number,
	Angle: number,
	GainPerSecond: number,
	MinDwell: number,
}

export type ProximityRule = {
	Range: number,
	GainPerSecond: number,
}

export type DiscoveryRule = {
	Sight: SightRule | false | nil,
	Proximity: ProximityRule?,
	Event: number?,
	Death: number?,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)

local DiscoveryConfig = {}

DiscoveryConfig.SweepInterval = 0.25

DiscoveryConfig.ReplicateStep = 0.05

DiscoveryConfig.Defaults = {
	Sight = {
		Range = 140,
		Angle = 45,
		GainPerSecond = 0.025,
		MinDwell = 0.75,
	} :: SightRule,

	Death = 0.34,
}

DiscoveryConfig.Rules = {
	Chaser = {},
	CeilingDweller = {
		Sight = { Range = 60, Angle = 55, GainPerSecond = 0.023, MinDwell = 0.4 },
		Death = 0.45,
	},
	Blind = {},
	WeepingAngel = {
		Sight = { Range = 200, Angle = 45, GainPerSecond = 0.032, MinDwell = 0.5 },
	},
	Sisters = {
		-- Met at 150 studs and slow enough to study on the way past.
		Sight = { Range = 180, Angle = 45, GainPerSecond = 0.028, MinDwell = 0.7 },
	},

	-- The ambushes. Nothing is learned by looking, because looking is exactly what they defeat.
	Mimic = {
		Sight = false,
		Event = 0.5,
		Death = 0.5,
	},
	Stalker = {
		Sight = false,
		Event = 0.45,
		Death = 0.4,
	},

	Watcher = {
		Sight = { Range = 160, Angle = 40, GainPerSecond = 0.055, MinDwell = 0.2 },
	},
	Ghost = {
		Sight = { Range = 120, Angle = 45, GainPerSecond = 0.023, MinDwell = 0.7 },
	},
	Eye = {
		Sight = { Range = 150, Angle = 35, GainPerSecond = 0.065, MinDwell = 0.3 },
		Death = 0.4,
	},
	Creep = {
		Sight = false,
		Proximity = { Range = CreepConfig.LightRange, GainPerSecond = 0.045 },
	},
	Chaos = {
		Sight = false,
		Event = 0.4,
		Death = 0.45,
	},
} :: { [string]: DiscoveryRule }

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
