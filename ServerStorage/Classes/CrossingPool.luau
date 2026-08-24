local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local MathService = require(ReplicatedStorage.Services.MathService)
local OddityService = require(ServerStorage.Services.OddityService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local LIST_REFRESH = 60

local ROOT_HEIGHT = 3

export type Site = {
	Id: string,
	Point: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfWidth: number,
}

type Armed = {
	Site: Site,
	Ready: { [Player]: boolean },
	Marker: BasePart?,
}

local CrossingPool = {}
CrossingPool.__index = CrossingPool

local function livingRoot(player: Player): BasePart?
	local root = CharacterService.GetAliveRoot(player)
	if not root then return nil end
	if Vanished.Is(player.Character) then return nil end
	return root
end

function CrossingPool.new(class: any, label: string)
	local self = setmetatable({}, CrossingPool)

	self.Class = class
	self.Label = label
	self.Settings = class.Settings

	self.Sites = {} :: { Site }
	self.ById = {} :: { [string]: Site }
	self.NextRebuild = 0

	self.Armed = {} :: { [string]: Armed }
	self.ArmedCount = 0
	self.Running = {} :: { [string]: Site }
	self.Cooldowns = {} :: { [string]: number }
	self.Accumulator = 0

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

function CrossingPool:Setting(name: string, fallback: number): number
	local value = self.Settings[name]
	return if type(value) == "number" then value else fallback
end

function CrossingPool:Log(message: string)
	if self.Settings.DebugLog then warn(`[{self.Label}] {message}`) end
end

function CrossingPool:PointFor(site: Site): Vector3?
	return site.Point
end

function CrossingPool:ArmDistance(): number
	return self:Setting("ArmDistance", 45)
end

function CrossingPool:_rebuild()
	local spacing = math.max(self:Setting("SiteSpacing", 40), 4)
	local inset = self:Setting("EndInset", 14)
	local minimumWidth = self:Setting("MinHallwayWidth", 8)

	local list: { Site } = {}
	local index: { [string]: Site } = {}

	for _, hallway in Hallways.All() do
		if hallway.HalfWidth * 2 < minimumWidth then continue end

		local usable = hallway.HalfLength - inset
		if usable <= 0 then continue end

		local count = math.max(math.floor((usable * 2) / spacing), 1)
		for step = 1, count do
			local along = -usable + (usable * 2) * ((step - 0.5) / count)
			local id = string.format(
				"%d:%d:%d:%d",
				math.round(hallway.Center.X),
				math.round(hallway.Center.Y),
				math.round(hallway.Center.Z),
				math.round(along)
			)

			local site = index[id] or self.ById[id]
			if site then
				site.Point = Hallways.PointAt(hallway, along)
				site.Axis = hallway.Axis
				site.Across = hallway.Across
				site.HalfWidth = hallway.HalfWidth
			else
				site = {
					Id = id,
					Point = Hallways.PointAt(hallway, along),
					Axis = hallway.Axis,
					Across = hallway.Across,
					HalfWidth = hallway.HalfWidth,
				}
			end

			if not index[id] then
				table.insert(list, site)
				index[id] = site
			end
		end
	end

	self.Sites = list
	self.ById = index
	self.NextRebuild = os.clock() + (if #list > 0 then LIST_REFRESH else 2)
end

function CrossingPool:_setMarker(record: Armed, on: boolean)
	if not on then
		if record.Marker then
			record.Marker:Destroy()
			record.Marker = nil
		end
		return
	end

	if record.Marker or not self.Settings.DebugMarker then return end

	local marker = Instance.new("Part")
	marker.Name = "ArmedCrossingDebug"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.2, 6, 6)
	marker.CFrame = CFrame.new(record.Site.Point + Vector3.yAxis * 0.1) * CFrame.Angles(0, 0, math.rad(90))
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 170, 40)
	marker.Transparency = 0.55
	marker.Parent = workspace
	record.Marker = marker
end

function CrossingPool:_disarm(id: string)
	local record = self.Armed[id]
	if not record then return end

	self.Armed[id] = nil
	self.ArmedCount -= 1
	self:_setMarker(record, false)
end

function CrossingPool:_arm(site: Site)
	local record: Armed = { Site = site, Ready = {}, Marker = nil }
	self.Armed[site.Id] = record
	self.ArmedCount += 1
	self:_setMarker(record, true)
	self:Log(`armed {site.Id}`)
end

function CrossingPool:_crowded(site: Site, spacing: number): boolean
	for _, record in self.Armed do
		if (record.Site.Point - site.Point).Magnitude < spacing then return true end
	end
	for _, other in self.Running do
		if (other.Point - site.Point).Magnitude < spacing then return true end
	end
	return false
