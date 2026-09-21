local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NPC = require(ServerStorage.Classes.NPC)
local Eye = require(ServerStorage.Classes.Enemies.Eye)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local BALL_CONFIG = ToolConfigs.Ball

local StunService = {}

local function hasClearSight(character: Model, target: Model): boolean
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head or not head:IsA("BasePart") then return false end

	local targetHead = target:FindFirstChild("Head")
	local position = if targetHead and targetHead:IsA("BasePart")
		then targetHead.Position
		else target:GetPivot().Position
	local offset = position - head.Position
	if offset.Magnitude < 1e-3 then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(head.Position, offset, params)
	return result ~= nil and result.Instance:IsDescendantOf(target)
end

function StunService:Stun(model: Instance?, duration: number): boolean
	local enemy = NPC.FromModel(model) or Eye.FromModel(model)
	if not enemy or not enemy.Active then return false end
	if enemy.StateMachine.State == "Stunned" then return false end

	enemy.StateMachine:SetState("Stunned", "Impact", enemy, duration)
	return enemy.StateMachine.State == "Stunned"
end

function StunService:KillEye(model: Instance?): boolean
	local eye = Eye.FromModel(model)
	if not eye or not eye.Active then return false end

	eye:Despawn()
	return true
end

function StunService:KillNpc(model: Instance?): boolean
	local npc = NPC.FromModel(model)
	if not npc or not npc.Active then return false end

	npc:Despawn()
	return true
end

local Hit = CommunicationService.Get("Ball", "Hit")

Hit.OnServerEvent:Connect(function(player: Player, model: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local eye = Eye.FromModel(model)
	if not eye or not eye.Active then return end

	local targetPosition = if eye.RootPart
		then eye.RootPart.Position
		else model:GetPivot().Position
	if (targetPosition - root.Position).Magnitude > BALL_CONFIG.ServerRange then return end
	if not hasClearSight(character, model) then return end

	StunService:KillEye(model)
end)

return StunService
