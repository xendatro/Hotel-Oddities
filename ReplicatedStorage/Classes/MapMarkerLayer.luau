local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local MapMarker = require(ReplicatedStorage.Classes.MapMarker)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MapInkService = require(ReplicatedStorage.Services.MapInkService)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)
local MathService = require(ReplicatedStorage.Services.MathService)

local Markers = MapConfig.Markers

local MapMarkerLayer = {}
MapMarkerLayer.__index = MapMarkerLayer

export type Options = {
	PlayerSize: number?,
	FriendSize: number?,
	LandmarkSize: number?,
}

export type MapMarkerLayer = typeof(setmetatable({} :: {
	Frame: Frame,
	Connections: { RBXScriptConnection },
	_options: Options,
	_landmarks: { [string]: MapMarker.MapMarker },
	_friends: { [Player]: MapMarker.MapMarker },
	_facings: { [Player]: ImageLabel },
	_player: Frame,
	_playerFacing: ImageLabel?,
	_upright: number,
}, MapMarkerLayer))

local Player = Players.LocalPlayer

local function toScale(worldX: number, worldZ: number): UDim2
	local canvas = MapLayoutService:ToCanvas(worldX, worldZ)
	local resolution = MapConfig.Canvas.Resolution
	return UDim2.fromScale(canvas.X / resolution, canvas.Y / resolution)
end

local function attachArrow(parent: GuiObject, size: number): ImageLabel
	local extent = size * Markers.ArrowScale
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Facing"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(extent, extent)
	arrow.BackgroundTransparency = 1
	arrow.ScaleType = Enum.ScaleType.Stretch
	arrow.ImageContent = MapInkService:GetArrow().Content
	arrow.ZIndex = parent.ZIndex + 1
	arrow.Parent = parent
	return arrow
end

local function buildPlayerMarker(parent: Frame, size: number): Frame
	local marker = Instance.new("Frame")
	marker.Name = "You"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(size, size)
	marker.BackgroundColor3 = MapConfig.Ink.Color
	marker.BorderSizePixel = 0
	marker.ZIndex = 25
	marker.Visible = false
	marker.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = marker

	return marker
end

local function setUpConnections(self: MapMarkerLayer): { RBXScriptConnection }
	return {
		Players.PlayerRemoving:Connect(function(player: Player)
			self:ClearFriend(player)
		end),
	}
end

function MapMarkerLayer.new(parent: GuiObject, options: Options?): MapMarkerLayer
	local self = setmetatable({}, MapMarkerLayer)

	self._options = options or {}
	self._landmarks = {}
	self._friends = {}
	self._facings = {}
	self._upright = 0

	local frame = Instance.new("Frame")
	frame.Name = MapConfig.Gui.MarkerName
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 10
	frame.Parent = parent
	self.Frame = frame

	local playerSize = self._options.PlayerSize or Markers.PlayerSize
	self._player = buildPlayerMarker(frame, playerSize)
	self._playerFacing = attachArrow(self._player, playerSize)

	self.Connections = setUpConnections(self)

	return self
end

function MapMarkerLayer:PlaceLandmark(kind: string, key: string): boolean
	if self._landmarks[key] or not MapLayoutService:IsLoaded() then return false end

	local x, z = key:match("^(-?%d+),(-?%d+)$")
	if not x then return false end

	local marker = MapMarker.new(self.Frame, kind, nil, self._options.LandmarkSize)
	marker:SetPosition(toScale(tonumber(x) :: number, tonumber(z) :: number))
	marker.Frame.Rotation = self._upright
	self._landmarks[key] = marker
	return true
end

function MapMarkerLayer:Pop(key: string)
	local marker = self._landmarks[key]
	if marker then marker:Pop() end
end

function MapMarkerLayer:SetComplete(key: string, complete: boolean)
	local marker = self._landmarks[key]
	if marker then marker:SetComplete(complete) end
end

function MapMarkerLayer:ClearLandmarks()
	for _, marker in self._landmarks do
		marker:Destroy()
	end
	table.clear(self._landmarks)
end

function MapMarkerLayer:ClearFriend(player: Player)
	local marker = self._friends[player]
	if marker then
		marker:Destroy()
		self._friends[player] = nil
	end
	self._facings[player] = nil
end

function MapMarkerLayer:SetUpright(degrees: number)
	if self._upright == degrees then return end
	self._upright = degrees

	for _, marker in self._landmarks do
		marker.Frame.Rotation = degrees
	end
	for _, marker in self._friends do
		marker.Frame.Rotation = degrees
	end
	self._player.Rotation = degrees
end

function MapMarkerLayer:Update()
	local root = CharacterService.GetAliveRoot(Player)
	if root then
		self._player.Visible = true
		self._player.Position = toScale(root.Position.X, root.Position.Z)
		if self._playerFacing then
			self._playerFacing.Rotation = MathService.LookDegrees(root.CFrame.LookVector) - self._upright
		end
	else
		self._player.Visible = false
	end

	for _, other in Players:GetPlayers() do
		if other == Player then continue end

		local otherRoot = CharacterService.GetAliveRoot(other)
		local marker = self._friends[other]

		if not otherRoot then
			if marker then marker.Frame.Visible = false end
			continue
		end

		if not marker then
			local size = self._options.FriendSize or Markers.FriendSize
			marker = MapMarker.new(self.Frame, "Friend", other.UserId, size)
			marker.Frame.Rotation = self._upright
			self._friends[other] = marker
			self._facings[other] = attachArrow(marker.Frame, size)
		end

		marker.Frame.Visible = true
		marker:SetPosition(toScale(otherRoot.Position.X, otherRoot.Position.Z))

		local facing = self._facings[other]
		if facing then
			facing.Rotation = MathService.LookDegrees(otherRoot.CFrame.LookVector) - self._upright
		end
	end
end

function MapMarkerLayer:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	self:ClearLandmarks()
	for player in self._friends do
		self:ClearFriend(player)
	end
	self.Frame:Destroy()
end

return MapMarkerLayer
