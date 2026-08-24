local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MapInkService = require(ReplicatedStorage.Services.MapInkService)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)

local Gui = MapConfig.Gui
local Remotes = MapConfig.Remotes

local MapService = {}

local Player = Players.LocalPlayer
local Paper: ImageLabel? = nil
local PlayerMarker: Frame? = nil
local Pending = false

local function getPaper(): ImageLabel
	if Paper then return Paper end

	local playerGui = Player:WaitForChild("PlayerGui")
	local screen = playerGui:WaitForChild(Gui.ScreenGui)
	Paper = screen:WaitForChild(Gui.Paper) :: ImageLabel
	return Paper :: ImageLabel
end

local function buildPlayerMarker(paper: ImageLabel): Frame
	local marker = Instance.new("Frame")
	marker.Name = "You"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(MapConfig.Markers.PlayerSize, MapConfig.Markers.PlayerSize)
	marker.BackgroundColor3 = MapConfig.Ink.Color
	marker.BorderSizePixel = 0
	marker.ZIndex = 20
	marker.Visible = false
	marker.Parent = paper

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

local function onSync(layout: { any }, store: { [string]: { number } })
	local paper = getPaper()

	MapLayoutService:Load(layout)
	MapInkService:Attach(paper)

	if PlayerMarker then PlayerMarker:Destroy() end
	PlayerMarker = buildPlayerMarker(paper)

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

RunService.RenderStepped:Connect(function()
	local marker = PlayerMarker
	if not marker or not MapLayoutService:IsLoaded() then return end

	local root = CharacterService.GetAliveRoot(Player)
	if not root then
		marker.Visible = false
		return
	end

	marker.Visible = true
	marker.Position = MapService:ToPaperScale(root.Position.X, root.Position.Z)
end)

return MapService
