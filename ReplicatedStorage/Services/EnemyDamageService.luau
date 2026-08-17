local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Vanished = require(game:GetService("ReplicatedStorage").Modules.Vanished)
local AnimationConfig = require(game:GetService("ReplicatedStorage").Configs.AnimationConfig)

local EnemyDamageService = {}

local localPlayer = Players.LocalPlayer
local character: Model? = localPlayer.Character
local connections: { [Model]: { RBXScriptConnection } } = {}
local attackTracks: { [Model]: { AnimationTrack } } = {}
local dead = false

local Kill = game:GetService("ReplicatedStorage")
	:WaitForChild("Communication")
	:WaitForChild("Death")
	:WaitForChild("Kill") :: RemoteEvent

local function playKillAnimation(enemy: Model)
	local tracks = attackTracks[enemy]
	if not tracks then
		tracks = {}
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		local enemyId = enemy:GetAttribute("EnemyId")
		local set = if type(enemyId) == "string" then AnimationConfig.Sets[enemyId] else nil
		local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid))
		if animator and set then
			for _, assetId in set.Attacks or {} do
				local animation = Instance.new("Animation")
				animation.AnimationId = `rbxassetid://{assetId}`
				local track = animator:LoadAnimation(animation)
				track.Priority = Enum.AnimationPriority.Action
				track.Looped = false
				table.insert(tracks, track)
			end
		end
		attackTracks[enemy] = tracks
	end
	if #tracks > 0 then
		tracks[math.random(#tracks)]:Play(0.2)
	end
end

local function getHumanoid(): Humanoid?
	local currentCharacter = character
	if not currentCharacter then return nil end
	return currentCharacter:FindFirstChildOfClass("Humanoid")
end

local function tryKill(enemy: Model, hit: BasePart)
	if dead or not character or not hit:IsDescendantOf(character) then return end
	if not enemy:IsDescendantOf(workspace) then return end
	if Vanished.Is(character) then return end
	-- Some enemies are scenery. A Watcher stands in corridors people walk down and has no attack at
	-- all, so brushing past one is not a death. Read at contact as the final guard; the server stamps
	-- the attribute before parenting, so it arrives with the model before the Enemy tag is added.
	if enemy:GetAttribute("Harmless") then return end

	local humanoid = getHumanoid()
	if not humanoid or humanoid.Health <= 0 then return end

	dead = true
	playKillAnimation(enemy)
	Kill:FireServer(enemy)
	humanoid.Health = 0
end

local function watchPart(enemy: Model, part: Instance, partConnections: { RBXScriptConnection })
	if not part:IsA("BasePart") then return end
	table.insert(partConnections, part.Touched:Connect(function(hit)
		tryKill(enemy, hit)
	end))
end

local function watchEnemy(instance: Instance)
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) or connections[instance] then return end

	local partConnections: { RBXScriptConnection } = {}
	connections[instance] = partConnections
	for _, descendant in instance:GetDescendants() do
		watchPart(instance, descendant, partConnections)
	end
	table.insert(partConnections, instance.DescendantAdded:Connect(function(descendant)
		watchPart(instance, descendant, partConnections)
	end))
end

local function unwatchEnemy(instance: Instance)
	if not instance:IsA("Model") then return end
	local partConnections = connections[instance]
	if not partConnections then return end
	connections[instance] = nil
	for _, connection in partConnections do
		connection:Disconnect()
	end
	attackTracks[instance] = nil
end

local function setCharacter(newCharacter: Model?)
	character = newCharacter
	dead = false
end

if not localPlayer then
	return EnemyDamageService
end

localPlayer.CharacterAdded:Connect(setCharacter)
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(watchEnemy)
CollectionService:GetInstanceRemovedSignal("Enemy"):Connect(unwatchEnemy)

for _, enemy in CollectionService:GetTagged("Enemy") do
	watchEnemy(enemy)
end

Kill.OnClientEvent:Connect(function(_victim: Player, enemy: Instance?)
	if enemy and enemy:IsA("Model") and enemy:IsDescendantOf(workspace) then
		playKillAnimation(enemy)
	end
end)

return EnemyDamageService
