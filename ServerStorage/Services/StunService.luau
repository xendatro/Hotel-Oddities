local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NPC = require(ServerStorage.Classes.NPC)

local BALL_STUN_DURATION = 3
local BALL_RANGE = 80 -- generous ceiling on the client's claimed throw, in studs

--- The single way an enemy gets held in place by a player. Both stun sources land here: the bear
--- trap calls :Stun directly from the server, and the paper ball arrives over a remote (so every
--- claim it makes has to be re-checked against the world before it counts).
local StunService = {}

--- Holds `model`'s enemy still for `duration` seconds. Returns whether anything was actually
--- stunned -- a model with no live NPC behind it, or one already stunned, yields false.
function StunService:Stun(model: Instance?, duration: number): boolean
	local npc = NPC.FromModel(model)
	if not npc or not npc.Active then return false end
	if npc.StateMachine.State == "Stunned" then return false end

	npc.StateMachine:SetState("Stunned", "Impact", npc, duration)
	return npc.StateMachine.State == "Stunned"
end

-- The paper ball's flight and hit detection play out on the thrower's client, so the server treats
-- the reported target as a claim: it must be a live enemy and it must be close enough to have been
-- hit from where the thrower is actually standing.
ReplicatedStorage.Communication.Ball.Hit.OnServerEvent:Connect(function(player: Player, model: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local npc = NPC.FromModel(model)
	if not npc or not npc.Active then return end
	if (npc.RootPart.Position - root.Position).Magnitude > BALL_RANGE then return end

	StunService:Stun(model, BALL_STUN_DURATION)
end)

return StunService
