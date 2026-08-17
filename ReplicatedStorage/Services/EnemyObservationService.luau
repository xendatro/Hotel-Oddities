local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ObservedFreezeConfig = require(ReplicatedStorage.Configs.ObservedFreezeConfig)
local Sightline = require(ReplicatedStorage.Modules.Sightline)

local REPORT_INTERVAL = 0.05
-- Carried by the enemies that react to being seen, and only those: the report costs a raycast per
-- visible part, so an enemy that would ignore the answer is not worth asking about.
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

-- Answers somebody else has already worked out this frame, by model. `ObservedFreezeService` tests
-- the enemies it predicts for every frame rather than every report, and it tests them against where
-- it is drawing them rather than where they replicated to -- so its answer is both fresher than one
-- taken here and the only one that matches what the player is actually looking at. Taking it whole
-- also keeps the raycasts to one set per frame instead of two.
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

	-- Where this report was taken from and which way it was pointing, so the server can work out what
	-- else this player would see without having to guess at a camera it cannot reach. An enemy
	-- choosing somewhere to hide is asking exactly that question, and answering it off the character's
	-- own head is how you get a thing that hides behind furniture the camera is looking straight over.
	-- The direction is what turns "on screen" into "how far off the middle of the screen", which is
	-- the whole of what an Eye does with this.
	UpdateView:FireServer(observed, camera.CFrame.Position, camera.CFrame.LookVector)
end

--- Records what this client has already decided about `model` this frame, in place of the test this
--- service would otherwise run for it. Cleared with nil.
function EnemyObservationService:SetSeen(model: Model, seen: boolean?)
	Overrides[model] = seen
end

--- Sends a report now rather than on the next tick, for a client that has just noticed something it
--- should not have to wait fifty milliseconds to say. Cheap to call on an edge and wasteful to call
--- every frame: the timer is reset by a send either way, so an edge report replaces the next periodic
--- one instead of adding to it.
---
--- Held back and retried on the following frame when the last report was too recent, because the
--- server drops anything arriving inside its own rate limit -- and a report dropped for being eager
--- is strictly worse than one sent a frame late.
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
