local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Gaze = require(ServerStorage.Modules.Gaze)
local LightService = require(ServerStorage.Services.LightService)
local PropOddity = require(ServerStorage.Classes.PropOddity)

local LIGHT_TAG = "Floor1Light"
local PLAYER_COLLISION_GROUP = "Players"
local ENEMY_COLLISION_GROUP = "Enemies"

local LanternFall = PropOddity.extend("LanternFall", PropOddity)

local preparedGroups: { [string]: boolean } = {}

local function ensureCollisionGroup(name: string)
	if preparedGroups[name] then return end
	preparedGroups[name] = true

	for _, group in { name, PLAYER_COLLISION_GROUP, ENEMY_COLLISION_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end

	PhysicsService:CollisionGroupSetCollidable(name, PLAYER_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(name, ENEMY_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(name, name, false)
end

function LanternFall.new(config: { [string]: any }?)
	local self = PropOddity.new(config, LanternFall)

	self.Parts = {} :: { BasePart }
	self.Origins = {} :: { [BasePart]: CFrame }
	self.Groups = {} :: { [BasePart]: string }
	self.Welds = {} :: { WeldConstraint }
	self.LightClaim = nil :: any
	self.FellAt = 0

	return self
end

function LanternFall:OnStart(): boolean
	local model = self.Model :: Model

	local parts: { BasePart } = {}
	local root: BasePart? = nil
	local largest = -1

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
			if volume > largest then
				largest = volume
				root = descendant
			end
		end
	end

	if not root then return false end

	local group = self.Config.CollisionGroup or "FallenProp"
	ensureCollisionGroup(group)

	for _, part in parts do
		self.Origins[part] = part.CFrame
		self.Groups[part] = part.CollisionGroup
	end

	self.LightClaim = LightService:DisableModel(model)
	model:RemoveTag(LIGHT_TAG)

	for _, part in parts do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
			table.insert(self.Welds, weld)
		end
	end

	for _, part in parts do
		part.CollisionGroup = group
		part.Anchored = false
	end

	self.Parts = parts
	self.FellAt = os.clock()
	return true
end

function LanternFall:GroundedFor(): number
	return if self.FellAt > 0 then os.clock() - self.FellAt else 0
end

function LanternFall:WhyNotFixed(): string?
	if not self.Active then return "not active" end

	local model = self.Model :: Model
	if not model or not model.Parent then return "model is gone" end

	local grounded = self:GroundedFor()
	local minimum = self:Setting("MinGroundTime", 45)
	if grounded < minimum then
		return `{math.ceil(minimum - grounded)}s left on the ground timer`
	end

	local pivot = model:GetPivot().Position
	local clearance = self:Setting("FixClearDistance", 24)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local distance = (root.Position - pivot).Magnitude
			if distance < clearance then
				return `{player.Name} is {math.floor(distance)} studs away, needs {math.floor(clearance)}`
			end
		end
	end

	local seen, watcher = Gaze.IsLookedAt(model, {
		Cone = self:Setting("FixViewCone", 120),
		MaxDistance = self:Setting("FixViewDistance", 160),
		Samples = 2,
	})
	if seen then
		return `{if watcher then watcher.Name else "someone"} is looking at it`
	end

	return nil
end

function LanternFall:IsReadyToFix(): boolean
	return self:WhyNotFixed() == nil
end

function LanternFall:OnStop()
	for _, weld in self.Welds do
		weld:Destroy()
	end
	table.clear(self.Welds)

	for _, part in self.Parts do
		if part.Parent then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			part.Anchored = true
			part.CFrame = self.Origins[part]
			part.CollisionGroup = self.Groups[part] or "Default"
		end
	end
	table.clear(self.Parts)
	table.clear(self.Origins)
	table.clear(self.Groups)

	local model = self.Model
	if model and model.Parent then
		model:AddTag(LIGHT_TAG)
	end

	if self.LightClaim then
		LightService:Release(self.LightClaim)
		self.LightClaim = nil
	end
end

return LanternFall
