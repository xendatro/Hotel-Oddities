local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocatorMarker = require(ReplicatedStorage.Classes.LocatorMarker)
local PlayerLocatorConfig = require(ReplicatedStorage.Configs.PlayerLocatorConfig)

local PlayerLocatorService = {}

if not RunService:IsClient() then
	return PlayerLocatorService
end

local Teleport = ReplicatedStorage.Communication.PlayerLocator.Teleport

local MODES = PlayerLocatorConfig.Modes
local MARKER = PlayerLocatorConfig.Marker
local FOCUS = PlayerLocatorConfig.Focus
local RENDER_JOB = "PlayerLocatorFocus"
local TAU = math.pi * 2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("PlayerLocator")
local frame = gui and gui:WaitForChild("Mode")
local modeLabel = frame and frame:FindFirstChild("Mode")
local toggle = frame and frame:FindFirstChild("Toggle")
local cooldownLabel = frame and frame:FindFirstChild("TeleportCooldown")

if not modeLabel or not toggle or not cooldownLabel then
	warn("[PlayerLocatorService] PlayerLocator gui is missing Mode, Toggle or TeleportCooldown; locator disabled.")
	function PlayerLocatorService:SetEnabled(_value: boolean) end
	function PlayerLocatorService:IsEnabled(): boolean
		return false
	end
	return PlayerLocatorService
end

local Markers: { [Player]: any } = {}
local Friends: { [number]: boolean } = {}
local Asking: { [number]: boolean } = {}
local modeIndex = 1
local enabled = false

local refresh

local markerFolder: Folder? = nil

local function markerHost(): Folder
	local existing = markerFolder
	if existing and existing.Parent then return existing end

	for target, marker in Markers do
		marker:Destroy()
		Markers[target] = nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "PlayerLocatorMarkers"
	folder.Parent = playerGui
	markerFolder = folder

	folder.AncestryChanged:Connect(function()
		if folder.Parent ~= nil or markerFolder ~= folder then return end
		task.defer(function()
			if markerFolder == folder and enabled then
				refresh()
			end
		end)
	end)

	return folder
end

local cooldownEndsAt = 0
local ticking: RBXScriptConnection? = nil
local pendingTarget: Player? = nil

local function isAvailable(): boolean
	return os.clock() >= cooldownEndsAt
end

local function updateCooldown()
	local remaining = cooldownEndsAt - os.clock()
	if remaining <= 0 then
		cooldownLabel.Visible = false
		if ticking then
			ticking:Disconnect()
			ticking = nil
		end
		return
	end

	cooldownLabel.Visible = enabled
	cooldownLabel.Text = string.format(PlayerLocatorConfig.CooldownFormat, math.ceil(remaining))
end

local function setCooldown(remaining: number)
	cooldownEndsAt = os.clock() + math.max(remaining, 0)
	if remaining > 0 and not ticking then
		ticking = RunService.Heartbeat:Connect(updateCooldown)
	end
	updateCooldown()

	local target = pendingTarget
	pendingTarget = nil
	if remaining > 0 and target and Markers[target] then
		Markers[target]:Confirm()
	end
end

local function requestTeleport(target: Player)
	if not enabled or not isAvailable() then return end
	if target == player or not target.Parent then return end

	local marker = Markers[target]
	if marker then
		marker:Press()
	end

	pendingTarget = target
	Teleport:FireServer(target)
end

Teleport.OnClientEvent:Connect(setCooldown)

local function findCursorDot(): GuiObject?
	local cursor = playerGui:FindFirstChild("Cursor")
	local holder = cursor and cursor:FindFirstChild("Frame")
	return if holder and holder:IsA("GuiObject") then holder else nil
end

local cursorDot: GuiObject? = findCursorDot()

local function aimsAtCentre(): boolean
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then return true end
	return not UserInputService.MouseIconEnabled
		or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function aimPoint(camera: Camera): Vector2
	local inset = GuiService:GetGuiInset()

	if not aimsAtCentre() then
		return UserInputService:GetMouseLocation() - inset
	end

	local dot = cursorDot
	if dot and dot.Visible and dot.AbsoluteSize.X > 0 then
		return dot.AbsolutePosition + dot.AbsoluteSize / 2
	end

	return (camera.ViewportSize - inset) / 2
end

local focused: any = nil
local pulse = 0

local function setFocused(marker: any)
	if focused == marker then return end
	if focused then
		focused:SetFocused(false)
	end
	focused = marker
	if marker then
		marker:SetFocused(true)
	end
