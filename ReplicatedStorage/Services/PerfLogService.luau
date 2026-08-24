local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local PerfLog = require(ReplicatedStorage.Modules.PerfLog)

local PerfLogService = {}

if not RunService:IsClient() or not FLAGS.PerfLog then
	return PerfLogService
end

local SPIKE_FRAME_TIME = 0.1
local SPIKE_COOLDOWN = 1
local WINDOW = 1
local DROP_FRACTION = 0.7
local DROP_FLOOR = 50
local BURST_THRESHOLD = 60

local localPlayer = Players.LocalPlayer

PerfLog.GetRemote().OnClientEvent:Connect(function(topic: any, action: any, timestamp: any)
	if type(topic) ~= "string" or type(action) ~= "string" then return end
	PerfLog.Print(topic, action, if type(timestamp) == "number" then timestamp else nil)
end)

local frames, elapsed = 0, 0
local previousFps: number? = nil
local lastSpikeAt = 0

RunService.RenderStepped:Connect(function(deltaTime: number)
	if deltaTime >= SPIKE_FRAME_TIME and os.clock() - lastSpikeAt >= SPIKE_COOLDOWN then
		lastSpikeAt = os.clock()
		PerfLog.Alert("FPS", string.format("frame spike %dms", math.floor(deltaTime * 1000 + 0.5)))
	end

	frames += 1
	elapsed += deltaTime
	if elapsed < WINDOW then return end

	local fps = frames / elapsed
	frames, elapsed = 0, 0

	if previousFps and fps < previousFps * DROP_FRACTION and fps < DROP_FLOOR then
		PerfLog.Alert("FPS", string.format("drop %d -> %d", math.floor(previousFps + 0.5), math.floor(fps + 0.5)))
	end
	previousFps = fps
end)

local added, removed = 0, 0
local total = 0
local addedBy: { [string]: number } = {}
local removedBy: { [string]: number } = {}

local function bucketOf(instance: Instance): string
	local current = instance
	while current.Parent and current.Parent ~= workspace do
		current = current.Parent :: Instance
	end
	if current.Parent ~= workspace then return "Loose" end
	if Players:GetPlayerFromCharacter(current) then return "Characters" end

	local name = current.Name
	if string.match(name, "^Maze") or name == "Lobby" or name == "Demo" or current:IsA("Terrain") then
		return "Map"
	end
	if name == "ProgrammaticVents" then return "Vents" end
	return name
end

workspace.DescendantAdded:Connect(function(instance: Instance)
	added += 1
	total += 1
	local bucket = bucketOf(instance)
	addedBy[bucket] = (addedBy[bucket] or 0) + 1
end)
workspace.DescendantRemoving:Connect(function(instance: Instance)
	removed += 1
	total -= 1
	local bucket = bucketOf(instance)
	removedBy[bucket] = (removedBy[bucket] or 0) + 1
end)
total += #workspace:GetDescendants()

local function breakdown(): string
	local buckets = {}
	for bucket in addedBy do
		buckets[bucket] = true
	end
	for bucket in removedBy do
		buckets[bucket] = true
	end

	local parts = {}
	for bucket in buckets do
		table.insert(parts, {
			Bucket = bucket,
			Added = addedBy[bucket] or 0,
			Removed = removedBy[bucket] or 0,
		})
	end
	table.sort(parts, function(a, b)
		return a.Added + a.Removed > b.Added + b.Removed
	end)

	local pieces = {}
	for _, part in parts do
		table.insert(pieces, `{part.Bucket} +{part.Added}/-{part.Removed}`)
	end
	return table.concat(pieces, ", ")
end

task.spawn(function()
	while true do
		task.wait(WINDOW)
		if added >= BURST_THRESHOLD or removed >= BURST_THRESHOLD then
			PerfLog.Print("Instances", `+{added} -{removed} in {WINDOW}s, {total} total ({breakdown()})`)
		end
		added, removed = 0, 0
		table.clear(addedBy)
		table.clear(removedBy)
	end
end)

localPlayer.CharacterAdded:Connect(function()
	PerfLog.Log("Character", "respawn")
end)

return PerfLogService
