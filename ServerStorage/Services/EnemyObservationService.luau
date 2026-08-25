local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local ENEMY_TAG = "Enemy"
local OBSERVABLE_TAG = "Observable"
local MAX_REPORTED_ENEMIES = 16
local MAX_REPORT_DISTANCE = 300
local MIN_REPORT_INTERVAL = 0.025
local MAX_REPORT_AGE = 0.2
local MAX_CAMERA_DISTANCE = 40
local HEAD_OFFSET = 1.5
local UNIT_TOLERANCE = 0.01

type Observation = {
	Models: { [Model]: boolean },
	Eye: Vector3?,
	Look: Vector3?,
	FogStart: number?,
	FogEnd: number?,
	ReceivedAt: number,
}

export type View = {
	Eye: Vector3,
	Look: Vector3,
}

local UpdateView = CommunicationService.Get("Enemies", "UpdateView") :: RemoteEvent

local EnemyObservationService = {}
local Observations: { [Player]: Observation } = {}
local LastReports: { [Player]: number } = {}

UpdateView.OnServerEvent:Connect(function(
	player: Player,
	reportedModels: any,
	reportedEye: any,
	reportedLook: any,
	reportedFogStart: any,
	reportedFogEnd: any
)
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

	local look = nil :: Vector3?
	if typeof(reportedLook) == "Vector3" and math.abs(reportedLook.Magnitude - 1) <= UNIT_TOLERANCE then
		look = reportedLook
	end

	local fogStart = nil :: number?
	if typeof(reportedFogStart) == "number" and reportedFogStart >= 0 and reportedFogStart < math.huge then
		fogStart = reportedFogStart
	end

	local fogEnd = nil :: number?
	if typeof(reportedFogEnd) == "number"
		and reportedFogEnd >= 0
		and reportedFogEnd < math.huge
		and (not fogStart or reportedFogEnd >= fogStart)
	then
		fogEnd = reportedFogEnd
	end

	Observations[player] = {
		Models = models,
		Eye = eye,
		Look = look,
		FogStart = fogStart,
		FogEnd = fogEnd,
		ReceivedAt = now,
	}
end)

local function getFresh(player: Player): Observation?
	local observation = Observations[player]
	if observation and os.clock() - observation.ReceivedAt <= MAX_REPORT_AGE then
		return observation
	end
	return nil
end

function EnemyObservationService:IsObservedBy(player: Player, model: Model): boolean
	local observation = getFresh(player)
	return observation ~= nil and observation.Models[model] == true
end

function EnemyObservationService:IsReporting(player: Player): boolean
	return getFresh(player) ~= nil
end

function EnemyObservationService:GetViewAngle(player: Player, model: Model): number?
	local observation = getFresh(player)
	if not observation or not observation.Models[model] then return nil end

	local eye, look = observation.Eye, observation.Look
	if not (eye and look) then return 0 end

	local offset = model:GetBoundingBox().Position - eye
	if offset.Magnitude < 1e-3 then return 0 end
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(look), -1, 1)))
end

function EnemyObservationService:GetView(player: Player): (Vector3?, Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil, nil end

	local observation = getFresh(player)
	if observation and observation.Eye and observation.Look then
		return observation.Eye, observation.Look
	end

	return root.Position + Vector3.new(0, HEAD_OFFSET, 0), root.CFrame.LookVector
end

function EnemyObservationService:GetFogRange(player: Player): (number?, number?)
	local observation = getFresh(player)
	if not observation then return nil, nil end
	return observation.FogStart, observation.FogEnd
end

function EnemyObservationService:GetViews(): { View }
	local views = {}

	for _, player in Players:GetPlayers() do
		if not CharacterService.GetAliveHumanoid(player) then continue end

		local eye, look = self:GetView(player)
		if eye and look then
			table.insert(views, { Eye = eye, Look = look } :: View)
		end
	end

	return views
end

function EnemyObservationService.IsWithinCone(view: View, point: Vector3, cone: number): boolean
	if cone >= 360 then return true end

	local offset = point - view.Eye
	if offset.Magnitude < 1e-3 or view.Look.Magnitude < 1e-3 then return true end
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(view.Look.Unit), -1, 1))) <= cone / 2
end

function EnemyObservationService:GetEyes(): { Vector3 }
	local eyes = {}

	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if not root then continue end

		local observation = getFresh(player)
		if observation and observation.Eye then
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
