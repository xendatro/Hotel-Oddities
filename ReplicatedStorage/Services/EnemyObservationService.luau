local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ObservedFreezeConfig = require(ReplicatedStorage.Configs.ObservedFreezeConfig)
local Sightline = require(ReplicatedStorage.Modules.Sightline)

local REPORT_INTERVAL = 0.05
local OBSERVABLE_TAG = "Observable"

local EnemyObservationService = {}

if not FLAGS.Enemies then
	return EnemyObservationService
end

local UpdateView = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("UpdateView") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local accumulator = REPORT_INTERVAL
local lastSentAt = -math.huge
local pending = false

local Overrides: { [Model]: boolean } = {}

local function send()
	local character = localPlayer.Character
	local camera = workspace.CurrentCamera
	local frustum = camera and Sightline.Frustum(camera)
	if not (character and camera and frustum) then return end

	local observed = {}
	for _, model in CollectionService:GetTagged(OBSERVABLE_TAG) do
		if not model:IsA("Model") then continue end

		local override = Overrides[model]
		local seen = if override ~= nil then override else Sightline.CanSee(camera, frustum, character, model)
		if seen then
			table.insert(observed, model)
		end
	end

	lastSentAt = os.clock()
	pending = false
	accumulator = 0

	UpdateView:FireServer(observed, camera.CFrame.Position, camera.CFrame.LookVector)
end

function EnemyObservationService:SetSeen(model: Model, seen: boolean?)
	Overrides[model] = seen
end

function EnemyObservationService:Report()
	if os.clock() - lastSentAt < ObservedFreezeConfig.MinReportGap then
		pending = true
		return
	end
	send()
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	if not localPlayer.Character then return end

	if pending and os.clock() - lastSentAt >= ObservedFreezeConfig.MinReportGap then
		send()
		return
	end

	accumulator += deltaTime
	if accumulator < REPORT_INTERVAL then return end
	send()
end)

return EnemyObservationService
