local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Hallways = require(ReplicatedStorage.Modules.Hallways)
local OddityService = require(ServerStorage.Services.OddityService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

--- Seconds between rebuilds of the cached fixture list; the map is static, so this is only
--- here to pick up fixtures that stream in late. 15-300.
local LIST_REFRESH = 60

--- Studs above the floor a HumanoidRootPart sits at, used to compare floors.
local ROOT_HEIGHT = 3

--- Seconds between debug reports on why a downed fixture has not repaired yet. 3-30.
local REPORT_INTERVAL = 6

local FixturePool = {}
FixturePool.__index = FixturePool

type Candidate = {
	Model: Model,
	Point: Vector3,
}

type Armed = {
	Candidate: Candidate,
	Ready: { [Player]: boolean },
	Highlight: Highlight?,
}

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	if Vanished.Is(character) then return nil end
	return root
end

local function hallwayPoint(position: Vector3): Vector3
	local hallway = Hallways.Nearest(position)
	if not hallway then return position end
	return Hallways.PointAt(hallway, Hallways.Along(hallway, position))
end

function FixturePool.new(class: any, label: string)
	local self = setmetatable({}, FixturePool)

	self.Class = class
	self.Label = label
	self.Settings = class.Settings

	self.Fixtures = {} :: { Candidate }
	self.ByModel = {} :: { [Model]: Candidate }
	self.NextRebuild = 0

	self.Armed = {} :: { [Model]: Armed }
	self.ArmedCount = 0
	self.Fallen = {} :: { [Model]: any }
	self.Accumulator = 0
	self.NextReport = 0

	if OddityService:IsEnabled(class.Scope) then
		Players.PlayerRemoving:Connect(function(player: Player)
			for _, record in self.Armed do
				record.Ready[player] = nil
			end
		end)

		RunService.Heartbeat:Connect(function(deltaTime: number)
			self:_step(deltaTime)
		end)
	end

	return self
end

function FixturePool:Setting(name: string, fallback: number): number
	local value = self.Settings[name]
	return if type(value) == "number" then value else fallback
end

function FixturePool:Log(message: string)
	if self.Settings.DebugLog then warn(`[{self.Label}] {message}`) end
end

function FixturePool:PointFor(model: Model): Vector3?
	local candidate = self.ByModel[model]
	return candidate and candidate.Point
end

function FixturePool:ArmDistance(): number
	return self:Setting("ArmDistance", 45)
end

function FixturePool:_rebuild()
	local tag = self.Settings.Tag
	local modelName = self.Settings.ModelName
	local list: { Candidate } = {}
	local index: { [Model]: Candidate } = {}

	for _, instance in CollectionService:GetTagged(tag) do
		if
			instance:IsA("Model")
			and (modelName == nil or instance.Name == modelName)
			and instance:IsDescendantOf(workspace)
			and (self.Class.IsCandidate == nil or self.Class:IsCandidate(instance))
		then
			local model = instance :: Model
			local candidate = self.ByModel[model]
			if not candidate then
				candidate = { Model = model, Point = hallwayPoint(model:GetPivot().Position) }
			end
			table.insert(list, candidate)
			index[model] = candidate
		end
	end

	for model in self.Fallen do
		if not index[model] and self.ByModel[model] then
			index[model] = self.ByModel[model]
		end
	end

	self.Fixtures = list
	self.ByModel = index
	self.NextRebuild = os.clock() + (if #list > 0 then LIST_REFRESH else 2)
end

function FixturePool:_setHighlight(record: Armed, on: boolean)
	if not on then
		if record.Highlight then
			record.Highlight:Destroy()
			record.Highlight = nil
		end
		return
	end

	if record.Highlight or not self.Settings.DebugHighlight then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ArmedFixtureDebug"
	highlight.Adornee = record.Candidate.Model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 170, 40)
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = Color3.fromRGB(255, 230, 150)
	highlight.Parent = record.Candidate.Model
	record.Highlight = highlight
end

function FixturePool:_disarm(model: Model)
	local record = self.Armed[model]
	if not record then return end

	self.Armed[model] = nil
	self.ArmedCount -= 1
	self:_setHighlight(record, false)
end

function FixturePool:_arm(candidate: Candidate)
	local record: Armed = { Candidate = candidate, Ready = {}, Highlight = nil }
	self.Armed[candidate.Model] = record
	self.ArmedCount += 1
	self:_setHighlight(record, true)
	self:Log(`armed {candidate.Model:GetFullName()}`)
end

function FixturePool:_crowded(candidate: Candidate, spacing: number): boolean
	for other in self.Armed do
		local point = self:PointFor(other)
		if point and (point - candidate.Point).Magnitude < spacing then return true end
	end
	for other in self.Fallen do
		local point = self:PointFor(other)
		if point and (point - candidate.Point).Magnitude < spacing then return true end
	end
	return false
end

function FixturePool:_refill()
	local wanted = math.max(self:Setting("ArmedCount", 3), 0)
	if self.ArmedCount >= wanted then return end

	local roots = {}
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root then table.insert(roots, root) end
	end
	if #roots == 0 or #self.Fixtures == 0 then return end

	local minimum = self:Setting("CandidateMinDistance", 55)
	local maximum = self:Setting("CandidateMaxDistance", 160)
	local spacing = self:Setting("CandidateSpacing", 90)
	local samples = math.max(math.floor(self:Setting("CandidateSamples", 48)), 1)

	while self.ArmedCount < wanted do
		local chosen: Candidate? = nil

		for _ = 1, samples do
			local candidate = self.Fixtures[math.random(1, #self.Fixtures)]
			local model = candidate.Model
			if self.Armed[model] or self.Fallen[model] or not model.Parent then continue end

			local nearest = math.huge
			for _, root in roots do
				nearest = math.min(nearest, (root.Position - candidate.Point).Magnitude)
			end
			if nearest < minimum or nearest > maximum then continue end
			if self:_crowded(candidate, spacing) then continue end

			chosen = candidate
			break
		end

		if not chosen then return end
		self:_arm(chosen)
	end
end

function FixturePool:_headingToward(root: BasePart, toPoint: Vector3): boolean
	local velocity = root.AssemblyLinearVelocity
	local heading = Vector3.new(velocity.X, 0, velocity.Z)
	if heading.Magnitude < self:Setting("ApproachMinSpeed", 4) then return false end
	if toPoint.Magnitude < 1e-3 then return true end
	return heading.Unit:Dot(toPoint.Unit) >= self:Setting("ApproachDot", 0.5)
end

function FixturePool:Drop(model: Model): boolean
	if self.Fallen[model] then return false end
	self:_disarm(model)

	local oddity, reason = OddityService:Start(self.Class, model)
	if not oddity then
		self:Log(`{model:GetFullName()} would not drop: {reason or "unknown"}`)
		return false
	end

	self.Fallen[model] = oddity
	oddity:OnStopped(function(finished: any)
		self.Fallen[model] = nil
		self:Log(`fixed {model:GetFullName()} after {math.floor(finished:GroundedFor())}s`)
	end)

	self:Log(`dropped {model:GetFullName()}`)
	return true
end

function FixturePool:_pollApproaches()
	local triggerDistance = self:Setting("TriggerDistance", 25)
	local armDistance = self:ArmDistance()
	local floorTolerance = self:Setting("SameFloorTolerance", 8)
	local chance = self:Setting("ApproachChance", 1)

	for model, record in self.Armed do
		if not model.Parent then
			self:_disarm(model)
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
			if not self:_headingToward(root, flat) then continue end

			if math.random() <= chance then
				self:Log(`{player.Name} approached {model.Name} at {math.floor(flat.Magnitude)} studs, dropping`)
				self:Drop(model)
			else
				self:Log(`{player.Name} approached {model.Name} at {math.floor(flat.Magnitude)} studs, roll failed`)
				self:_disarm(model)
			end
			consumed = true
			break
		end

		if consumed then break end
	end
end

function FixturePool:_pollRepairs()
	local report = self.Settings.DebugLog and os.clock() >= self.NextReport
	if report then self.NextReport = os.clock() + REPORT_INTERVAL end

	for model, oddity in self.Fallen do
		if not model.Parent then
			self.Fallen[model] = nil
		elseif oddity:IsReadyToFix() then
			oddity:Stop()
		elseif report then
			self:Log(`{model.Name} still down: {oddity:WhyNotFixed()}`)
		end
	end
end

function FixturePool:_step(deltaTime: number)
	local interval = self:Setting("PollInterval", 0.2)
	self.Accumulator += deltaTime
	if self.Accumulator < interval then return end
	self.Accumulator %= interval

	if os.clock() >= self.NextRebuild then self:_rebuild() end

	self:_refill()
	self:_pollApproaches()
	self:_pollRepairs()
end

function FixturePool:GetArmed(): { Model }
	local models = {}
	for model in self.Armed do
		table.insert(models, model)
	end
	return models
end

function FixturePool:GetFallen(): { [Model]: any }
	return self.Fallen
end

function FixturePool:Nearest(position: Vector3): (Model?, number)
	local best: Model? = nil
	local bestDistance = math.huge

	for _, candidate in self.Fixtures do
		if self.Fallen[candidate.Model] or not candidate.Model.Parent then continue end
		local distance = (candidate.Point - position).Magnitude
		if distance < bestDistance then
			best = candidate.Model
			bestDistance = distance
		end
	end

	return best, bestDistance
end

return FixturePool
