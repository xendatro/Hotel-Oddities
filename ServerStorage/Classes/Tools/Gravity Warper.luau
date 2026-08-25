local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local WARPING_ATTRIBUTE = "GravityWarping"

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
	if not player or not character or not root then return end
	if character:GetAttribute(WARPING_ATTRIBUTE) then return end
	if not findCeiling(character, root, self.Config.MaxCeilingDistance) then return end
	if not self:Consume() then return end

	local duration = self.Config.Duration
	character:SetAttribute(WARPING_ATTRIBUTE, true)
	character:AddTag(Vanished.EyeExemptTag)
	self:Fire("Warp", duration)

	local function finish()
		if not character:GetAttribute(WARPING_ATTRIBUTE) then return end
		character:SetAttribute(WARPING_ATTRIBUTE, nil)
		character:RemoveTag(Vanished.EyeExemptTag)
	end

	local humanoid = CharacterService.GetHumanoid(character)
	if humanoid then
		humanoid.Died:Once(finish)
	end
	task.delay(duration + self.Config.DescendTime, finish)
end

return GravityWarper
