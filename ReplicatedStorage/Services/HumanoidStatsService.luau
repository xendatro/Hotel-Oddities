local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

export type Stats = { [string]: number }

type State = {
	Humanoid: Humanoid,
	Sources: { [string]: Stats },
	Applied: Stats,
	Defaults: { MaxHealth: number, WalkSpeed: number, JumpPower: number, UseJumpPower: boolean },
	Connection: RBXScriptConnection,
}

local HumanoidStatsService = {}

local states: { [Humanoid]: State } = {}

local function baseOf(statId: string): number
	local stat = KitConfig.StatsById[statId]
	return if stat then stat.Base else 0
end

local function clampStat(statId: string, value: number): number
	local stat = KitConfig.StatsById[statId]
	if not stat then return value end
	return math.clamp(value, stat.Minimum, stat.Maximum)
end

local function resolve(state: State): Stats
	local resolved: Stats = {}

	for _, stat in KitConfig.Stats do
		local value = stat.Base
		local touched = false

		for _, source in state.Sources do
			local contribution = source[stat.Id]
			if contribution == nil then continue end

			touched = true
			if stat.Mode == "Scale" then
				value *= contribution / stat.Base
			else
				value += contribution - stat.Base
			end
		end

		if touched then
			resolved[stat.Id] = clampStat(stat.Id, value)
		end
	end

	return resolved
end

local function writeHealth(humanoid: Humanoid, maxHealth: number)
	local previous = humanoid.MaxHealth
	if math.abs(previous - maxHealth) <= 0.001 then return end

	local fraction = if previous > 0 then humanoid.Health / previous else 1
	humanoid.MaxHealth = maxHealth
	humanoid.Health = math.clamp(fraction * maxHealth, 0, maxHealth)
end

local function apply(state: State)
	local resolved = resolve(state)
	local humanoid = state.Humanoid
	local character = humanoid.Parent

	for statId in state.Applied do
		if resolved[statId] ~= nil then continue end

		if statId == "MaxHealth" then
			writeHealth(humanoid, state.Defaults.MaxHealth)
		elseif statId == "WalkSpeed" and humanoid.WalkSpeed > 0 then
			humanoid.WalkSpeed = state.Defaults.WalkSpeed
		elseif statId == "JumpPower" then
			humanoid.JumpPower = state.Defaults.JumpPower
			humanoid.UseJumpPower = state.Defaults.UseJumpPower
		elseif character then
			character:SetAttribute(statId, nil)
		end
	end

	if resolved.MaxHealth then
		writeHealth(humanoid, resolved.MaxHealth)
	end

	if resolved.WalkSpeed and humanoid.WalkSpeed > 0 then
		humanoid.WalkSpeed = resolved.WalkSpeed
	end

	if resolved.JumpPower then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = resolved.JumpPower
	end

	if character then
		for _, stat in KitConfig.Stats do
			if stat.Apply ~= "Attribute" then continue end
			character:SetAttribute(stat.Id, resolved[stat.Id])
		end
	end

	state.Applied = resolved
end

local function release(humanoid: Humanoid)
	local state = states[humanoid]
	if not state then return end

	states[humanoid] = nil
	state.Connection:Disconnect()

	local character = humanoid.Parent
	if character then
		for _, stat in KitConfig.Stats do
			if stat.Apply == "Attribute" then character:SetAttribute(stat.Id, nil) end
		end
	end
end

local function getState(humanoid: Humanoid): State
	local state = states[humanoid]
	if state then return state end

	state = {
		Humanoid = humanoid,
		Sources = {},
		Applied = {},
		Defaults = {
			MaxHealth = humanoid.MaxHealth,
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			UseJumpPower = humanoid.UseJumpPower,
		},
		Connection = humanoid.Destroying:Connect(function()
			release(humanoid)
		end),
	}
	states[humanoid] = state
	return state
end

function HumanoidStatsService:SetSource(humanoid: Humanoid, source: string, stats: Stats?)
	if not humanoid or not humanoid.Parent then return end

	local state = getState(humanoid)
	local copy: Stats? = nil

	if stats and next(stats) ~= nil then
		copy = {}
		for statId, value in stats do
			if KitConfig.StatsById[statId] then
				(copy :: Stats)[statId] = value
			end
		end
		if next(copy :: Stats) == nil then copy = nil end
	end

	state.Sources[source] = copy
	apply(state)
end

function HumanoidStatsService:ClearSource(humanoid: Humanoid, source: string)
	local state = states[humanoid]
	if not state or not state.Sources[source] then return end

	state.Sources[source] = nil
	apply(state)
end

function HumanoidStatsService:Get(humanoid: Humanoid, statId: string): number
	local state = states[humanoid]
	local applied = state and state.Applied[statId]
	return applied or baseOf(statId)
end

function HumanoidStatsService.ReadAttribute(character: Instance?, statId: string): number
	local stat = KitConfig.StatsById[statId]
	local base = if stat then stat.Base else 0
	if not character then return base end

	local value = character:GetAttribute(statId)
	if type(value) ~= "number" or not stat then return base end
	return math.clamp(value, stat.Minimum, stat.Maximum)
end

function HumanoidStatsService.GetDetectionRadius(character: Instance?): number
	return HumanoidStatsService.ReadAttribute(character, "DetectionRadius")
end

function HumanoidStatsService.Describe(stats: Stats): { { Stat: KitConfig.Stat, Value: number, Delta: number, Better: boolean } }
	local rows = {}

	for _, stat in KitConfig.Stats do
		local value = stats[stat.Id]
		if value == nil then continue end

		local delta = value - stat.Base
		if math.abs(delta) <= 0.0001 then continue end

		table.insert(rows, {
			Stat = stat,
			Value = value,
			Delta = delta,
			Better = if stat.HigherIsBetter then delta > 0 else delta < 0,
		})
	end

	table.sort(rows, function(a, b)
		return a.Stat.Order < b.Stat.Order
	end)

	return rows
end

return HumanoidStatsService
