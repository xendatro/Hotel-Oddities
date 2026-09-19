local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GateConfig = require(ReplicatedStorage.Configs.GateConfig)
local Gaze = require(ServerStorage.Services.GazeService)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local HallwayRegion = require(ServerStorage.Services.HallwayRegionService)
local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)
local HallwayWall = require(ServerStorage.Services.HallwayWallService)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)

local Gate = ReplicatedStorage.Props.Other.Gate :: Model

local BLOCKER_FOLDER_NAME = "HallwayBlockers"

local function blockerFolder(): Folder
	local existing = workspace:FindFirstChild(BLOCKER_FOLDER_NAME)
	if existing then return existing :: Folder end

	local folder = Instance.new("Folder")
	folder.Name = BLOCKER_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local ActiveSpans: { HallwayRegion.Span } = {}

local HallwayBlocker = HallwayOddity.extend("HallwayBlocker", HallwayOddity)

local function setting(class: any, name: string, fallback: number): number
	local value = class.Settings and class.Settings[name]
	return if type(value) == "number" then value else fallback
end

local function isActive(span: HallwayRegion.Span): boolean
	for _, activeSpan in ActiveSpans do
		if HallwayRegion.Same(activeSpan, span) then return true end
	end
	return false
end

local function isNearSplit(class: any, span: HallwayRegion.Span): boolean
	local boxCFrame, boxSize = HallwayRegion.Box(span)
	local across = boxCFrame.XVector
	local clearance = setting(class, "SplitClearance", 12)

	for _, node in HallwayGraph:Get() do
		if HallwayGraph:CountExits(node) < 3 then continue end

		local offset = node.Position - span.Center
		if math.abs(offset.Y) > 4 then continue end
		if math.abs(offset:Dot(across)) > boxSize.X / 2 then continue end
		if math.abs(offset:Dot(span.Axis)) <= clearance then return true end
	end

	return false
end

type Placement = {
	CFrame: CFrame,
	FloorY: number,
}

local function placementFor(class: any, span: HallwayRegion.Span): Placement?
	local frame = HallwayWall.Frame(span)
	if not frame then return nil end

	local clearance = setting(class, "MouthClearance", 8)
	local shortest = setting(class, "MinimumStretch", 6)

	local best: HallwayWall.Interval? = nil
	for _, interval in HallwayWall.Inset(HallwayWall.Closing(frame), clearance) do
		local length = interval.Maximum - interval.Minimum
		if length < shortest then continue end
		if not best or length > best.Maximum - best.Minimum then best = interval end
	end
	if not best then return nil end

	local along = (best.Minimum + best.Maximum) / 2
	local position = frame.Center + frame.Axis * along
	if not Hallways.At(position) then return nil end

	return {
		CFrame = CFrame.lookAt(position, position + frame.Axis, Vector3.yAxis),
		FloorY = frame.FloorY,
	}
end

local function isUnseen(class: any, span: HallwayRegion.Span): boolean
	local lookedAt = Gaze.IsLookedAt(span.Center, {
		Cone = setting(class, "GazeCone", 100),
		MaxDistance = setting(class, "GazeDistance", 300),
	})
	return not lookedAt
end

function HallwayBlocker.new(config: { [string]: any }?)
	local self = HallwayOddity.new(config, HallwayBlocker)
	self.Blocker = nil :: Model?
	return self
end

function HallwayBlocker.Pick(class: any): HallwayRegion.Span?
	local rejected: { [HallwayRegion.Span]: boolean } = {}
	local available = function(span: HallwayRegion.Span): boolean
		return not rejected[span] and not isActive(span) and not isNearSplit(class, span)
	end

	local dangerWeight = setting(class, "DangerWeight", 0.35)
	for _ = 1, math.max(setting(class, "PickAttempts", 12), 1) do
		local unseen = HallwayRegion.RandomDistantWeighted(dangerWeight, function(span)
			return available(span) and isUnseen(class, span)
		end)
		local span = unseen or HallwayRegion.RandomDistantWeighted(dangerWeight, available)
		if not span then return nil end
		if placementFor(class, span) then return span end
		rejected[span] = true
	end
	return nil
end

function HallwayBlocker:OnStart(): boolean
	local span = self.Span :: HallwayRegion.Span
	local placement = placementFor(self, span)
	if not placement then return false end

	local floorY = placement.FloorY
	local blocker = Gate:Clone()
	blocker.Name = "HallwayBlocker"
	blocker:PivotTo(placement.CFrame)

	local boundsCFrame, boundsSize = blocker:GetBoundingBox()
	local bottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
	blocker:PivotTo(blocker:GetPivot() + Vector3.new(0, floorY - bottomY, 0))
	blocker.Parent = blockerFolder()
	CollectionService:AddTag(blocker, GateConfig.Tag)
	self.Blocker = blocker
	table.insert(ActiveSpans, self.Span :: HallwayRegion.Span)
	return true
end

function HallwayBlocker:OnStop()
	if self.Blocker then
		self.Blocker:Destroy()
		self.Blocker = nil
	end

	local span = self.Span
	if span then
		local index = table.find(ActiveSpans, span)
		if index then table.remove(ActiveSpans, index) end
	end
end

return HallwayBlocker
