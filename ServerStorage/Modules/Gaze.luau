local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

--- Full cone angle, in degrees, a target must fall inside to count as looked at.
local DEFAULT_CONE = 100
--- Nothing further away than this many studs counts as looked at, sightline or not.
local DEFAULT_MAX_DISTANCE = 300
--- How many points on a target are tried before it is called blocked.
local DEFAULT_SAMPLES = 3
--- Views are rebuilt at most this often; repeat queries inside the window reuse them.
local VIEW_CACHE_TIME = 0.05

local Gaze = {}

export type Target = Vector3 | BasePart | Model

export type Options = {
	Cone: number?,
	MaxDistance: number?,
	Samples: number?,
	Horizontal: boolean?,
	LineOfSight: boolean?,
	Ignore: { Instance }?,
	Players: { Player }?,
}

export type Viewer = {
	Player: Player,
	Character: Model,
	Eye: Vector3,
	Look: Vector3,
}

local cachedViewers: { Viewer } = {}
local cachedAt = -math.huge

local function livingCharacter(player: Player): Model?
	local character = player.Character
	if not character or not CharacterService.GetAliveHumanoid(player) then return nil end
	if Vanished.Is(character) then return nil end
	return character
end

local function viewerFor(player: Player): Viewer?
	local character = livingCharacter(player)
	if not character then return nil end

	local eye, look = EnemyObservationService:GetView(player)
	if not eye or not look or look.Magnitude < 1e-3 then return nil end
	return { Player = player, Character = character, Eye = eye, Look = look.Unit }
end

function Gaze.Viewers(): { Viewer }
	local now = os.clock()
	if now - cachedAt < VIEW_CACHE_TIME then return cachedViewers end
	cachedAt = now

	local viewers = {}
	for _, player in Players:GetPlayers() do
		local viewer = viewerFor(player)
		if viewer then table.insert(viewers, viewer) end
	end

	cachedViewers = viewers
	return viewers
end

function Gaze.ViewerFor(player: Player): Viewer?
	for _, viewer in Gaze.Viewers() do
		if viewer.Player == player then return viewer end
	end
	return nil
end

local function pointsFor(target: Target, samples: number): { Vector3 }
	if typeof(target) == "Vector3" then return { target } end

	if target:IsA("BasePart") then
		local cframe = target.CFrame
		local half = target.Size / 2
		local points = { cframe.Position }
		local offsets = {
			cframe.UpVector * half.Y,
			cframe.RightVector * half.X,
			cframe.LookVector * half.Z,
		}
		for _, offset in offsets do
			if #points >= samples then break end
			table.insert(points, cframe.Position + offset)
			if #points >= samples then break end
			table.insert(points, cframe.Position - offset)
		end
		return points
	end

	local points = { target:GetPivot().Position }
	if #points < samples then
		for _, descendant in target:GetDescendants() do
			if #points >= samples then break end
			if descendant:IsA("BasePart") then
				table.insert(points, descendant.Position)
			end
		end
	end
	return points
end

local function withinCone(viewer: Viewer, point: Vector3, cone: number, horizontal: boolean): boolean
	if cone >= 360 then return true end

	local offset = point - viewer.Eye
	if offset.Magnitude < 1e-3 then return true end

	local direction, look = offset, viewer.Look
	if horizontal then
		direction = Vector3.new(offset.X, 0, offset.Z)
		look = Vector3.new(viewer.Look.X, 0, viewer.Look.Z)
		if direction.Magnitude < 1e-3 or look.Magnitude < 1e-3 then return true end
	end

	return direction.Unit:Dot(look.Unit) >= math.cos(math.rad(cone / 2))
end

local function isClear(params: RaycastParams, viewer: Viewer, point: Vector3, target: Target): boolean
	local offset = point - viewer.Eye
	if offset.Magnitude < 1e-3 then return true end

	local result = workspace:Raycast(viewer.Eye, offset, params)
	if result == nil then return true end
	if typeof(target) == "Vector3" then return false end
	return result.Instance == target or result.Instance:IsDescendantOf(target)
