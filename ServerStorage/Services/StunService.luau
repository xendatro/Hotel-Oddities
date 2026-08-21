local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NPC = require(ServerStorage.Classes.NPC)
local Eye = require(ServerStorage.Classes.Enemies.Eye)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local BALL_CONFIG = ToolConfigs.Ball

local StunService = {}

function StunService:Stun(model: Instance?, duration: number): boolean
	local enemy = NPC.FromModel(model) or Eye.FromModel(model)
	if not enemy or not enemy.Active then return false end
	if enemy.StateMachine.State == "Stunned" then return false end

	enemy.StateMachine:SetState("Stunned", "Impact", enemy, duration)
	return enemy.StateMachine.State == "Stunned"
end

ReplicatedStorage.Communication.Ball.Hit.OnServerEvent:Connect(function(player: Player, model: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local enemy = NPC.FromModel(model) or Eye.FromModel(model)
	if not enemy or not enemy.Active then return end

	local targetPosition = if enemy.RootPart
		then enemy.RootPart.Position
		else model:GetPivot().Position
	if (targetPosition - root.Position).Magnitude > BALL_CONFIG.ServerRange then return end

	StunService:Stun(model, BALL_CONFIG.StunDuration)
end)

return StunService
