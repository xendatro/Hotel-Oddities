local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local SistersConfig = require(ReplicatedStorage.Configs.SistersConfig)
local Vanished = require(ReplicatedStorage.Services.VanishedService)
local GravityWarpService = require(ServerStorage.Services.GravityWarpService)

local SistersGazeService = {}

local Config = SistersConfig.Gaze
local GazeRemote = CommunicationService.Ensure(SistersConfig.Remotes.Folder, SistersConfig.Remotes.Gaze)
local GazedRemote = CommunicationService.Ensure(SistersConfig.Remotes.Folder, SistersConfig.Remotes.Gazed)

local CooldownUntil: { [Player]: number } = {}
CharacterService.CleanupOnLeave(CooldownUntil)

local function isSister(instance: any): boolean
	return typeof(instance) == "Instance"
		and instance:IsA("Model")
		and instance:HasTag(SistersConfig.Tag)
		and instance:IsDescendantOf(workspace)
end

function SistersGazeService:IsOnCooldown(player: Player): boolean
	return os.clock() < (CooldownUntil[player] or 0)
end

function SistersGazeService:Catch(player: Player, sister: Model): boolean
	if self:IsOnCooldown(player) then return false end

	local character = player.Character
	local root = character and CharacterService.GetAliveRootFromCharacter(character)
	if not character or not root or Vanished.Is(character) then return false end

	local head = sister:FindFirstChild("Head") :: BasePart?
	if not head then return false end
	if (head.Position - root.Position).Magnitude > Config.Range + Config.ServerRangeSlack then return false end

	local leadTime = SistersConfig.Vertigo.LeadTime
	local duration = SistersConfig.Warp.Duration
	if not GravityWarpService:Warp(player, duration, leadTime) then return false end

	CooldownUntil[player] = os.clock() + leadTime + GravityWarpService:TravelTime(duration) + Config.Cooldown
	return true
end

GazeRemote.OnServerEvent:Connect(function(player: Player, sister: any)
	local caught = isSister(sister) and SistersGazeService:Catch(player, sister)
	GazedRemote:FireClient(player, caught, SistersConfig.Vertigo.LeadTime)
end)

return SistersGazeService