end

local function buildParams(viewer: Viewer, options: Options?): RaycastParams
	local filter: { Instance } = { viewer.Character }
	local ignore = options and options.Ignore
	if ignore then
		for _, instance in ignore do
			table.insert(filter, instance)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true
	return params
end

function Gaze.Sees(viewer: Viewer, target: Target, options: Options?): boolean
	local cone = if options and options.Cone then options.Cone else DEFAULT_CONE
	local maxDistance = if options and options.MaxDistance then options.MaxDistance else DEFAULT_MAX_DISTANCE
	local samples = math.max(if options and options.Samples then options.Samples else DEFAULT_SAMPLES, 1)
	local horizontal = if options then options.Horizontal == true else false
	local lineOfSight = if options and options.LineOfSight ~= nil then options.LineOfSight else true

	local points = pointsFor(target, samples)
	local params: RaycastParams? = nil

	for _, point in points do
		if (point - viewer.Eye).Magnitude > maxDistance then continue end
		if not withinCone(viewer, point, cone, horizontal) then continue end
		if not lineOfSight then return true end

		if not params then params = buildParams(viewer, options) end
		if isClear(params :: RaycastParams, viewer, point, target) then return true end
	end

	return false
end

function Gaze.IsLookedAtBy(player: Player, target: Target, options: Options?): boolean
	local viewer = Gaze.ViewerFor(player)
	return viewer ~= nil and Gaze.Sees(viewer, target, options)
end

local function candidates(options: Options?): { Viewer }
	local only = options and options.Players
	if not only then return Gaze.Viewers() end

	local wanted: { [Player]: boolean } = {}
	for _, player in only do
		wanted[player] = true
	end

	local viewers = {}
	for _, viewer in Gaze.Viewers() do
		if wanted[viewer.Player] then table.insert(viewers, viewer) end
	end
	return viewers
end

function Gaze.IsLookedAt(target: Target, options: Options?): (boolean, Player?)
	for _, viewer in candidates(options) do
		if Gaze.Sees(viewer, target, options) then return true, viewer.Player end
	end
	return false, nil
end

function Gaze.Watchers(target: Target, options: Options?): { Player }
	local watching = {}
	for _, viewer in candidates(options) do
		if Gaze.Sees(viewer, target, options) then
			table.insert(watching, viewer.Player)
		end
	end
	return watching
end

local Tracker = {}
Tracker.__index = Tracker

export type Tracker = typeof(setmetatable(
	{} :: {
		Target: Target,
		Options: Options?,
		LookedAt: boolean,
		SeenFor: number,
		UnseenFor: number,
		Watchers: { Player },
		UpdatedAt: number,
	},
	Tracker
))

function Gaze.new(target: Target, options: Options?): Tracker
	return setmetatable({
		Target = target,
		Options = options,
		LookedAt = false,
		SeenFor = 0,
		UnseenFor = 0,
		Watchers = {},
		UpdatedAt = os.clock(),
	}, Tracker)
end

function Tracker:Update(): boolean
	local now = os.clock()
	local elapsed = now - self.UpdatedAt
	self.UpdatedAt = now

	local watchers = Gaze.Watchers(self.Target, self.Options)
	local lookedAt = #watchers > 0
	self.Watchers = watchers

	if lookedAt ~= self.LookedAt then
		self.LookedAt = lookedAt
		self.SeenFor = 0
		self.UnseenFor = 0
	elseif lookedAt then
		self.SeenFor += elapsed
	else
		self.UnseenFor += elapsed
	end

	return lookedAt
end

function Tracker:Retarget(target: Target)
	self.Target = target
	self.LookedAt = false
	self.SeenFor = 0
	self.UnseenFor = 0
	self.Watchers = {}
	self.UpdatedAt = os.clock()
end

return Gaze
