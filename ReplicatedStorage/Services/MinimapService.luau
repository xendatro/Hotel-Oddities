local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local MapMarkerLayer = require(ReplicatedStorage.Classes.MapMarkerLayer)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MapInkService = require(ReplicatedStorage.Services.MapInkService)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)
local MapService = require(ReplicatedStorage.Services.MapService)
local MathService = require(ReplicatedStorage.Services.MathService)
local PresetConfig = require(ReplicatedStorage.Frameworks.xenterface.Config.PresetConfig)
local xenterface = require(ReplicatedStorage.Frameworks.xenterface)

local Minimap = MapConfig.Minimap
local Gui = Minimap.Gui

local MinimapService = {}

if not RunService:IsClient() then
	return MinimapService
end

local Player = Players.LocalPlayer
local Screen: ScreenGui? = nil
local Viewport: CanvasGroup? = nil
local Rotor: Frame? = nil
local Content: Frame? = nil
local Layer: MapMarkerLayer.MapMarkerLayer? = nil
local ActiveId = ""
local HandBack = 0

local function build()
	local playerGui = Player:WaitForChild("PlayerGui")
	local screen = playerGui:WaitForChild(Gui.ScreenGui, 10) :: ScreenGui?
	if not screen then
		warn(`MinimapService: {Gui.ScreenGui} did not replicate within 10 seconds`)
		return
	end

	local frame = screen:WaitForChild(Gui.Frame) :: GuiObject
	local existing = frame:FindFirstChild(Gui.ViewportName)
	if existing then existing:Destroy() end

	local viewport = Instance.new("CanvasGroup")
	viewport.Name = Gui.ViewportName
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1 - Minimap.Inset * 2, 1 - Minimap.Inset * 2)
	viewport.BackgroundTransparency = 1
	viewport.ClipsDescendants = true
	viewport.ZIndex = 1
	viewport.Parent = frame

	local rotor = Instance.new("Frame")
	rotor.Name = Gui.RotorName
	rotor.AnchorPoint = Vector2.new(0.5, 0.5)
	rotor.Position = UDim2.fromScale(0.5, 0.5)
	rotor.Size = UDim2.fromScale(1, 1)
	rotor.BackgroundTransparency = 1
	rotor.ZIndex = 2
	rotor.Parent = viewport

	local content = Instance.new("Frame")
	content.Name = Gui.ContentName
	content.AnchorPoint = Vector2.new(0, 0)
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = rotor

	Screen = screen
	Viewport = viewport
	Rotor = rotor
	Content = content

	Layer = MapMarkerLayer.new(content, {
		PlayerSize = Minimap.PlayerSize,
		FriendSize = Minimap.FriendSize,
		LandmarkSize = Minimap.LandmarkSize,
		PlayerParent = viewport,
	})
	MapService:RegisterLayer(Layer :: MapMarkerLayer.MapMarkerLayer)
end

function MinimapService:IsShowing(): boolean
	local screen = Screen
	return screen ~= nil and screen.Enabled
end

task.spawn(build)

xenterface:Controller(MapConfig.Gui.PageGroup).Fired:Connect(function(data)
	local previous = ActiveId
	ActiveId = data.ActiveId

	if ActiveId == MapConfig.Gui.PageId then
		MapInkService:Reparent(nil)
		return
	end

	if previous == MapConfig.Gui.PageId then
		HandBack = os.clock() + PresetConfig.HotelPage.CloseTime + 0.04
	end
end)

RunService.RenderStepped:Connect(function()
	local screen, viewport, rotor, content, layer = Screen, Viewport, Rotor, Content, Layer
	if not screen or not viewport or not rotor or not content or not layer then return end

	local showing = ActiveId == "" and os.clock() >= HandBack and MapLayoutService:IsLoaded()
	if screen.Enabled ~= showing then screen.Enabled = showing end
	if not showing then return end

	MapInkService:Reparent(content)

	local root = CharacterService.GetAliveRoot(Player)
	local camera = Workspace.CurrentCamera
	if not root or not camera then return end

	local rotation = -MathService.LookDegrees(camera.CFrame.LookVector)
	rotor.Rotation = rotation
	layer:SetUpright(-rotation)

	local resolution = MapConfig.Canvas.Resolution
	local span = math.max(Minimap.Studs * MapLayoutService:GetScale(), 1e-3)
	local window = math.min(viewport.AbsoluteSize.X, viewport.AbsoluteSize.Y)
	local extent = window * resolution / span

	local canvas = MapLayoutService:ToCanvas(root.Position.X, root.Position.Z)
	content.Size = UDim2.fromOffset(extent, extent)
	content.Position = UDim2.new(0.5, -canvas.X / resolution * extent, 0.5, -canvas.Y / resolution * extent)
end)

return MinimapService
