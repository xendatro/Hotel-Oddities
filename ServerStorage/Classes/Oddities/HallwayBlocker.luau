local ServerStorage = game:GetService("ServerStorage")

local Gaze = require(ServerStorage.Modules.Gaze)
local HallwayRegion = require(ServerStorage.Modules.HallwayRegion)
local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)

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
	self.Blocker = nil :: BasePart?
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
	local height = math.max(self:Setting("BlockerHeight", self.BoxSize.Y), 1)
	local thickness = math.max(self:Setting("BlockerThickness", 1.5), 0.1)
	local widthPadding = self:Setting("BlockerWidthPadding", 0)

	local blocker = Instance.new("Part")
	blocker.Name = "HallwayBlocker"
	blocker.Anchored = true
	blocker.CanCollide = true
	blocker.CanQuery = true
	blocker.CanTouch = false
	blocker.AudioCanCollide = true
	blocker.CastShadow = false
	blocker.Size = Vector3.new(self.BoxSize.X + widthPadding * 2, height, thickness)
	blocker.CFrame = self.BoxCFrame * CFrame.new(0, (height - self.BoxSize.Y) / 2, 0)
	blocker.Transparency = math.clamp(self:Setting("BlockerTransparency", 0.18), 0, 1)

	local color = self.Config.BlockerColor
	if typeof(color) == "Color3" then blocker.Color = color end
	local material = self.Config.BlockerMaterial
	if typeof(material) == "EnumItem" then blocker.Material = material end

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
