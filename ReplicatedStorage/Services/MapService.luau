local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local MapMarker = require(ReplicatedStorage.Classes.MapMarker)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MapControlService = require(ReplicatedStorage.Services.MapControlService)
local MapInkService = require(ReplicatedStorage.Services.MapInkService)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)

local Gui = MapConfig.Gui
local Remotes = MapConfig.Remotes

local MapService = {}

local Player = Players.LocalPlayer
local Paper: ImageLabel? = nil
local Content: Frame? = nil
local Layer: Frame? = nil
local PlayerMarker: Frame? = nil
local Landmarks: { [string]: MapMarker.MapMarker } = {}
local Friends: { [Player]: MapMarker.MapMarker } = {}
local Pending = false

local function getPaper(): ImageLabel
	if Paper then return Paper :: ImageLabel end

	local playerGui = Player:WaitForChild("PlayerGui")
	local screen = playerGui:WaitForChild(Gui.ScreenGui)
	Paper = screen:WaitForChild(Gui.Paper) :: ImageLabel
	return Paper :: ImageLabel
end

local function buildViewport(paper: ImageLabel): (Frame, Frame)
	local inset = MapConfig.Controls.Inset

	local viewport = Instance.new("Frame")
	viewport.Name = Gui.ViewportName
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1 - inset * 2, 1 - inset * 2)
	viewport.BackgroundTransparency = 1
	viewport.ClipsDescendants = true
	viewport.Active = true
	viewport.ZIndex = 2
	viewport.Parent = paper

	local content = Instance.new("Frame")
	content.Name = Gui.ContentName
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = viewport

	return viewport, content
end

local function buildPlayerMarker(layer: Frame): Frame
	local marker = Instance.new("Frame")
	marker.Name = "You"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(MapConfig.Markers.PlayerSize, MapConfig.Markers.PlayerSize)
	marker.BackgroundColor3 = MapConfig.Ink.Color
	marker.BorderSizePixel = 0
	marker.ZIndex = 25
	marker.Visible = false
	marker.Parent = layer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = marker

	return marker
end

function MapService:GetPaper(): ImageLabel?
	return Paper
end

function MapService:ToPaperScale(worldX: number, worldZ: number): UDim2
	local canvas = MapLayoutService:ToCanvas(worldX, worldZ)
	local resolution = MapConfig.Canvas.Resolution
	return UDim2.fromScale(canvas.X / resolution, canvas.Y / resolution)
end

local function placeLandmark(kind: string, key: string, pop: boolean)
	local layer = Layer
	if not layer or Landmarks[key] then return end

	local x, z = key:match("^(-?%d+),(-?%d+)$")
	if not x then return end

	local marker = MapMarker.new(layer, kind)
	marker:SetPosition(MapService:ToPaperScale(tonumber(x) :: number, tonumber(z) :: number))
	Landmarks[key] = marker

	if pop then marker:Pop() end
end

local function clearFriend(player: Player)
	local marker = Friends[player]
	if marker then
		marker:Destroy()
		Friends[player] = nil
	end
end

local function updateFriends()
	local layer = Layer
	if not layer then return end

	for _, other in Players:GetPlayers() do
		if other == Player then continue end

		local root = CharacterService.GetAliveRoot(other)
		local marker = Friends[other]

		if not root then
			if marker then marker.Frame.Visible = false end
			continue
		end

		if not marker then
			marker = MapMarker.new(layer, "Friend", other.UserId)
			Friends[other] = marker
		end

		marker.Frame.Visible = true
		marker:SetPosition(MapService:ToPaperScale(root.Position.X, root.Position.Z))
	end
end

local function onSync(layout: { any }, store: { [string]: { number } }, landmarks: { [string]: { [string]: boolean } })
	local paper = getPaper()

	MapLayoutService:Load(layout)

	for _, marker in Landmarks do
		marker:Destroy()
	end
	table.clear(Landmarks)

	for player in Friends do
		clearFriend(player)
	end

	local existing = paper:FindFirstChild(Gui.ViewportName)
	if existing then existing:Destroy() end

	local viewport, content = buildViewport(paper)
	Content = content

	MapInkService:Attach(content)

	local layer = Instance.new("Frame")
	layer.Name = Gui.MarkerName
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 10
	layer.Parent = content
	Layer = layer

	PlayerMarker = buildPlayerMarker(layer)
	MapControlService:Attach(viewport, content)

	for kind, found in landmarks do
		for key in found do
			placeLandmark(kind, key, false)
		end
	end

	task.spawn(function()
		MapInkService:LoadDiscovered(store)
	end)
end

local function onReveal(key: string, packed: { number })
	if not MapInkService:IsAttached() then return end
	if not MapInkService:Reveal(key, packed) then return end

	if Pending then return end
	Pending = true
	task.defer(function()
		Pending = false
		MapInkService:Flush()
	end)
end

CommunicationService.Get(Remotes.Folder, Remotes.Sync).OnClientEvent:Connect(onSync)
CommunicationService.Get(Remotes.Folder, Remotes.Reveal).OnClientEvent:Connect(onReveal)
CommunicationService.Get(Remotes.Folder, Remotes.Landmark).OnClientEvent:Connect(function(kind: string, key: string)
	placeLandmark(kind, key, true)
end)

Players.PlayerRemoving:Connect(clearFriend)

RunService.RenderStepped:Connect(function()
	if not MapLayoutService:IsLoaded() then return end

	local marker = PlayerMarker
	if marker then
		local root = CharacterService.GetAliveRoot(Player)
		if root then
			marker.Visible = true
			marker.Position = MapService:ToPaperScale(root.Position.X, root.Position.Z)
		else
			marker.Visible = false
		end
	end

	updateFriends()
end)

return MapService
