local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LanternFallService = require(ServerStorage.Services.LanternFallService)

local LanternFallCommandService = {}

--- Studs above the hallway floor the teleport stands you at. 2-5.
local STAND_HEIGHT = 3.5

local function nearestArmed(position: Vector3): (Model?, number)
	local best: Model? = nil
	local bestDistance = math.huge

	for _, model in LanternFallService:GetArmed() do
		if not model.Parent then continue end
		local point = LanternFallService:PointFor(model) or model:GetPivot().Position
		local distance = (point - position).Magnitude
		if distance < bestDistance then
			best = model
			bestDistance = distance
		end
	end

	return best, bestDistance
end

local function landingSpot(model: Model): CFrame?
	local floor = LanternFallService:PointFor(model)
	if not floor then return nil end

	local pivot = model:GetPivot().Position
	local stand = floor + Vector3.yAxis * STAND_HEIGHT
	local facing = Vector3.new(pivot.X, stand.Y, pivot.Z)
	if (facing - stand).Magnitude < 1e-3 then return CFrame.new(stand) end
	return CFrame.lookAt(stand, facing)
end

local function run(player: Player, argument: string?)
	local command = argument and argument:lower()

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		warn(`[lantern] {player.Name} has no character`)
		return
	end

	if command == "drop" or command == "fall" then
		local target, gap = LanternFallService:Nearest(root.Position)
		if not target then
			warn("[lantern] no lantern found near you")
		elseif LanternFallService:Drop(target) then
			warn(`[lantern] dropped {target:GetFullName()} {math.floor(gap)} studs away`)
		else
			warn(`[lantern] {target:GetFullName()} would not drop`)
		end
		return
	end

	local model, distance = nearestArmed(root.Position)
	if not model then
		warn("[lantern] nothing is armed right now")
		return
	end

	local spot = landingSpot(model)
	if not spot then
		warn("[lantern] could not find floor to land on near that lantern")
		return
	end

	character:PivotTo(spot)
	warn(`[lantern] moved {player.Name} {math.floor(distance)} studs to {model:GetFullName()}; walk out past {LanternFallService:ArmDistance()} studs and back to trigger it`)
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		local name, argument = message:match("^/(%a+)%s*(.*)$")
		if name and (name:lower() == "lantern" or name:lower() == "lanterns") then
			run(player, if argument ~= "" then argument else nil)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return LanternFallCommandService
