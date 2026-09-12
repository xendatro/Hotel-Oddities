local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local OddityService = require(ServerStorage.Services.OddityService)

local SCOPE = "Map"
local RESYNC_COOLDOWN = 1

local MapOddityService = {}
local RequestMapDoors = CommunicationService.Ensure("Oddities", "RequestMapDoors")
local LastResync: { [Player]: number } = {}

local function disabledReason(): string
	if RunService:IsStudio() and not RunService:IsRunning() then
		return "map oddities are disabled in Studio edit mode"
	end
	return "map oddities are disabled"
end

function MapOddityService:Trigger(position: Vector3, kind: string?): (boolean, string?, string?)
	if not OddityService:IsEnabled(SCOPE) then return false, nil, disabledReason() end

	local chosen = kind or "Transparency"
	local class = OddityService:Get(SCOPE, chosen)
	if not class then
		return false, nil, "unknown effect; use transparency, blackout, doors, chaos, blocker, void, or crush"
	end

	local context = class.Resolve(class, position)
	local oddity, reason = OddityService:Start(class, context)
	if not oddity then return false, nil, reason end
	return true, chosen, nil
end

function MapOddityService:Warn(
	span: any,
	duration: number,
	arrivalAtStart: number,
	arrivalAtFinish: number,
	warningTime: number,
	run: number
): number?
	if not span or duration <= 0 then return nil end
	if not OddityService:IsEnabled(SCOPE) then return nil end

	local class = OddityService:Get(SCOPE, "ChaosWarning")
	if not class then return nil end

	local oddity = OddityService:Start(class, span, duration, {
		ArrivalAtStart = arrivalAtStart,
		ArrivalAtFinish = arrivalAtFinish,
		WarningTime = warningTime,
		WarningRun = run,
	})
	return if oddity then oddity.Token else nil
end

function MapOddityService:Clear(token: number?): boolean
	if token then return OddityService:Stop(token) end
	return OddityService:StopAll(SCOPE) > 0
end

function MapOddityService:GetActive(): { [number]: any }
	return OddityService:GetActive(SCOPE)
end

function MapOddityService:Resync(player: Player)
	for _, oddity in OddityService:GetActive(SCOPE) do
		if type(oddity.ResyncTo) == "function" then
			oddity:ResyncTo(player)
		end
	end
end

RequestMapDoors.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if now - (LastResync[player] or -math.huge) < RESYNC_COOLDOWN then return end
	LastResync[player] = now
	MapOddityService:Resync(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastResync[player] = nil
end)

return MapOddityService
