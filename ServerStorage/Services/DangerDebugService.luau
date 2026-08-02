--- Server half of the danger map's tuning tools. Temporary: delete this, its client half, the
--- `DangerDebug` flag and the `Danger` remote folder once the field has been tuned and a seed picked.
---
--- It exists because the two numbers that matter most -- feature scale and contrast -- cannot be
--- judged from inside the game. You have to look at the field, against where the doors and the vents
--- and the objectives actually are, and a seed is authored content rather than something to guess at.
---
--- Studio only. This takes numbers off a client and feeds them straight into what the whole enemy
--- population is built from, which is fine on a machine somebody is developing on and is not
--- something to leave reachable in a live server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyDirectorService = require(ServerStorage.Services.EnemyDirectorService)

local DangerDebugService = {}

if not (FLAGS.DangerDebug and RunService:IsStudio()) then
	return DangerDebugService
end

-- Only the field's own resolved settings are accepted, and only as numbers. `StartPosition` is not in
-- here on purpose: where the entrance is comes from the tagged part, not from a slider.
local TUNABLE = {
	Seed = true,
	FeatureScale = true,
	Octaves = true,
	Persistence = true,
	NoiseGain = true,
	Contrast = true,
	FloorHeight = true,
	FloorSeparation = true,
	SafeRadius = true,
	RampLength = true,
}

-- On its own thread: the server bootstrap requires every service in one synchronous loop, so a
-- `WaitForChild` that never resolves here would stop the rest of the game from loading. A temporary
-- debug hook must not be able to take the server down with it.
task.spawn(function()
	local setConfig = ReplicatedStorage
		:WaitForChild("Communication")
		:WaitForChild("Danger")
		:WaitForChild("SetConfig") :: RemoteEvent

	setConfig.OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then return end

		local overrides = {}
		local count = 0
		for key, value in payload do
			-- `value == value` rejects NaN, which would otherwise poison every sample in the field
			-- and leave the whole map reading as danger zero with nothing to explain it.
			if TUNABLE[key] and type(value) == "number" and value == value then
				overrides[key] = value
				count += 1
			end
		end
		if count == 0 then return end

		DangerMapService:Rebake(overrides)
		-- Everything currently in the world was placed against the old field, so leaving it there
		-- would mean judging a new one through the last one's population.
		EnemyDirectorService:Reset()

		warn(`[danger] rebaked from {player.Name}'s debug panel with {count} overrides`)
	end)
end)

return DangerDebugService
