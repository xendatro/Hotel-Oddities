local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocatorMarker = require(ReplicatedStorage.Classes.LocatorMarker)
local PlayerLocatorConfig = require(ReplicatedStorage.Configs.PlayerLocatorConfig)

--- Drives the PlayerLocator gui: the mode toggle, the outlines over everyone the mode includes, and
--- the countdown after a teleport.
---
--- The mode is a display choice and lives only here. There is nothing to validate about it -- "All
--- Players" is open to everyone, so a client claiming to be in it is claiming nothing. The teleport
--- itself is the server's, and so is its cooldown; this only counts down what the server reports.
local PlayerLocatorService = {}

if not RunService:IsClient() then
	return PlayerLocatorService
end

local Teleport = ReplicatedStorage.Communication.PlayerLocator.Teleport

local MODES = PlayerLocatorConfig.Modes
local GUI_TIMEOUT = 10

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("PlayerLocator", GUI_TIMEOUT)
local frame = gui and gui:WaitForChild("Mode", GUI_TIMEOUT)
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

local markerFolder = Instance.new("Folder")
markerFolder.Name = "PlayerLocatorMarkers"
markerFolder.Parent = playerGui

local Markers: { [Player]: any } = {}
--- nil while the answer has not come back yet, which reads as "not a friend" until it does.
local Friends: { [number]: boolean } = {}
local Asking: { [number]: boolean } = {}
local modeIndex = 1
local enabled = false

--- Teleport ---------------------------------------------------------------------------------------

local cooldownEndsAt = 0
local ticking: RBXScriptConnection? = nil

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

--- Starts the on-screen countdown from what the server says is left. Always the server's figure, so
--- a request refused for being early corrects the label rather than leaving it out of step.
local function setCooldown(remaining: number)
	cooldownEndsAt = os.clock() + math.max(remaining, 0)
	if remaining > 0 and not ticking then
		ticking = RunService.Heartbeat:Connect(updateCooldown)
	end
	updateCooldown()
end

local function requestTeleport(target: Player)
	if not enabled then return end
	if os.clock() < cooldownEndsAt then return end
	if target == player or not target.Parent then return end

	Teleport:FireServer(target)
end

Teleport.OnClientEvent:Connect(setCooldown)

--- Who is marked ----------------------------------------------------------------------------------

local refresh

--- Asks Roblox whether `target` is a friend, once per player per session. The call yields, so the
--- markers are built without it and rebuilt when the answer lands.
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

function refresh()
	if not enabled then
		for target, marker in Markers do
			marker:Destroy()
			Markers[target] = nil
		end
		return
	end

	for _, target in Players:GetPlayers() do
		local wanted = shouldMark(target)
		if wanted and not Markers[target] then
			Markers[target] = LocatorMarker.new(target, markerFolder, requestTeleport)
		elseif not wanted and Markers[target] then
			Markers[target]:Destroy()
			Markers[target] = nil
		end
	end
end

--- Enables the locator only for the tool's equipped lifetime.
function PlayerLocatorService:SetEnabled(value: boolean)
	enabled = value == true
	gui.Enabled = enabled
	refresh()
	updateCooldown()
end

function PlayerLocatorService:IsEnabled(): boolean
	return enabled
end

local function forget(target: Player)
	if Markers[target] then
		Markers[target]:Destroy()
		Markers[target] = nil
	end
	Friends[target.UserId] = nil
	Asking[target.UserId] = nil
end

--- Mode -------------------------------------------------------------------------------------------

local function setMode(index: number)
	modeIndex = (index - 1) % #MODES + 1
	modeLabel.Text = MODES[modeIndex].Label
	refresh()
end

toggle.Activated:Connect(function()
	setMode(modeIndex + 1)
end)

--- The mode currently selected, as one of the ids in `PlayerLocatorConfig.Modes`.
function PlayerLocatorService:GetMode(): string
	return MODES[modeIndex].Id
end

Players.PlayerAdded:Connect(refresh)
Players.PlayerRemoving:Connect(forget)

gui.Enabled = false
setMode(1)
setCooldown(0)

return PlayerLocatorService
