local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NPC = require(ServerStorage.Classes.NPC)
local Eye = require(ServerStorage.Classes.Enemies.Eye)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local BALL_CONFIG = ToolConfigs.Ball

--- The single way an enemy gets held in place by a player. Both stun sources land here: the bear
--- trap calls :Stun directly from the server, and the paper ball arrives over a remote (so every
--- claim it makes has to be re-checked against the world before it counts).
local StunService = {}

--- Holds `model`'s enemy still for `duration` seconds. Returns whether anything was actually
--- stunned -- an unknown model or an enemy already stunned yields false.
function StunService:Stun(model: Instance?, duration: number): boolean
	local enemy = NPC.FromModel(model) or Eye.FromModel(model)
	if not enemy or not enemy.Active then return false end
	if enemy.StateMachine.State == "Stunned" then return false end

	enemy.StateMachine:SetState("Stunned", "Impact", enemy, duration)
	return enemy.StateMachine.State == "Stunned"
end

-- The paper ball's flight and hit detection play out on the thrower's client, so the server treats
-- the reported target as a claim: it must be a live enemy and it must be close enough to have been
-- hit from where the thrower is actually standing.
ReplicatedStorage.Communication.Ball.Hit.OnServerEvent:Connect(function(player: Player, model: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Eye is a stationary prop rather than an NPC, but a paper ball can still interrupt its stare.
	-- This lookup lives only on the ball path, so a TrapObject cannot stun an Eye by touching it.
	local enemy = NPC.FromModel(model) or Eye.FromModel(model)
	if not enemy or not enemy.Active then return end

	local targetPosition = if enemy.RootPart
		then enemy.RootPart.Position
		else model:GetPivot().Position
	if (targetPosition - root.Position).Magnitude > BALL_CONFIG.ServerRange then return end

	StunService:Stun(model, BALL_CONFIG.StunDuration)
end)

return StunService
