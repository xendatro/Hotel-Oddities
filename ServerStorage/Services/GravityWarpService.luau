local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local GravityWarpService = {}

local WarpRemote = CommunicationService.Ensure("GravityWarp", "Warp")
local FinishedRemote = CommunicationService.Ensure("GravityWarp", "Finished")

local Config = ToolConfigs["Gravity Warper"]
local WARPING_ATTRIBUTE = "GravityWarping"
local FINISH_FALLBACK_SLACK = 5

GravityWarpService.WarpingAttribute = WARPING_ATTRIBUTE

local PendingFinishByPlayer: { [Player]: () -> () } = {}

FinishedRemote.OnServerEvent:Connect(function(player: Player)
	local finish = PendingFinishByPlayer[player]
	if finish then
		finish()
	end
end)

function GravityWarpService:FindCeiling(character: Model, root: BasePart, maxDistance: number?): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	return workspace:Raycast(root.Position, Vector3.new(0, maxDistance or Config.MaxCeilingDistance, 0), params)
end

function GravityWarpService:IsWarping(character: Model?): boolean
	return character ~= nil and character:GetAttribute(WARPING_ATTRIBUTE) == true
end

function GravityWarpService:TravelTime(duration: number?): number
	return Config.AscendTime + (duration or Config.Duration) + Config.DescendTime
end

local function resolve(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	local root = character and CharacterService.GetAliveRootFromCharacter(character)
	local humanoid = character and CharacterService.GetHumanoid(character)
	if not character or not root or not humanoid then return nil end
	if character:GetAttribute(WARPING_ATTRIBUTE) then return nil end
	if not GravityWarpService:FindCeiling(character, root) then return nil end
	return character, root, humanoid
end

function GravityWarpService:CanWarp(player: Player): boolean
	return resolve(player) ~= nil
end

function GravityWarpService:Warp(player: Player, duration: number?, leadTime: number?): boolean
	local character, _, humanoid = resolve(player)
	if not character or not humanoid then return false end

	local warpDuration = duration or Config.Duration
	local lead = math.max(leadTime or 0, 0)
	local totalTime = lead + self:TravelTime(warpDuration)

	character:SetAttribute(WARPING_ATTRIBUTE, true)
	character:AddTag(Vanished.EyeExemptTag)

	local function finish()
		if PendingFinishByPlayer[player] ~= finish then return end
		PendingFinishByPlayer[player] = nil
		character:SetAttribute(WARPING_ATTRIBUTE, nil)
		character:RemoveTag(Vanished.EyeExemptTag)
	end

	PendingFinishByPlayer[player] = finish
	humanoid.Died:Once(finish)
	task.delay(totalTime + FINISH_FALLBACK_SLACK, finish)

	if lead > 0 then
		task.delay(lead, function()
			if PendingFinishByPlayer[player] ~= finish then return end
			if not CharacterService.IsAlive(character) then
				finish()
				return
			end
			WarpRemote:FireClient(player, warpDuration)
		end)
	else
		WarpRemote:FireClient(player, warpDuration)
	end

	return true
end

return GravityWarpService
