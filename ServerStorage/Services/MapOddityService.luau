local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local OddityService = require(ServerStorage.Services.OddityService)

local SCOPE = "Map"

local MapOddityService = {}

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
		return false, nil, "unknown effect; use transparency, doors, or chaos"
	end

	local span = class.Resolve(class, position)
	local oddity, reason = OddityService:Start(class, span)
	if not oddity then return false, nil, reason end
	return true, chosen, nil
end

function MapOddityService:Warn(position: Vector3, duration: number): boolean
	if not OddityService:IsEnabled(SCOPE) or duration <= 0 then return false end

	local class = OddityService:Get(SCOPE, "ChaosWarning")
	if not class then return false end

	local span = class.Resolve(class, position)
	return OddityService:Start(class, span, duration) ~= nil
end

function MapOddityService:Clear(token: number?): boolean
	if token then return OddityService:Stop(token) end
	return OddityService:StopAll(SCOPE) > 0
end

function MapOddityService:GetActive(): { [number]: any }
	return OddityService:GetActive(SCOPE)
end

return MapOddityService