end

function CrossingPool:_refill()
	local wanted = math.max(self:Setting("ArmedCount", 2), 0)
	if self.ArmedCount >= wanted then return end

	local roots = {}
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root then table.insert(roots, root) end
	end
	if #roots == 0 or #self.Sites == 0 then return end

	local minimum = self:Setting("CandidateMinDistance", 55)
	local maximum = self:Setting("CandidateMaxDistance", 200)
	local spacing = self:Setting("CandidateSpacing", 90)
	local samples = math.max(math.floor(self:Setting("CandidateSamples", 48)), 1)
	local now = os.clock()

	while self.ArmedCount < wanted do
		local chosen: Site? = nil

		for _ = 1, samples do
			local site = self.Sites[math.random(1, #self.Sites)]
			if self.Armed[site.Id] or self.Running[site.Id] then continue end
			if (self.Cooldowns[site.Id] or 0) > now then continue end

			local nearest = math.huge
			for _, root in roots do
				nearest = math.min(nearest, (root.Position - site.Point).Magnitude)
			end
			if nearest < minimum or nearest > maximum then continue end
			if self:_crowded(site, spacing) then continue end

			chosen = site
			break
		end

		if not chosen then return end
		self:_arm(chosen)
	end
end

function CrossingPool:_headingToward(root: BasePart, toPoint: Vector3): boolean
	local heading = MathService.Horizontal(root.AssemblyLinearVelocity)
	if heading.Magnitude < self:Setting("ApproachMinSpeed", 4) then return false end
	if toPoint.Magnitude < 1e-3 then return true end
	return heading.Unit:Dot(toPoint.Unit) >= self:Setting("ApproachDot", 0.5)
end

function CrossingPool:Trigger(site: Site): boolean
	if self.Running[site.Id] then return false end
	self:_disarm(site.Id)

	local oddity, reason = OddityService:Start(self.Class, site)
	if not oddity then
		self:Log(`{site.Id} would not run: {reason or "unknown"}`)
		return false
	end

	self.Running[site.Id] = site
	self.Cooldowns[site.Id] = os.clock() + self:Setting("SiteCooldown", 180)
	oddity:OnStopped(function()
		self.Running[site.Id] = nil
	end)

	self:Log(`ran at {site.Id}`)
	return true
end

function CrossingPool:_pollApproaches()
	local triggerDistance = self:Setting("TriggerDistance", 26)
	local armDistance = self:ArmDistance()
	local floorTolerance = self:Setting("SameFloorTolerance", 8)
	local chance = self:Setting("ApproachChance", 1)

	for id, record in self.Armed do
		local site = record.Site
		local ready = record.Ready

		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if not root then
				ready[player] = nil
				continue
			end

			local flat = MathService.Horizontal(site.Point - root.Position)

			if flat.Magnitude > armDistance then
				ready[player] = true
				continue
			end

			if not ready[player] then continue end
			if flat.Magnitude > triggerDistance then continue end
			if math.abs(site.Point.Y - (root.Position.Y - ROOT_HEIGHT)) > floorTolerance then continue end
			if not self:_headingToward(root, flat) then continue end

			if math.random() <= chance then
				self:Log(`{player.Name} approached {id} at {math.floor(flat.Magnitude)} studs, running`)
				self:Trigger(site)
			else
				self:Log(`{player.Name} approached {id} at {math.floor(flat.Magnitude)} studs, roll failed`)
				self:_disarm(id)
			end
			return
		end
	end
end

function CrossingPool:_step(deltaTime: number)
	local interval = self:Setting("PollInterval", 0.2)
	self.Accumulator += deltaTime
	if self.Accumulator < interval then return end
	self.Accumulator %= interval

	if os.clock() >= self.NextRebuild then self:_rebuild() end

	self:_refill()
	self:_pollApproaches()
end

function CrossingPool:GetArmed(): { Site }
	local sites = {}
	for _, record in self.Armed do
		table.insert(sites, record.Site)
	end
	return sites
end

function CrossingPool:GetRunning(): { [string]: Site }
	return self.Running
end

function CrossingPool:Nearest(position: Vector3): (Site?, number)
	local best: Site? = nil
	local bestDistance = math.huge

	for _, site in self.Sites do
		if self.Running[site.Id] then continue end
		local distance = (site.Point - position).Magnitude
		if distance < bestDistance then
			best = site
			bestDistance = distance
		end
	end

	return best, bestDistance
end

return CrossingPool
