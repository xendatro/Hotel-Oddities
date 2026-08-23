local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.VoiceDebugConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local VoiceActivityService = require(ServerStorage.Services.VoiceActivityService)
local WalkieTalkieService = require(ServerStorage.Services.WalkieTalkieService)

local VoiceDebugService = {}

if not (FLAGS.VoiceDebug and RunService:IsStudio()) then
	return VoiceDebugService
end

local EntriesById: { [string]: Config.Entry } = {}
for _, entry in Config.Entries do
	EntriesById[entry.Id] = entry
end

task.spawn(function()
	local setVolume = ReplicatedStorage
		:WaitForChild("Communication")
		:WaitForChild("VoiceDebug")
		:WaitForChild("SetVolume") :: RemoteEvent

	setVolume.OnServerEvent:Connect(function(player: Player, id: any, value: any)
		local entry = type(id) == "string" and EntriesById[id]
		if not entry or type(value) ~= "number" or value ~= value then return end

		entry.Table[entry.Key] = math.clamp(value, 0, entry.Maximum)
		VoiceActivityService:ApplyVolume()
		WalkieTalkieService:ApplyVolumes()
		warn(`[voice] {player.Name} set {entry.Label} to {entry.Table[entry.Key]}`)
	end)
end)

return VoiceDebugService
