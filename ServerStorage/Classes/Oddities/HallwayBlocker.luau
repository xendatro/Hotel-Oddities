local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Gaze = require(ServerStorage.Modules.Gaze)
local HallwayRegion = require(ServerStorage.Modules.HallwayRegion)
local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)
local Hallways = require(ReplicatedStorage.Modules.Hallways)

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
	local available = function(span: HallwayRegion.Span): boolean
		return not isActive(span)
	end

	local dangerWeight = setting(class, "DangerWeight", 0.35)
	local unseen = HallwayRegion.RandomDistantWeighted(dangerWeight, function(span)
		return available(span) and isUnseen(class, span)
	end)
	return unseen or HallwayRegion.RandomDistantWeighted(dangerWeight, available)
		or HallwayRegion.RandomDistantWeighted(dangerWeight)
end

function HallwayBlocker:OnStart(): boolean
	local span = self.Span :: HallwayRegion.Span
	local hallway = Hallways.Nearest(span.Center)
	local floorY = hallway and hallway.FloorY or span.Center.Y
	local blocker = Gate:Clone()
	blocker.Name = "HallwayBlocker"
	blocker:PivotTo(self.BoxCFrame)

	local boundsCFrame, boundsSize = blocker:GetBoundingBox()
	local bottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
	blocker:PivotTo(blocker:GetPivot() + Vector3.new(0, floorY - bottomY, 0))
	blocker.Parent = blockerFolder()
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
