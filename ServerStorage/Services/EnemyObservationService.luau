local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ENEMY_TAG = "Enemy"
local OBSERVABLE_TAG = "Observable" -- the enemies a client's view report is allowed to name
local MAX_REPORTED_ENEMIES = 16
local MAX_REPORT_DISTANCE = 300
local MIN_REPORT_INTERVAL = 0.025
local MAX_REPORT_AGE = 0.2
-- Studs a reported camera may sit from the character it belongs to. First person puts it inside their
-- head; the allowance is for a zoomed-out third-person one, and for nothing else -- a client claiming
-- to be looking from across the building is claiming to see places it has no business seeing.
local MAX_CAMERA_DISTANCE = 40
local HEAD_OFFSET = 1.5 -- studs from an R15 root up to roughly where that character's head sits

type Observation = {
	Models: { [Model]: boolean },
	Eye: Vector3?, -- where they reported looking from, when the claim was plausible
	ReceivedAt: number,
}

local UpdateView = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("UpdateView") :: RemoteEvent

local EnemyObservationService = {}
local Observations: { [Player]: Observation } = {}
local LastReports: { [Player]: number } = {}

UpdateView.OnServerEvent:Connect(function(player: Player, reportedModels: any, reportedEye: any)
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
			and model:HasTag(OBSERVABLE_TAG)
			and (model:GetPivot().Position - (root :: BasePart).Position).Magnitude <= MAX_REPORT_DISTANCE
		then
			models[model] = true
		end
	end

	local eye = nil :: Vector3?
	if typeof(reportedEye) == "Vector3"
		and (reportedEye - (root :: BasePart).Position).Magnitude <= MAX_CAMERA_DISTANCE
	then
		eye = reportedEye
	end

	Observations[player] = {
		Models = models,
		Eye = eye,
		ReceivedAt = now,
	}
end)

function EnemyObservationService:IsObservedBy(player: Player, model: Model): boolean
	local observation = Observations[player]
	return observation ~= nil
		and os.clock() - observation.ReceivedAt <= MAX_REPORT_AGE
		and observation.Models[model] == true
end

--- Where every living player is looking from. A reported camera is used while it is fresh, and the top
--- of the character otherwise -- so a client that reports nothing, or reports somewhere it could not
--- possibly be, is treated as seeing from where the server already knew it was rather than as blind.
function EnemyObservationService:GetEyes(): { Vector3 }
	local eyes = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (humanoid and root and humanoid.Health > 0) then continue end

		local observation = Observations[player]
		if observation and observation.Eye and os.clock() - observation.ReceivedAt <= MAX_REPORT_AGE then
			table.insert(eyes, observation.Eye)
		else
			table.insert(eyes, root.Position + Vector3.new(0, HEAD_OFFSET, 0))
		end
	end

	return eyes
end

Players.PlayerRemoving:Connect(function(player: Player)
	Observations[player] = nil
	LastReports[player] = nil
end)

return EnemyObservationService
