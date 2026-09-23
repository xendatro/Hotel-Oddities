local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local IntroCutsceneConfig = require(ReplicatedStorage.Configs.IntroCutsceneConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local IntroCutsceneService = {}

type Session = {
	Trigger: string,
	StartedAt: number,
}

local REMOTES = IntroCutsceneConfig.Remotes
local TRIGGERS = IntroCutsceneConfig.Triggers
local OUTCOMES = IntroCutsceneConfig.Outcomes
local STREAMING = IntroCutsceneConfig.Streaming
local VERSION = IntroCutsceneConfig.Version
local SEEN_ATTRIBUTE = IntroCutsceneConfig.SeenAttribute
local ANALYTICS_EVENT = "IntroCutscene"
local SESSION_GRACE = 5
local LONGEST_SESSION = IntroCutsceneConfig.Length + SESSION_GRACE
local WATCHED_SHARE = 0.5
local PREPARE_INTERVAL = 20
local START_INTERVAL = 5
local FINISH_INTERVAL = 1

local PrepareRemote = CommunicationService.Ensure(REMOTES.Folder, REMOTES.Prepare) :: RemoteEvent
local StartedRemote = CommunicationService.Ensure(REMOTES.Folder, REMOTES.Started) :: RemoteEvent
local FinishedRemote = CommunicationService.Ensure(REMOTES.Folder, REMOTES.Finished) :: RemoteEvent
local QueueRemote = CommunicationService.Ensure(REMOTES.Folder, REMOTES.Queue) :: RemoteEvent

local Sessions: { [Player]: Session } = {}
local Pending: { [Player]: boolean } = {}
local Commanded: { [Player]: true } = {}
local Streaming: { [Player]: true } = {}
local LastRequest: { [Player]: { [string]: number } } = {}

local function valuesOf(map: { [string]: string }, except: string?): { [string]: true }
	local set: { [string]: true } = {}
	for _, value in map do
		if type(value) == "string" and value ~= except then
			set[value] = true
		end
	end
	return set
end

local VALID_TRIGGERS = valuesOf(TRIGGERS)
local VALID_OUTCOMES = valuesOf(OUTCOMES, OUTCOMES.Left)

local function readVersion(profile: any): number
	local version = tonumber(profile.Data.IntroVersion)
	if not version or version ~= version or version < 0 or version == math.huge then
		return 0
	end
	return math.floor(version)
end

local function publish(player: Player)
	if not DataSaveService:Get(player) or not player:IsDescendantOf(Players) then return end
	player:SetAttribute(SEEN_ATTRIBUTE, IntroCutsceneService:HasSeen(player))
end

local function record(player: Player, seen: boolean)
	local profile = DataSaveService:Get(player)
	if profile then
		Pending[player] = nil
		profile.Data.IntroVersion = if seen then math.max(readVersion(profile), VERSION) else 0
	elseif player:IsDescendantOf(Players) then
		Pending[player] = seen
	end
	publish(player)
end

local function loadPlayer(player: Player)
	local profile = DataSaveService:Wait(player)
	if not profile or not player:IsDescendantOf(Players) then return end

	local pending = Pending[player]
	Pending[player] = nil

	local version = readVersion(profile)
	if pending == true then
		version = math.max(version, VERSION)
	elseif pending == false then
		version = 0
	end
	profile.Data.IntroVersion = version
	publish(player)
end

local function throttled(player: Player, key: string, interval: number): boolean
	local now = os.clock()
	local times = LastRequest[player]
	if not times then
		times = {}
		LastRequest[player] = times
	end
	local last = times[key]
	if last and now - last < interval then return true end
	times[key] = now
	return false
end

local function resolveTrigger(player: Player, trigger: string): string
	local commanded = Commanded[player]
	Commanded[player] = nil
	if commanded and trigger == TRIGGERS.Command then return TRIGGERS.Command end
	return if IntroCutsceneService:HasSeen(player) then TRIGGERS.Replay else TRIGGERS.First
end

local function close(player: Player, outcome: string)
	local session = Sessions[player]
	if not session then return end
	Sessions[player] = nil

	local seconds = math.clamp(os.clock() - session.StartedAt, 0, LONGEST_SESSION)
	if outcome == OUTCOMES.Watched and seconds < IntroCutsceneConfig.Length * WATCHED_SHARE then
		outcome = OUTCOMES.Skipped
	end
	if session.Trigger == TRIGGERS.Command then return end

	AnalyticsService:LogEvent(player, ANALYTICS_EVENT, math.round(seconds), {
		Outcome = outcome,
		Trigger = session.Trigger,
	}, outcome == OUTCOMES.Left)
end

local function stream(player: Player)
	Streaming[player] = true
	for _, point in STREAMING.Points do
		if player.Parent ~= Players then break end
		if typeof(point) == "Vector3" then
			pcall(player.RequestStreamAroundAsync, player, point, STREAMING.Timeout)
		end
	end
	Streaming[player] = nil
end

function IntroCutsceneService:HasSeen(player: Player): boolean
	local pending = Pending[player]
	if pending ~= nil then return pending end

	local profile = DataSaveService:Get(player)
	return profile ~= nil and readVersion(profile) >= VERSION
end

function IntroCutsceneService:MarkSeen(player: Player)
	record(player, true)
end

function IntroCutsceneService:Reset(player: Player)
	record(player, false)
end

function IntroCutsceneService:Queue(player: Player)
	if player.Parent ~= Players then return end
	Commanded[player] = true
	QueueRemote:FireClient(player)
end

PrepareRemote.OnServerEvent:Connect(function(player: Player)
	if player.Parent ~= Players or Streaming[player] or not workspace.StreamingEnabled then return end
	if throttled(player, REMOTES.Prepare, PREPARE_INTERVAL) then return end
	task.spawn(stream, player)
end)

StartedRemote.OnServerEvent:Connect(function(player: Player, trigger: any)
	if player.Parent ~= Players then return end
	if type(trigger) ~= "string" or not VALID_TRIGGERS[trigger] then return end
	if throttled(player, REMOTES.Started, START_INTERVAL) then return end

	close(player, OUTCOMES.Interrupted)
	Sessions[player] = { Trigger = resolveTrigger(player, trigger), StartedAt = os.clock() }
	IntroCutsceneService:MarkSeen(player)
end)

FinishedRemote.OnServerEvent:Connect(function(player: Player, outcome: any)
	if player.Parent ~= Players or not Sessions[player] then return end
	if type(outcome) ~= "string" or not VALID_OUTCOMES[outcome] then return end
	if throttled(player, REMOTES.Finished, FINISH_INTERVAL) then return end
	close(player, outcome)
end)

CharacterService.ForEachPlayer(loadPlayer)
CharacterService.CleanupOnLeave(Pending)
CharacterService.CleanupOnLeave(Commanded)
CharacterService.CleanupOnLeave(Streaming)
CharacterService.CleanupOnLeave(LastRequest)
Players.PlayerRemoving:Connect(function(player: Player)
	close(player, OUTCOMES.Left)
end)

return IntroCutsceneService
