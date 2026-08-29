local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local PhotoCaptureService = {}

if not RunService:IsClient() then
	return PhotoCaptureService
end

local PhotoConfig = require(ReplicatedStorage.Configs.PhotoConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local NotificationService = require(ReplicatedStorage.Services.NotificationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local PhotoDevelopService = require(ReplicatedStorage.Services.PhotoDevelopService)

local Snap = CommunicationService.Get("Photo", "Snap")

local BIND_NAME = "PhotoCaptureCamera"
local CORE_TYPES = {}
for _, coreType in Enum.CoreGuiType:GetEnumItems() do
	if coreType ~= Enum.CoreGuiType.All then
		table.insert(CORE_TYPES, coreType)
	end
end

local player = Players.LocalPlayer
local busy = false
local flash: Frame? = nil

local function getFlash(): Frame
	if flash and flash.Parent then return flash end

	local gui = GuiBuilderService.CreateScreenGui("PhotoFlash", 1000, true)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	flash = frame
	return frame
end

type HiddenGui = { Gui: LayerCollector, Parent: Instance, Enabled: boolean, Detached: boolean }

local function hideInterface(): (() -> (), () -> ())
	local hidden: { HiddenGui } = {}
	for _, gui in player.PlayerGui:GetDescendants() do
		if gui:IsA("LayerCollector") and gui.Parent then
			table.insert(hidden, { Gui = gui, Parent = gui.Parent, Enabled = gui.Enabled, Detached = false })
			gui.Enabled = false
		end
	end

	local core: { [Enum.CoreGuiType]: boolean } = {}
	for _, coreType in CORE_TYPES do
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, coreType)
		if ok and enabled then
			core[coreType] = true
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, false)
		end
	end
	pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)

	local function hold()
		for _, entry in hidden do
			if entry.Detached or not entry.Gui.Parent then continue end
			if entry.Gui.Enabled then
				entry.Gui.Enabled = false
				entry.Gui.Parent = nil
				entry.Detached = true
			end
		end
	end

	return hold, function()
		for _, entry in hidden do
			if entry.Detached and entry.Parent.Parent then
				entry.Gui.Parent = entry.Parent
				entry.Detached = false
			end
			if entry.Gui.Parent then
				entry.Gui.Enabled = entry.Enabled
			end
		end
		for coreType in core do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, true)
		end
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", true)
	end
end

local function showSelf(): (() -> (), () -> ())
	local character = player.Character
	if not character then return function() end, function() end end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootCFrame = root and root.CFrame
	local autoRotate = humanoid and humanoid.AutoRotate

	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or Vector3.zero
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.zero

	if humanoid then
		humanoid.AutoRotate = false
	end

	local saved: { [BasePart]: number } = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			saved[part] = part.LocalTransparencyModifier
		end
	end

	local function hold()
		for part in saved do
			if part.Parent then
				part.LocalTransparencyModifier = 0
			end
		end
		if root and root.Parent then
			if facing.Magnitude > 0 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
			elseif rootCFrame then
				root.CFrame = rootCFrame
			end
		end
	end

	return hold, function()
		for part, value in saved do
			if part.Parent then
				part.LocalTransparencyModifier = value
			end
		end
		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = autoRotate
		end
		if root and rootCFrame and root.Parent then
			root.CFrame = CFrame.new(root.Position) * rootCFrame.Rotation
		end
	end
end

local function hideViewmodel(): () -> ()
	local camera = workspace.CurrentCamera
	local rig = camera and camera:FindFirstChild("Viewmodel")
	if not rig then return function() end end

	local saved: { [BasePart]: number } = {}
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			saved[part] = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
		end
	end

	return function()
		for part, value in saved do
			if part.Parent then
				part.LocalTransparencyModifier = value
			end
		end
	end
end

