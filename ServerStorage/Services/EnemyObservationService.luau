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
local UNIT_TOLERANCE = 0.01 -- slack on a reported look direction's length before it stops being one

type Observation = {
	Models: { [Model]: boolean },
	Eye: Vector3?, -- where they reported looking from, when the claim was plausible
	Look: Vector3?, -- and which way, as a unit vector
	ReceivedAt: number,
}

--- One player's camera, reduced to what a "would they see something there" question needs.
export type View = {
	Eye: Vector3,
	Look: Vector3,
}

local UpdateView = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("UpdateView") :: RemoteEvent

local EnemyObservationService = {}
local Observations: { [Player]: Observation } = {}
local LastReports: { [Player]: number } = {}

UpdateView.OnServerEvent:Connect(function(player: Player, reportedModels: any, reportedEye: any, reportedLook: any)
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

	Observations[player] = {
		Models = models,
		Eye = eye,
		Look = look,
		ReceivedAt = now,
	}
end)

-- This player's latest report, while it is recent enough to still describe where they are looking.
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

--- Whether this player's client is currently keeping the server up to date on what it can see.
---
--- False after a frame hitch, a jittery connection, or anything else that lets a report age out, and
--- the distinction matters to callers that must not read silence as blindness. `IsObservedBy` cannot
--- make that call for them -- a stale report names no models at all, so it is indistinguishable from
--- an honest "I can see nothing" -- so a caller that would act on the difference asks here first and
--- answers the question itself.
function EnemyObservationService:IsReporting(player: Player): boolean
	return getFresh(player) ~= nil
end

--- Degrees between the middle of `player`'s screen and `model`, or nil while they are not looking at
--- it at all. Zero is dead center. Distance is not considered: this is where the thing sits in their
--- view, not how big it looms in it.
---
--- A report that names the model but gives no usable camera to have seen it from counts as dead
--- center, so a client that strips its own camera out of the report is answering for the worst case
--- rather than escaping the question.
function EnemyObservationService:GetViewAngle(player: Player, model: Model): number?
	local observation = getFresh(player)
	if not observation or not observation.Models[model] then return nil end

	local eye, look = observation.Eye, observation.Look
	if not (eye and look) then return 0 end

	local offset = model:GetBoundingBox().Position - eye
	if offset.Magnitude < 1e-3 then return 0 end
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(look), -1, 1)))
end

--- Where one player is looking from and which way, or nil for a player with no character.
---
--- Falls back to the top of their character and the way it faces when no fresh report is in hand,
--- for the same reason `GetEyes` does: a client that stops reporting should be treated as seeing
--- from where the server already knew it was, not as blind. Callers that need to know the difference
--- do not exist yet -- everything asking this wants the best available answer.
---
--- Note what the fallback costs and what it does not. Every client fires `UpdateView` on a timer
--- whether or not it can see anything, so a fresh report is the normal case; and the camera in it
--- has already been checked against `MAX_CAMERA_DISTANCE` by the time it is stored, so a player
--- cannot claim to be looking from across the building.
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

--- Every living player's camera, as `GetView` reports it. What a placement that must not happen in
--- front of anybody asks, rather than asking after one player at a time and forgetting the rest.
function EnemyObservationService:GetViews(): { View }
	local views = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if not (humanoid and humanoid.Health > 0) then continue end

		local eye, look = self:GetView(player)
		if eye and look then
			table.insert(views, { Eye = eye, Look = look } :: View)
		end
	end

	return views
end

--- Whether `point` falls inside the `cone`-degree wedge somebody with this view is looking down.
---
--- Aim only: a point behind a wall is still within the cone, because the cheap half of "can they see
--- it" is the half worth asking first. A caller that means the whole question follows this with a
--- raycast of its own, which also lets it choose what that ray is allowed to be stopped by.
function EnemyObservationService.IsWithinCone(view: View, point: Vector3, cone: number): boolean
	if cone >= 360 then return true end

	local offset = point - view.Eye
	if offset.Magnitude < 1e-3 or view.Look.Magnitude < 1e-3 then return true end
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(view.Look.Unit), -1, 1))) <= cone / 2
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
