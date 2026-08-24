local ServerStorage = game:GetService("ServerStorage")

local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local FixtureCommand = {}

local STAND_HEIGHT = 3.5

local function nearestArmed(pool: any, position: Vector3): (Model?, number)
	local best: Model? = nil
	local bestDistance = math.huge

	for _, model in pool:GetArmed() do
		if not model.Parent then continue end
		local point = pool:PointFor(model) or model:GetPivot().Position
		local distance = (point - position).Magnitude
		if distance < bestDistance then
			best = model
			bestDistance = distance
		end
	end

	return best, bestDistance
end

local function landingSpot(pool: any, model: Model): CFrame?
	local floor = pool:PointFor(model)
	if not floor then return nil end

	local pivot = model:GetPivot().Position
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

	if command == "drop" or command == "fall" then
		local target, gap = pool:Nearest(root.Position)
		if not target then
			warn(`[{label}] none found near you`)
		elseif pool:Drop(target) then
			warn(`[{label}] dropped {target:GetFullName()} {math.floor(gap)} studs away`)
		else
			warn(`[{label}] {target:GetFullName()} would not drop`)
		end
		return
	end

	local model, distance = nearestArmed(pool, root.Position)
	if not model then
		warn(`[{label}] nothing is armed right now`)
		return
	end

	local spot = landingSpot(pool, model)
	if not spot then
		warn(`[{label}] could not find hallway floor beside {model:GetFullName()}`)
		return
	end

	character:PivotTo(spot)
	warn(
		`[{label}] moved {player.Name} {math.floor(distance)} studs to {model:GetFullName()}; `
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
