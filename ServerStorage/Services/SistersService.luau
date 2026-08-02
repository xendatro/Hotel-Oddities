--- Places the Sisters, for the director and for the chat command alike. There is nothing to plan:
--- they carry no warning and are given no route, so all this decides is which corridor they walk out
--- of and which way they are facing when they do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DangerMapService = require(ServerStorage.Services.DangerMapService)
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
--- landed on, drawn towards the worse end of the hotel. Returns the pair, or nil when the map offered
--- no such corridor.
function SistersService:Spawn(): any?
	local candidates = {}
	local cumulative = {}
	local total = 0

	for _, node in HallwayGraphService:Get() do
		if HallwayGraphService:CountExits(node) > 1
			and HallwayGraphService:IsFarFromPlayers(node.Position, Config.SpawnPlayerDistance) then
			-- A floor under the weight, so a hotel with no strongly dangerous corridors still gets a
			-- pair walking about somewhere rather than none at all.
			total += 0.1 + DangerMapService:GetDanger(node.Position) ^ (Config.DangerBias or 1)
			table.insert(candidates, node)
			table.insert(cumulative, total)
		end
	end
	if #candidates == 0 or total <= 0 then return nil end

	local roll = math.random() * total
	local startNode = candidates[#candidates]
	for index, ceiling in cumulative do
		if roll <= ceiling then
			startNode = candidates[index]
			break
		end
	end

	local firstNode = chooseOpening(startNode)
	if not firstNode then return nil end

	local spawnCFrame = CFrame.lookAt(walkPosition(startNode), walkPosition(firstNode))
	return EnemyService:Spawn("Sisters", spawnCFrame, startNode, firstNode)
end

return SistersService
