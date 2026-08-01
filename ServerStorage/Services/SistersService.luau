--- Places command-spawned Sisters. There is nothing to plan: they carry no warning, they are given
--- no route, and they never leave, so all this decides is which corridor they walk out of and which
--- way they are facing when they do. Automatic enemy scheduling does not belong here; when that
--- system arrives it can call Spawn through the same public boundary.

local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local HallwayGraphService = require(ServerStorage.Services.HallwayGraphService)

type RouteNode = HallwayGraphService.RouteNode

local SistersService = {}
local Config = EnemyConfigs.Sisters

local function walkPosition(node: RouteNode): Vector3
	return node.Position + Vector3.yAxis * Config.RouteHeight
end

-- The corner they set off towards. A dead-end neighbor is the one opening worth avoiding: it would
-- have them turn round in front of whoever they were walking towards.
local function chooseOpening(node: RouteNode): RouteNode?
	local openings = {}
	local anywhere = {}
	for neighbor in node.Neighbors do
		table.insert(anywhere, neighbor)
		if HallwayGraphService:CountExits(neighbor) > 1 then
			table.insert(openings, neighbor)
		end
	end
	if #openings == 0 then
		openings = anywhere
	end
	return if #openings > 0 then openings[math.random(1, #openings)] else nil
end

--- Puts one pair in a corridor far enough from everybody that they are walked into rather than
--- landed on. False when the map offered no such corridor.
function SistersService:Spawn(): boolean
	local candidates = {}
	for _, node in HallwayGraphService:Build() do
		if HallwayGraphService:CountExits(node) > 1
			and HallwayGraphService:IsFarFromPlayers(node.Position, Config.SpawnPlayerDistance) then
			table.insert(candidates, node)
		end
	end
	if #candidates == 0 then return false end

	local startNode = candidates[math.random(1, #candidates)]
	local firstNode = chooseOpening(startNode)
	if not firstNode then return false end

	local spawnCFrame = CFrame.lookAt(walkPosition(startNode), walkPosition(firstNode))
	return EnemyService:Spawn("Sisters", spawnCFrame, startNode, firstNode) ~= nil
end

return SistersService
