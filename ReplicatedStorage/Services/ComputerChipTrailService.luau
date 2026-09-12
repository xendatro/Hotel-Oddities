local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Service = {}
if not RunService:IsClient() then return Service end

local Config = require(ReplicatedStorage.Configs.ComputerChipConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local EffectsHUD = require(ReplicatedStorage.Services.EffectsHUDService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local player = Players.LocalPlayer
local RouteRemote = CommunicationService.Get(Config.RemoteFolder, Config.RouteRemote)
local SyncRemote = CommunicationService.Get(Config.RemoteFolder, Config.SyncRemote)
local folder = Instance.new("Folder")
folder.Name = "ComputerChipTrail"
folder.Parent = workspace

local dots = {}
local current = nil
local samples = {}
local accumulator = 0
local highestId = 0

local function hide()
	for _, dot in dots do dot.Transparency = 1 end
end

local function clear()
	if current then EffectsHUD:Dismiss(current.ToolName) end
	current = nil
	table.clear(samples)
	hide()
end

local function makeSamples(points)
	local result = {}
	local distance = 0
	local nextDot = 0
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		local segment = (b - a).Magnitude
		if segment < 0.001 then continue end
		while nextDot <= distance + segment do
			local fraction = math.clamp((nextDot - distance) / segment, 0, 1)
			table.insert(result, { Position = a:Lerp(b, fraction), Distance = nextDot })
			nextDot += Config.DotSpacing
		end
		distance += segment
	end
	if #result == 0 and points[1] then table.insert(result, { Position = points[1], Distance = 0 }) end
	return result
end

local function getDot(index)
	if dots[index] then return dots[index] end
	local dot = Instance.new("Part")
	dot.Name = "TrailDot"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Config.DotSize
	dot.Material = Enum.Material.Neon
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanTouch = false
	dot.CanQuery = false
	dot.CastShadow = false
	dot.Transparency = 1
	dot.Parent = folder
	dots[index] = dot
	return dot
end

RouteRemote.OnClientEvent:Connect(function(message)
	if type(message) ~= "table" or type(message.Id) ~= "number" or message.Id < highestId then return end
	if message.Clear then
		highestId = math.max(highestId, message.Id)
		if current and current.Id == message.Id then clear() end
		return
	end
	if type(message.Points) ~= "table" or type(message.EndsAt) ~= "number" or type(message.StartedAt) ~= "number"
		or type(message.Duration) ~= "number" or typeof(message.Color) ~= "Color3" then return end
	if message.EndsAt <= workspace:GetServerTimeNow() then return end
	if current and current.Id == message.Id and current.Version >= message.Version then return end
	if current and current.Id ~= message.Id then EffectsHUD:Dismiss(current.ToolName) end
	highestId = message.Id
	current = message
	current.Progress = 0
	current.SampleIndex = 1
	samples = makeSamples(message.Points)
	EffectsHUD:ShowTimed(message.ToolName, message.Duration, message.EndsAt, message.Color)
end)

RunService.Heartbeat:Connect(function(dt)
	if not current then return end
	local now = workspace:GetServerTimeNow()
	if now >= current.EndsAt then clear(); return end
	local root = CharacterService.GetAliveRoot(player)
	if not root then clear(); return end
	local t = math.clamp((now - current.StartedAt) / math.max(current.Duration, 0.05), 0, 1)
	local transparency = t ^ Config.FadePower
	for _, dot in dots do if dot.Transparency < 1 then dot.Transparency = transparency end end
	accumulator += dt
	if accumulator < Config.VisualUpdateInterval then return end
	accumulator = 0
	local first = math.max(1, current.SampleIndex - 3)
	local last = math.min(#samples, current.SampleIndex + 16)
	local nearest, nearestDistance = nil, current.TrimDistance or Config.OffRouteDistance
	for index = first, last do
		local sample = samples[index]
		local delta = sample.Position - root.Position
		local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
		if math.abs(delta.Y) < Config.RoomHeightTolerance and distance < nearestDistance then
			nearest, nearestDistance = index, distance
		end
	end
	if nearest then
		current.SampleIndex = nearest
		current.Progress = samples[nearest].Distance
	end
	local visible = 0
	for _, sample in samples do
		if sample.Distance + Config.DotSpacing < current.Progress then continue end
		if (sample.Position - root.Position).Magnitude > Config.DotRenderDistance then continue end
		visible += 1
		if visible > Config.MaxDots then visible = Config.MaxDots; break end
		local dot = getDot(visible)
		dot.Position = sample.Position + Vector3.yAxis * Config.DotLift
		dot.Color = current.Color
		dot.Transparency = transparency
	end
	for index = visible + 1, #dots do dots[index].Transparency = 1 end
end)

player.CharacterRemoving:Connect(clear)
SyncRemote:FireServer()

return Service
