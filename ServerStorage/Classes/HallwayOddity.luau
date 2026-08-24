local ServerStorage = game:GetService("ServerStorage")

local HallwayRegion = require(ServerStorage.Modules.HallwayRegion)
local Oddity = require(ServerStorage.Classes.Oddity)
local OddityRemotes = require(ServerStorage.Modules.OddityRemotes)

local MapDoors = OddityRemotes.Event("MapDoors")

local HallwayOddity = Oddity.extend("HallwayOddity")

HallwayOddity.Scope = "Map"
HallwayOddity.ConfigName = "MapOddityConfig"
HallwayOddity.RequiresPlayer = false
HallwayOddity.IncludeRoomFloors = false

function HallwayOddity.new(config: { [string]: any }?, class: any?)
	local self = Oddity.new(config, class or HallwayOddity)

	self.Span = nil :: HallwayRegion.Span?
	self.BoxCFrame = CFrame.identity
	self.BoxSize = Vector3.zero

	return self
end

function HallwayOddity.Resolve(class: any, position: Vector3): HallwayRegion.Span?
	return HallwayRegion.At(position, class.IncludeRoomFloors)
end

function HallwayOddity.Pick(class: any): HallwayRegion.Span?
	if class.RequiresPlayer then return HallwayRegion.RandomOccupied() end

	local occupiedChance = class.Settings and class.Settings.OccupiedChance
	if type(occupiedChance) == "number" then
		return HallwayRegion.RandomBiased(occupiedChance)
	end

	return HallwayRegion.RandomDistant()
end

function HallwayOddity:CanStart(span: HallwayRegion.Span?): (boolean, string?)
	if not span then return false, "that position is not in a usable hallway" end
	if self.RequiresPlayer and not HallwayRegion.HasPlayer(span) then
		return false, "that oddity needs a living player in that hallway"
	end
	return true, nil
end

function HallwayOddity:Start(span: HallwayRegion.Span, duration: number?): boolean
	self.Span = span
	self.BoxCFrame, self.BoxSize = HallwayRegion.Box(span)
	return Oddity.Start(self, span, duration)
end

function HallwayOddity:FireMapDoors(action: string, ...: any)
	MapDoors:FireAllClients(action, self.Token, ...)
end

return HallwayOddity