local function spawnFigure(pivot: CFrame?, figureName: string?): Model?
	if not pivot then return nil end

	local name = figureName or PhotoConfig.Figure.Name
	local enemies = ReplicatedStorage:FindFirstChild("Enemies")
	local rig = enemies and enemies:FindFirstChild(name)
	if not rig or not rig:IsA("Model") then
		warn(`PhotoCaptureService: no rig named "{name}" in ReplicatedStorage.Enemies -- the photo will have no figure`)
		return nil
	end

	local clone = rig:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("BodyColors") or descendant:IsA("HumanoidDescription") or descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end

	clone:PivotTo(pivot)
	clone.Parent = workspace
	return clone
end

local function holdCamera(lens: CFrame, fieldOfView: number, onStep: () -> ()): () -> ()
	local camera = workspace.CurrentCamera
	if not camera then return function() end end

	local cameraType = camera.CameraType
	local cameraCFrame = camera.CFrame
	local cameraFov = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 5, function()
		camera.CFrame = lens
		camera.FieldOfView = fieldOfView
		onStep()
	end)

	return function()
		RunService:UnbindFromRenderStep(BIND_NAME)
		camera.CFrame = cameraCFrame
		camera.FieldOfView = cameraFov
		camera.CameraType = cameraType
	end
end

local function waitForFrame(timeout: number)
	local thread = coroutine.running()
	local resumed = false
	local connection: RBXScriptConnection? = nil

	local function finish()
		if resumed then return end
		resumed = true
		if connection then
			connection:Disconnect()
		end
		task.spawn(thread)
	end

	connection = RunService.RenderStepped:Connect(finish)
	task.delay(timeout, finish)
	coroutine.yield()
end

local function capture(): (CaptureGalleryService.Media?, string?)
	return CaptureGalleryService:TakeScreenshot()
end

function PhotoCaptureService:Take(lens: CFrame, fieldOfView: number, figure: CFrame?, figureName: string?)
	if busy then return end
	busy = true

	CaptureGalleryService:EnsurePermission()

	local settings = PhotoConfig.Capture
	local sheet = getFlash()

	TweenService:Create(sheet, TweenInfo.new(settings.FlashIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	}):Play()
	task.wait(settings.FlashIn + settings.FlashHold)

	local holdInterface: (() -> ())? = nil
	local restoreInterface: (() -> ())? = nil
	local restoreViewmodel: (() -> ())? = nil
	local holdSelf, restoreSelf = showSelf()
	local rig = spawnFigure(figure, figureName)
	local restoreCamera = holdCamera(lens, fieldOfView, function()
		if holdInterface then
			holdInterface()
		end
		holdSelf()
	end)

	local reason: string? = nil
	local ok, content = pcall(function(): CaptureGalleryService.Media?
		for _ = 1, settings.WarmupFrames do
			waitForFrame(settings.FrameTimeout)
		end

		holdInterface, restoreInterface = hideInterface()
		restoreViewmodel = hideViewmodel()

		for _ = 1, settings.HoldFrames do
			waitForFrame(settings.FrameTimeout)
		end

		local media, message = capture()
		reason = message
		return media
	end)

	holdInterface = nil
	if restoreInterface then
		restoreInterface()
	end
	if ok and content then
		PhotoDevelopService:Show(content, true)
	end
	if reason then
		NotificationService:Show(reason)
	end

	restoreCamera()
	if restoreViewmodel then
		restoreViewmodel()
	end
	restoreSelf()
	if rig then
		rig:Destroy()
	end

	TweenService:Create(sheet, TweenInfo.new(settings.FlashOut, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()

	busy = false

	if not ok then
		warn(`PhotoCaptureService: capture failed: {content}`)
	end
end

Snap.OnClientEvent:Connect(function(lens: CFrame, fieldOfView: number, figure: CFrame?, figureName: string?)
	if typeof(lens) ~= "CFrame" then return end

	task.spawn(function()
		PhotoCaptureService:Take(lens, fieldOfView or PhotoConfig.Lens.FieldOfView, figure, figureName)
	end)
end)

return PhotoCaptureService
