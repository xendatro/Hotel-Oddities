local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.PlayerOddityConfig)
local OddityService = require(ServerStorage.Services.OddityService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local SCOPE = "Player"

local PlayerOddityService = {}

local active: { [Player]: any } = {}

local function disabledReason(): string
	if RunService:IsStudio() and not RunService:IsRunning() then
		return "player oddities are disabled in Studio edit mode"
	end
	return "player oddities are disabled"
end

local function isLiving(player: Player): boolean
	return CharacterService.GetAliveHumanoid(player) ~= nil
end

local function available(): { Player }
	local candidates = {}
	for _, player in Players:GetPlayers() do
		if isLiving(player) and not active[player] then
			table.insert(candidates, player)
		end
	end
	return candidates
end

local function clear(player: Player)
	local oddity = active[player]
	if not oddity then return end
	active[player] = nil
	oddity:Stop()
end

local function chooseKind(): string?
	local weights = Config.EffectWeights
	local usable = {}
	local total = 0

	for kind, weight in weights do
		local class = OddityService:Get(SCOPE, kind)
		if not class or type(weight) ~= "number" or weight <= 0 then continue end
		if not class.IsAvailable(class) then continue end

		usable[kind] = weight
		total += weight
	end

	if total <= 0 then return nil end

	local roll = math.random() * total
	for kind, weight in usable do
		roll -= weight
		if roll <= 0 then return kind end
	end
	return nil
end

function PlayerOddityService:Trigger(player: Player, kind: string?): (boolean, string?, string?)
	if not OddityService:IsEnabled(SCOPE) then return false, nil, disabledReason() end
	if not isLiving(player) then return false, nil, "that player has no living character" end
	if active[player] then return false, nil, `{player.Name} already has an oddity` end

	if kind and not OddityService:Get(SCOPE, kind) then
		return false, nil, "unknown effect; use size, headsize, transparency, or stare"
	end

	local chosen = kind or chooseKind()
	if not chosen then return false, nil, "no oddity is available right now" end

	local oddity, reason = OddityService:Start(OddityService:Get(SCOPE, chosen), player)
	if not oddity then return false, nil, reason or "could not start that oddity" end

	active[player] = oddity
	oddity:OnStopped(function()
		if active[player] == oddity then
			active[player] = nil
		end
	end)
	return true, chosen, nil
end

local function roll()
	if math.random() > Config.TriggerChance then return end

	local candidates = available()
	if #candidates == 0 then return end

	PlayerOddityService:Trigger(candidates[math.random(1, #candidates)])
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function()
		clear(player)
	end)
end

if OddityService:IsEnabled(SCOPE) then
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	task.spawn(function()
		task.wait(Config.InitialDelay)
		while true do
			roll()
			task.wait(Config.RollInterval)
		end
	end)
end

return PlayerOddityService
