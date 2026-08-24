local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ObservedFreezeConfig = require(ReplicatedStorage.Configs.ObservedFreezeConfig)
local Sightline = require(ReplicatedStorage.Services.SightlineService)

local REPORT_INTERVAL = 0.05
local OBSERVABLE_TAG = "Observable"

local EnemyObservationService = {}

if not FLAGS.Enemies then
	return EnemyObservationService
end

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local UpdateView = CommunicationService.Get("Enemies", "UpdateView") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local accumulator = REPORT_INTERVAL
local lastSentAt = -math.huge
local pending = false

local Overrides: { [Model]: boolean } = {}
local ObservableModels: { Model } = {}
local ObservableIndices: { [Model]: number } = {}

local function addObservable(instance: Instance)
	if not instance:IsA("Model") or ObservableIndices[instance] then return end
	table.insert(ObservableModels, instance)
	ObservableIndices[instance] = #ObservableModels
end

local function removeObservable(instance: Instance)
	if not instance:IsA("Model") then return end
	local index = ObservableIndices[instance]
	if not index then return end

	local last = ObservableModels[#ObservableModels]
	ObservableModels[index] = last
	ObservableModels[#ObservableModels] = nil
	ObservableIndices[instance] = nil
	Overrides[instance] = nil
	if last ~= instance then ObservableIndices[last] = index end
end

CollectionService:GetInstanceAddedSignal(OBSERVABLE_TAG):Connect(addObservable)
CollectionService:GetInstanceRemovedSignal(OBSERVABLE_TAG):Connect(removeObservable)
for _, instance in CollectionService:GetTagged(OBSERVABLE_TAG) do
	addObservable(instance)
end

local observed: { Model } = {}
local lastSentSet: { [Model]: boolean } = {}
local lastSentCount = 0
local lastSentPosition: Vector3? = nil
local lastSentLook: Vector3? = nil

local function send(force: boolean?)
	local character = localPlayer.Character
	local camera = workspace.CurrentCamera
	local frustum = camera and Sightline.Frustum(camera)
	if not (character and camera and frustum) then return end

	table.clear(observed)
	local changed = false
	for _, model in ObservableModels do
		local override = Overrides[model]
		local seen = if override ~= nil then override else Sightline.CanSee(camera, frustum, character, model)
		if seen then
			table.insert(observed, model)
			if not lastSentSet[model] then
				changed = true
			end
		end
	end
	if #observed ~= lastSentCount then
		changed = true
	end

	local position = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local cameraMoved = lastSentPosition == nil
		or (position - lastSentPosition :: Vector3).Magnitude > 1e-2
		or (look - lastSentLook :: Vector3).Magnitude > 1e-3

	accumulator = 0
	if not force and not changed and not cameraMoved then return end

	table.clear(lastSentSet)
	for _, model in observed do
		lastSentSet[model] = true
	end
	lastSentCount = #observed
	lastSentPosition = position
	lastSentLook = look

	lastSentAt = os.clock()
	pending = false

	UpdateView:FireServer(observed, position, look)
end

function EnemyObservationService:SetSeen(model: Model, seen: boolean?)
	Overrides[model] = seen
end

function EnemyObservationService:Report()
	if os.clock() - lastSentAt < ObservedFreezeConfig.MinReportGap then
		pending = true
		return
	end
	send(true)
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	if not localPlayer.Character then return end

	if pending and os.clock() - lastSentAt >= ObservedFreezeConfig.MinReportGap then
		send(true)
		return
	end

	accumulator += deltaTime
	if accumulator < REPORT_INTERVAL then return end
	send()
end)

return EnemyObservationService
