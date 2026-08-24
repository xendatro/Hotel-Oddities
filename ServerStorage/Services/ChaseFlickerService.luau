local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local EnemyService = require(ServerStorage.Services.EnemyService)
local LightService = require(ServerStorage.Services.LightService)

local ChaseFlickerService = {}

if not FLAGS.Enemies then
	return ChaseFlickerService
end

local FLICKER_ENEMIES = {
	CeilingDweller = true,
	Mimic = true,
}
local POLL_INTERVAL = 0.35
local FLICKER_ROLL = 1.1
local CHASE_STATES = {
	Chase = true,
	Attack = true,
}

task.spawn(function()
	while true do
		task.wait(POLL_INTERVAL)

		EnemyService:ForEachActive(function(enemy)
			if not FLICKER_ENEMIES[enemy.EnemyId] or not enemy.Active then return end

			local machine = enemy.StateMachine
			local target = enemy.Target
			if not target or not machine or not CHASE_STATES[machine.State] then return end

			local character = target.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				LightService:FlickerHallwayContaining(root.Position, FLICKER_ROLL)
			end
		end)
	end
end)

return ChaseFlickerService