end

local function render(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end

	pulse = (pulse + deltaTime * TAU / FOCUS.PulsePeriod) % TAU

	local aim = aimPoint(camera)
	local viewportHeight = camera.ViewportSize.Y
	local uiScale = math.clamp(viewportHeight / MARKER.ReferenceHeight, MARKER.MinScale, MARKER.MaxScale)
	local radius = math.clamp(viewportHeight * FOCUS.RadiusScale, FOCUS.MinRadius, FOCUS.MaxRadius)
	local available = isAvailable()
	local eye = camera.CFrame.Position

	local nearest, nearestDistance = nil, math.huge
	for _, marker in Markers do
		marker:SetUiScale(uiScale)

		local anchor = marker:GetAnchor()
		if not anchor then
			continue
		end

		local position = anchor.Position + MARKER.Offset
		local screen, onScreen = camera:WorldToScreenPoint(position)
		if onScreen then
			local offset = (Vector2.new(screen.X, screen.Y) - aim).Magnitude
			local limit = if marker == focused then radius * FOCUS.ReleaseSlack else radius
			if offset <= limit and offset < nearestDistance then
				nearest, nearestDistance = marker, offset
			end
		end

		if marker == focused then
			marker:SetAvailable(available)
			if MARKER.ShowDistance then
				marker:SetDistanceText(
					if available
						then string.format(MARKER.DistanceFormat, math.round((position - eye).Magnitude))
						else string.format(PlayerLocatorConfig.MarkerCooldownFormat, math.ceil(cooldownEndsAt - os.clock()))
				)
			end
		end

		marker:Pulse(pulse)
	end

	setFocused(nearest)
end

local function setRendering(shouldRender: boolean)
	if shouldRender then
		RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 1, render)
	else
		RunService:UnbindFromRenderStep(RENDER_JOB)
		setFocused(nil)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not enabled or not focused then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not aimsAtCentre() then return end

	requestTeleport(focused.Player)
end)

local function askFriendship(target: Player)
	local userId = target.UserId
	if Friends[userId] ~= nil or Asking[userId] then return end

	Asking[userId] = true
	task.spawn(function()
		local success, result = pcall(player.IsFriendsWith, player, userId)
		Asking[userId] = nil
		Friends[userId] = success and result == true
		refresh()
	end)
end

local function shouldMark(target: Player): boolean
	if target == player then return false end
	if not MODES[modeIndex].Friends then return true end

	askFriendship(target)
	return Friends[target.UserId] == true
end

local function drop(target: Player)
	local marker = Markers[target]
	if not marker then return end
	if focused == marker then
		focused = nil
	end
	marker:Destroy()
	Markers[target] = nil
end

local refreshing = false
local refreshQueued = false

local function rebuild()
	if not enabled then
		for target in Markers do
			drop(target)
		end
		return
	end

	local host = markerHost()
	for _, target in Players:GetPlayers() do
		local wanted = shouldMark(target)
		if wanted and not Markers[target] then
			Markers[target] = LocatorMarker.new(target, host, requestTeleport)
		elseif not wanted and Markers[target] then
			drop(target)
		end
	end
end

function refresh()
	if refreshing then
		refreshQueued = true
		return
	end

	refreshing = true
	repeat
		refreshQueued = false
		local ok, err = pcall(rebuild)
		if not ok then
			refreshing = false
			error(err, 0)
		end
	until not refreshQueued
	refreshing = false
end

function PlayerLocatorService:SetEnabled(value: boolean)
	local wanted = value == true
	if enabled == wanted then return end

	enabled = wanted
	gui.Enabled = enabled
	refresh()
	updateCooldown()
	setRendering(enabled)
end

function PlayerLocatorService:IsEnabled(): boolean
	return enabled
end

local function forget(target: Player)
	drop(target)
	Friends[target.UserId] = nil
	Asking[target.UserId] = nil
end

local function setMode(index: number)
	modeIndex = (index - 1) % #MODES + 1
	modeLabel.Text = MODES[modeIndex].Label
	refresh()
end

toggle.Activated:Connect(function()
	setMode(modeIndex + 1)
end)

function PlayerLocatorService:GetMode(): string
	return MODES[modeIndex].Id
end

Players.PlayerAdded:Connect(refresh)
Players.PlayerRemoving:Connect(forget)

gui.Enabled = false
setMode(1)
setCooldown(0)

return PlayerLocatorService
