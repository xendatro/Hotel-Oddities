local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.LanternSwayConfig)
local LightService = require(ServerStorage.Services.LightService)

local LanternSwingCommandService = {}

local SwayNames: { [string]: true } = {}
for _, name in Config.SwayModelNames do
	SwayNames[name] = true
end

local function nearestLantern(position: Vector3): Model?
	local best: Model? = nil
	local bestDistance = math.huge
	for _, model in LightService:GetModels() do
		if not SwayNames[model.Name] then continue end
		local distance = (model:GetPivot().Position - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = model, distance
		end
	end
	return best
end

local function run(player: Player, argument: string?)
	local duration = tonumber(argument) or 15

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		warn(`[lantern] {player.Name} has no character to target`)
		return
	end

	local lantern = nearestLantern(root.Position)
	if not lantern then
		warn("[lantern] no swayable lantern found in the workspace")
		return
	end

	LightService:WarnRed(lantern, duration)
	warn(`[lantern] swinging {lantern:GetFullName()} red for {duration}s (ChaosRed={tostring(lantern:GetAttribute("ChaosRed"))})`)
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		local name, argument = message:match("^/(%a+)%s*(.*)$")
		if not name then return end
		name = name:lower()
		if name ~= "lantern" and name ~= "lanterns" then return end

		local rest = argument and argument:lower():match("^swing%s*(.*)$")
		if rest then
			run(player, if rest ~= "" then rest else nil)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return LanternSwingCommandService
