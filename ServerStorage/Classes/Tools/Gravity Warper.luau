local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local WarpRemote = CommunicationService.Ensure("GravityWarp", "Warp")
local FinishedRemote = CommunicationService.Ensure("GravityWarp", "Finished")

local WARPING_ATTRIBUTE = "GravityWarping"
local FINISH_FALLBACK_SLACK = 5

local PendingFinishByPlayer: { [Player]: () -> () } = {}

FinishedRemote.OnServerEvent:Connect(function(player: Player)
	local finish = PendingFinishByPlayer[player]
	if finish then
		finish()
	end
end)

local GravityWarper = ServerTool.extend("GravityWarper")

function GravityWarper.new(tool: Tool)
	return ServerTool.new(tool, GravityWarper)
end

local function findCeiling(character: Model, root: BasePart, maxDistance: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	return workspace:Raycast(root.Position, Vector3.new(0, maxDistance, 0), params)
end

function GravityWarper:OnActivated()
	local player = self:GetPlayer()
	local character = player and player.Character
	local root = character and CharacterService.GetAliveRootFromCharacter(character)
	local humanoid = character and CharacterService.GetHumanoid(character)
	if not player or not character or not root or not humanoid then return end
	if character:GetAttribute(WARPING_ATTRIBUTE) then return end
	if not findCeiling(character, root, self.Config.MaxCeilingDistance) then return end

	local duration = self.Config.Duration
	local totalTime = self.Config.AscendTime + duration + self.Config.DescendTime

	if not self:Consume() then return end

	character:SetAttribute(WARPING_ATTRIBUTE, true)
	character:AddTag(Vanished.EyeExemptTag)

	local function finish()
		if PendingFinishByPlayer[player] == finish then
			PendingFinishByPlayer[player] = nil
		end
		if not character:GetAttribute(WARPING_ATTRIBUTE) then return end
		character:SetAttribute(WARPING_ATTRIBUTE, nil)
		character:RemoveTag(Vanished.EyeExemptTag)
	end

	PendingFinishByPlayer[player] = finish
	humanoid.Died:Once(finish)
	task.delay(totalTime + FINISH_FALLBACK_SLACK, finish)
	WarpRemote:FireClient(player, duration)
end

return GravityWarper
