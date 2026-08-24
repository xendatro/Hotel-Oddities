local ServerStorage = game:GetService("ServerStorage")

local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local FixtureCommand = {}

local STAND_HEIGHT = 3.5

local function isAlive(target: any): boolean
	return typeof(target) ~= "Instance" or target.Parent ~= nil
end

local function describe(target: any): string
	return if typeof(target) == "Instance" then target:GetFullName() else tostring(target.Id)
end

local function anchorOf(pool: any, target: any): Vector3
	if typeof(target) == "Instance" then return target:GetPivot().Position end
	return pool:PointFor(target) or target.Point
end

local function fire(pool: any, target: any): boolean
	local trigger = pool.Drop or pool.Trigger
	return trigger(pool, target)
end

local function nearestArmed(pool: any, position: Vector3): (any?, number)
	local best: any? = nil
	local bestDistance = math.huge

	for _, target in pool:GetArmed() do
		if not isAlive(target) then continue end
		local point = pool:PointFor(target) or anchorOf(pool, target)
		local distance = (point - position).Magnitude
		if distance < bestDistance then
			best = target
			bestDistance = distance
		end
	end

	return best, bestDistance
end

local function landingSpot(pool: any, target: any): CFrame?
	local floor = pool:PointFor(target)
	if not floor then return nil end

	local pivot = anchorOf(pool, target)
	local stand = floor + Vector3.yAxis * STAND_HEIGHT
	local facing = Vector3.new(pivot.X, stand.Y, pivot.Z)
	if (facing - stand).Magnitude < 1e-3 then return CFrame.new(stand) end
	return CFrame.lookAt(stand, facing)
end

local function run(pool: any, label: string, player: Player, argument: string?)
	local command = argument and argument:lower()
	if command and command:match("^swing") then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		warn(`[{label}] {player.Name} has no character`)
		return
	end

	if command == "drop" or command == "fall" or command == "run" then
		local target, gap = pool:Nearest(root.Position)
		if not target then
			warn(`[{label}] none found near you`)
		elseif fire(pool, target) then
			warn(`[{label}] triggered {describe(target)} {math.floor(gap)} studs away`)
		else
			warn(`[{label}] {describe(target)} would not trigger`)
		end
		return
	end

	local target, distance = nearestArmed(pool, root.Position)
	if not target then
		warn(`[{label}] nothing is armed right now`)
		return
	end

	local spot = landingSpot(pool, target)
	if not spot then
		warn(`[{label}] could not find hallway floor beside {describe(target)}`)
		return
	end

	character:PivotTo(spot)
	warn(
		`[{label}] moved {player.Name} {math.floor(distance)} studs to {describe(target)}; `
			.. `walk out past {pool:ArmDistance()} studs and back to trigger it`
	)
end

function FixtureCommand.Bind(pool: any, label: string, names: { string })
	local aliases = {}
	for index = 2, #names do
		table.insert(aliases, names[index])
	end

	ChatCommandService.Register(names[1], {
		Aliases = aliases,
		Handler = function(player: Player, argument: string?)
			run(pool, label, player, argument)
		end,
	})
end

return FixtureCommand
