local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local START_ATTRIBUTE = "PerfLogServerStart"
local PREFIX = "[PerfLog]"

local PerfLog = {}

local remote: RemoteEvent? = nil

local function ensure(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then return existing end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local function getRemote(): RemoteEvent
	if remote then return remote end

	if RunService:IsServer() then
		local communication = ensure(ReplicatedStorage, "Communication", "Folder")
		remote = ensure(communication, "PerfLog", "RemoteEvent") :: RemoteEvent
	else
		remote = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("PerfLog") :: RemoteEvent
	end
	return remote :: RemoteEvent
end

if RunService:IsServer() and FLAGS.PerfLog then
	getRemote()
	if ReplicatedStorage:GetAttribute(START_ATTRIBUTE) == nil then
		ReplicatedStorage:SetAttribute(START_ATTRIBUTE, Workspace:GetServerTimeNow())
	end
end

function PerfLog.Now(): number
	local start = ReplicatedStorage:GetAttribute(START_ATTRIBUTE)
	if type(start) ~= "number" then return 0 end
	return Workspace:GetServerTimeNow() - start
end

function PerfLog.Format(timestamp: number): string
	local minutes = math.floor(timestamp / 60)
	return string.format("%02d:%06.3f", minutes, timestamp - minutes * 60)
end

function PerfLog.Print(topic: string, action: string, timestamp: number?)
	print(`{PREFIX}[{topic}] {action} @ {PerfLog.Format(timestamp or PerfLog.Now())}`)
end

function PerfLog.Alert(topic: string, action: string, timestamp: number?)
	warn(`{PREFIX}[{topic}] {action} @ {PerfLog.Format(timestamp or PerfLog.Now())}`)
end

function PerfLog.Log(topic: string, action: string)
	if not FLAGS.PerfLog then return end

	if RunService:IsServer() then
		getRemote():FireAllClients(topic, action, PerfLog.Now())
	else
		PerfLog.Print(topic, action)
	end
end

function PerfLog.GetRemote(): RemoteEvent
	return getRemote()
end

return PerfLog
