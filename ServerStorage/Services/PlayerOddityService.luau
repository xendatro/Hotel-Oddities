local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.PlayerOddityConfig)

local PlayerOddityService = {}

if RunService:IsStudio() and not RunService:IsRunning() then
	function PlayerOddityService:Trigger(_player: Player, _kind: string?): (boolean, string?, string?)
		return false, nil, "player oddities are disabled in Studio edit mode"
	end
	return PlayerOddityService
end

local function getHeadStareRemote(): RemoteEvent
	local communication = ReplicatedStorage:FindFirstChild("Communication")
	if not communication then
		communication = Instance.new("Folder")
		communication.Name = "Communication"
		communication.Parent = ReplicatedStorage
	end

	local oddities = communication:FindFirstChild("Oddities")
	if not oddities then
		oddities = Instance.new("Folder")
		oddities.Name = "Oddities"
		oddities.Parent = communication
	end

	local remote = oddities:FindFirstChild("HeadStare")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "HeadStare"
		remote.Parent = oddities
	end
	return remote :: RemoteEvent
end

local HeadStare = getHeadStareRemote()

if not Config.Enabled then
	function PlayerOddityService:Trigger(_player: Player, _kind: string?): (boolean, string?, string?)
		return false, nil, "player oddities are disabled"
	end
	return PlayerOddityService
end

type ActiveEffect = {
	Token: number,
	Character: Model,
	Cleanup: () -> (),
	Died: RBXScriptConnection?,
}

local active: { [Player]: ActiveEffect } = {}
local nextToken = 0

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

local function getLivingCharacter(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then return nil, nil end
	return character, humanoid
end

local function livingPlayerCount(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if getLivingCharacter(player) then
			count += 1
		end
	end
	return count
end

local function clear(player: Player, token: number?)
	local effect = active[player]
	if not effect or (token and effect.Token ~= token) then return end

	active[player] = nil
	if effect.Died then
		effect.Died:Disconnect()
	end
	effect.Cleanup()
end

local function applySize(character: Model): () -> ()
	local originalScale = character:GetScale()
	local options = Config.SizeOptions
	local factor = options[math.random(1, #options)]
	character:ScaleTo(originalScale * factor)

	return function()
		if character.Parent then
			character:ScaleTo(originalScale)
		end
	end
end

local function applyTransparency(character: Model): () -> ()
	local original: { [BasePart]: number } = {}

	local function apply(instance: Instance)
		if not instance:IsA("BasePart") or instance.Transparency ~= 0 then return end
		original[instance] = 0
		instance.Transparency = Config.OddTransparency
	end

	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end
	local added = character.DescendantAdded:Connect(apply)

	return function()
		added:Disconnect()
		for part, transparency in original do
			if part.Parent then
				part.Transparency = transparency
			end
		end
	end
end

local function start(player: Player, kind: string, character: Model, humanoid: Humanoid): boolean
	if active[player] then return false end

	nextToken += 1
	local token = nextToken
	local duration = randomRange(Config.MinDuration, Config.MaxDuration)
	local cleanup: () -> ()

	if kind == "Size" then
		cleanup = applySize(character)
	elseif kind == "Transparency" then
		cleanup = applyTransparency(character)
	elseif kind == "HeadStare" then
		HeadStare:FireClient(player, duration)
		cleanup = function()
			if player.Parent == Players then
				HeadStare:FireClient(player, 0)
			end
		end
	else
		return false
	end

	local effect: ActiveEffect = {
		Token = token,
		Character = character,
		Cleanup = cleanup,
		Died = nil,
	}
	active[player] = effect
	effect.Died = humanoid.Died:Connect(function()
		clear(player, token)
	end)

	task.delay(duration, function()
		clear(player, token)
	end)
	return true
end

local function livingPlayers(): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		local character = getLivingCharacter(player)
		if character and not active[player] then
			table.insert(result, player)
		end
	end
	return result
end

local function chooseKind(playerCount: number): string?
	local total = 0
	for kind, weight in Config.EffectWeights do
		if kind ~= "HeadStare" or playerCount >= Config.MinimumPlayersForHeadStare then
			total += weight
		end
	end
	if total <= 0 then return nil end

	local roll = math.random() * total
	for kind, weight in Config.EffectWeights do
		if kind == "HeadStare" and playerCount < Config.MinimumPlayersForHeadStare then continue end
		roll -= weight
		if roll <= 0 then return kind end
	end
	return nil
end

function PlayerOddityService:Trigger(player: Player, kind: string?): (boolean, string?, string?)
	if not Config.Enabled then return false, nil, "player oddities are disabled" end

	local character, humanoid = getLivingCharacter(player)
	if not character or not humanoid then return false, nil, "that player has no living character" end
	if active[player] then return false, nil, `{player.Name} already has an oddity` end

	if kind and kind ~= "Size" and kind ~= "Transparency" and kind ~= "HeadStare" then
		return false, nil, "unknown effect; use size, transparency, or stare"
	end
	if kind == "HeadStare" and livingPlayerCount() < Config.MinimumPlayersForHeadStare then
		return false, nil, "stare needs at least 2 other living players"
	end

	local chosen = kind or chooseKind(#livingPlayers())
	if not chosen then return false, nil, "no oddity is available right now" end
	if not start(player, chosen, character, humanoid) then
		return false, nil, "could not start that oddity"
	end
	return true, chosen, nil
end

local function roll()
	if math.random() > Config.TriggerChance then return end

	local candidates = livingPlayers()
	if #candidates == 0 then return end

	local player = candidates[math.random(1, #candidates)]
	local character, humanoid = getLivingCharacter(player)
	if not character or not humanoid then return end

	PlayerOddityService:Trigger(player)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		clear(player)
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player)
	clear(player)
	active[player] = nil
end)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

task.spawn(function()
	task.wait(Config.InitialDelay)
	while true do
		roll()
		task.wait(Config.RollInterval)
	end
end)

return PlayerOddityService
