local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Hallways = require(ReplicatedStorage.Modules.Hallways)
local OddityService = require(ServerStorage.Services.OddityService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

local SCOPE = "Prop"
local KIND = "LanternFall"
local LIGHT_TAG = "Floor1Light"

--- Seconds between rebuilds of the cached lantern list; the map is static, so this is only
--- here to pick up lanterns that stream in late. 15-300.
local LIST_REFRESH = 60

--- Studs above the floor a HumanoidRootPart sits at, used to compare floors.
local ROOT_HEIGHT = 3

--- Seconds between debug reports on why a downed lantern has not repaired yet. 3-30.
local REPORT_INTERVAL = 6

local LanternFallService = {}

local Class = OddityService:Get(SCOPE, KIND)
if not Class then return LanternFallService end

local Settings = Class.Settings

type Candidate = {
	Model: Model,
	Position: Vector3,
	Point: Vector3,
}

type Armed = {
	Candidate: Candidate,
	Ready: { [Player]: boolean },
	Highlight: Highlight?,
}

local lanterns: { Candidate } = {}
local byModel: { [Model]: Candidate } = {}
local nextRebuild = 0

local armed: { [Model]: Armed } = {}
local armedCount = 0
local fallen: { [Model]: any } = {}
local accumulator = 0

local function setting(name: string, fallback: number): number
	local value = Settings[name]
	return if type(value) == "number" then value else fallback
end

local function log(message: string)
	if Settings.DebugLog then warn(`[lantern] {message}`) end
end

local function pointOf(model: Model): Vector3?
	local candidate = byModel[model]
	return candidate and candidate.Point
end

local function hallwayPoint(position: Vector3): Vector3
	local hallway = Hallways.Nearest(position)
	if not hallway then return position end
	return Hallways.PointAt(hallway, Hallways.Along(hallway, position))
end

local function rebuild()
	local modelName = Settings.ModelName or "HallwayLantern"
	local list: { Candidate } = {}
	local index: { [Model]: Candidate } = {}

	for _, instance in CollectionService:GetTagged(LIGHT_TAG) do
		if instance:IsA("Model") and instance.Name == modelName and instance:IsDescendantOf(workspace) then
			local model = instance :: Model
			local existing = byModel[model]
			local candidate = existing
			if not candidate then
				local position = model:GetPivot().Position
				candidate = { Model = model, Position = position, Point = hallwayPoint(position) }
			end
			table.insert(list, candidate)
			index[model] = candidate
		end
	end

	for model in fallen do
		if not index[model] and byModel[model] then
			index[model] = byModel[model]
		end
	end

	lanterns = list
	byModel = index
	nextRebuild = os.clock() + (if #list > 0 then LIST_REFRESH else 2)
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	if Vanished.Is(character) then return nil end
	return root
end

local function livingRoots(): { BasePart }
	local roots = {}
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root then table.insert(roots, root) end
	end
	return roots
end

local function setHighlight(record: Armed, on: boolean)
	if not on then
		if record.Highlight then
			record.Highlight:Destroy()
			record.Highlight = nil
		end
		return
	end

	if record.Highlight or not Settings.DebugHighlight then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ArmedLanternDebug"
	highlight.Adornee = record.Candidate.Model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 170, 40)
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = Color3.fromRGB(255, 230, 150)
	highlight.Parent = record.Candidate.Model
	record.Highlight = highlight
end

local function disarm(model: Model)
	local record = armed[model]
	if not record then return end

	armed[model] = nil
	armedCount -= 1
	setHighlight(record, false)
end

local function arm(candidate: Candidate)
	local record: Armed = { Candidate = candidate, Ready = {}, Highlight = nil }
	armed[candidate.Model] = record
	armedCount += 1
	setHighlight(record, true)
	log(`armed {candidate.Model:GetFullName()}`)
end

local function refill()
	local wanted = math.max(setting("ArmedCount", 3), 0)
	if armedCount >= wanted then return end

	local roots = livingRoots()
	if #roots == 0 or #lanterns == 0 then return end

	local minimum = setting("CandidateMinDistance", 55)
	local maximum = setting("CandidateMaxDistance", 160)
	local spacing = setting("CandidateSpacing", 90)
	local samples = math.max(math.floor(setting("CandidateSamples", 48)), 1)

	while armedCount < wanted do
		local chosen: Candidate? = nil

		for _ = 1, samples do
			local candidate = lanterns[math.random(1, #lanterns)]
			local model = candidate.Model
			if armed[model] or fallen[model] or not model.Parent then continue end

			local nearest = math.huge
			for _, root in roots do
				nearest = math.min(nearest, (root.Position - candidate.Point).Magnitude)
			end
			if nearest < minimum or nearest > maximum then continue end

			local crowded = false
			for other in armed do
				local point = pointOf(other)
				if point and (point - candidate.Point).Magnitude < spacing then
					crowded = true
					break
				end
			end
			if not crowded then
				for other in fallen do
					local point = pointOf(other)
					if point and (point - candidate.Point).Magnitude < spacing then
						crowded = true
						break
					end
				end
			end
			if crowded then continue end

			chosen = candidate
			break
		end

		if not chosen then return end
		arm(chosen)
	end
end

local function isHeadingToward(root: BasePart, toPoint: Vector3): boolean
	local velocity = root.AssemblyLinearVelocity
	local heading = Vector3.new(velocity.X, 0, velocity.Z)
	if heading.Magnitude < setting("ApproachMinSpeed", 4) then return false end
	if toPoint.Magnitude < 1e-3 then return true end
	return heading.Unit:Dot(toPoint.Unit) >= setting("ApproachDot", 0.5)
end

local function drop(model: Model): boolean
	disarm(model)

	local oddity, reason = OddityService:Start(Class, model)
	if not oddity then
		log(`{model:GetFullName()} would not drop: {reason or "unknown"}`)
		return false
	end

	fallen[model] = oddity
	oddity:OnStopped(function(finished: any)
		fallen[model] = nil
		log(`fixed {model:GetFullName()} after {math.floor(finished:GroundedFor())}s`)
	end)

	log(`dropped {model:GetFullName()}`)
	return true
end

local function pollApproaches()
	local triggerDistance = setting("TriggerDistance", 25)
	local armDistance = setting("ArmDistance", 45)
	local floorTolerance = setting("SameFloorTolerance", 8)
	local chance = setting("ApproachChance", 0.05)

	for model, record in armed do
		if not model.Parent then
			disarm(model)
			continue
		end

		local point = record.Candidate.Point
		local ready = record.Ready
		local consumed = false

		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if not root then
				ready[player] = nil
				continue
			end

			local offset = point - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)

			if flat.Magnitude > armDistance then
				ready[player] = true
				continue
			end

			if not ready[player] then continue end
			if flat.Magnitude > triggerDistance then continue end
			if math.abs(point.Y - (root.Position.Y - ROOT_HEIGHT)) > floorTolerance then continue end
			if not isHeadingToward(root, flat) then continue end

			if math.random() <= chance then
				log(`{player.Name} approached {model.Name} at {math.floor(flat.Magnitude)} studs, dropping`)
				drop(model)
			else
				log(`{player.Name} approached {model.Name} at {math.floor(flat.Magnitude)} studs, roll failed`)
				disarm(model)
			end
			consumed = true
			break
		end

		if consumed then break end
	end
end

local nextReport = 0

local function pollRepairs()
	local report = Settings.DebugLog and os.clock() >= nextReport
	if report then nextReport = os.clock() + REPORT_INTERVAL end

	for model, oddity in fallen do
		if not model.Parent then
			fallen[model] = nil
		elseif oddity:IsReadyToFix() then
			oddity:Stop()
		elseif report then
			log(`{model.Name} still down: {oddity:WhyNotFixed()}`)
		end
	end
end

function LanternFallService:ArmDistance(): number
	return setting("ArmDistance", 45)
end

function LanternFallService:GetArmed(): { Model }
	local models = {}
	for model in armed do
		table.insert(models, model)
	end
	return models
end

function LanternFallService:GetFallen(): { [Model]: any }
	return fallen
end

function LanternFallService:PointFor(model: Model): Vector3?
	local candidate = byModel[model]
	return candidate and candidate.Point
end

function LanternFallService:Nearest(position: Vector3): (Model?, number)
	local best: Model? = nil
	local bestDistance = math.huge

	for _, candidate in lanterns do
		if fallen[candidate.Model] or not candidate.Model.Parent then continue end
		local distance = (candidate.Point - position).Magnitude
		if distance < bestDistance then
			best = candidate.Model
			bestDistance = distance
		end
	end

	return best, bestDistance
end

function LanternFallService:Drop(model: Model): boolean
	if fallen[model] then return false end
	return drop(model)
end

if OddityService:IsEnabled(SCOPE) then
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, record in armed do
			record.Ready[player] = nil
		end
	end)

	RunService.Heartbeat:Connect(function(deltaTime: number)
		local interval = setting("PollInterval", 0.2)
		accumulator += deltaTime
		if accumulator < interval then return end
		accumulator %= interval

		if os.clock() >= nextRebuild then rebuild() end

		refill()
		pollApproaches()
		pollRepairs()
	end)
end

return LanternFallService
