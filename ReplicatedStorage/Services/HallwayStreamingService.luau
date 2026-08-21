local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.StreamingConfig)

local HallwayStreamingService = {}

if not RunService:IsClient() then
	return HallwayStreamingService
end

if not Config.Enabled then
	return HallwayStreamingService
end

local player = Players.LocalPlayer
local streaming = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Streaming")

local PrepareTeleport = streaming:WaitForChild("PrepareTeleport") :: RemoteEvent
local ClientReady = streaming:WaitForChild("ClientReady") :: RemoteEvent
local TeleportFailed = streaming:WaitForChild("TeleportFailed") :: RemoteEvent
local ExpectedModels = streaming:WaitForChild("ExpectedModels") :: RemoteEvent
local ReportMissing = streaming:WaitForChild("ReportMissing") :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name = "StreamingMessageGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 200
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Message"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.78)
frame.Size = UDim2.fromOffset(460, 56)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
frame.BackgroundTransparency = 0.12
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(130, 130, 140)
stroke.Transparency = 0.45
stroke.Parent = frame

local label = Instance.new("TextLabel")
label.Name = "Label"
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, -32, 1, -12)
label.Position = UDim2.fromOffset(16, 6)
label.Font = Enum.Font.GothamMedium
label.TextColor3 = Color3.fromRGB(238, 238, 244)
label.TextSize = 18
label.TextWrapped = true
label.Parent = frame

local messageToken = 0
local function showMessage(message: string)
	messageToken += 1
	local token = messageToken
	label.Text = message
	gui.Enabled = true
	task.delay(4, function()
		if messageToken == token then gui.Enabled = false end
	end)
end

local function arrivedModelNames(): { [string]: boolean }
	local arrived = {}
	for _, model in CollectionService:GetTagged(Config.ModelTag) do
		if model:IsDescendantOf(workspace) then arrived[model.Name] = true end
	end
	return arrived
end

local function arrivedModelIds(): { [string]: boolean }
	local arrived = {}
	for _, model in CollectionService:GetTagged(Config.ModelTag) do
		if not model:IsDescendantOf(workspace) then continue end
		local streamingId = model:GetAttribute(Config.ModelIdAttribute)
		if type(streamingId) == "string" then arrived[streamingId] = true end
	end
	return arrived
end

local expectedIds: { [string]: boolean } = {}
local receivedExpected = false
local expectedChangedAt = 0

ExpectedModels.OnClientEvent:Connect(function(ids: any)
	if type(ids) ~= "table" then return end
	table.clear(expectedIds)
	for _, streamingId in ids do
		if type(streamingId) == "string" then expectedIds[streamingId] = true end
	end
	receivedExpected = true
	expectedChangedAt = os.clock()
end)

task.spawn(function()
	while true do
		task.wait(Config.ReconcileInterval)
		if not receivedExpected then
			ReportMissing:FireServer({})
			continue
		end
		if os.clock() - expectedChangedAt < Config.ReconcileGraceTime then continue end

		local arrived = arrivedModelIds()
		local missing = {}
		for streamingId in expectedIds do
			if arrived[streamingId] then continue end
			table.insert(missing, streamingId)
			if #missing >= Config.MaxMissingReport then break end
		end
		if #missing > 0 then ReportMissing:FireServer(missing) end
	end
end)

PrepareTeleport.OnClientEvent:Connect(function(token: number, names: { string }, timeout: number?)
	local deadline = os.clock() + (timeout or Config.ClientReadyTimeout)
	local ready = false

	while os.clock() < deadline do
		local arrived = arrivedModelNames()
		ready = true
		for _, name in names or {} do
			if not arrived[name] then
				ready = false
				break
			end
		end
		if ready then break end
		RunService.Heartbeat:Wait()
	end

	ClientReady:FireServer(token, ready)
end)

TeleportFailed.OnClientEvent:Connect(function(message: any)
	showMessage(if type(message) == "string" then message else Config.FailureMessage)
end)

return HallwayStreamingService
