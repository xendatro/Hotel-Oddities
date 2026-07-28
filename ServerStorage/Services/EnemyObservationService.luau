local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ENEMY_TAG = "Enemy"
local WEEPING_ANGEL_MODEL = "Weeping Angel"
local MAX_REPORTED_ENEMIES = 16
local MAX_REPORT_DISTANCE = 300
local MIN_REPORT_INTERVAL = 0.025
local MAX_REPORT_AGE = 0.2

type Observation = {
	Models: { [Model]: boolean },
	ReceivedAt: number,
}

local UpdateView = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("UpdateView") :: RemoteEvent

local EnemyObservationService = {}
local Observations: { [Player]: Observation } = {}
local LastReports: { [Player]: number } = {}

UpdateView.OnServerEvent:Connect(function(player: Player, reportedModels: any)
	if type(reportedModels) ~= "table" then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local now = os.clock()
	local lastReport = LastReports[player]
	if lastReport and now - lastReport < MIN_REPORT_INTERVAL then return end
	LastReports[player] = now

	local models = {}
	local count = 0
	for _, model in reportedModels do
		count += 1
		if count > MAX_REPORTED_ENEMIES then return end

		if typeof(model) == "Instance"
			and model:IsA("Model")
			and model:IsDescendantOf(workspace)
			and model:HasTag(ENEMY_TAG)
			and model.Name == WEEPING_ANGEL_MODEL
			and (model:GetPivot().Position - (root :: BasePart).Position).Magnitude <= MAX_REPORT_DISTANCE
		then
			models[model] = true
		end
	end

	Observations[player] = {
		Models = models,
		ReceivedAt = now,
	}
end)

function EnemyObservationService:IsObservedBy(player: Player, model: Model): boolean
	local observation = Observations[player]
	return observation ~= nil
		and os.clock() - observation.ReceivedAt <= MAX_REPORT_AGE
		and observation.Models[model] == true
end

Players.PlayerRemoving:Connect(function(player: Player)
	Observations[player] = nil
	LastReports[player] = nil
end)

return EnemyObservationService
