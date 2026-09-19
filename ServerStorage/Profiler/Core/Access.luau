local RunService = game:GetService("RunService")
local Config = require(script.Parent.Parent.Config.Access)
local Access = {}
local cache = setmetatable({}, { __mode = "k" })

function Access.Allowed(player)
	if not Config.Enabled then return false end
	if RunService:IsStudio() then return true end
	if Config.UserIds[player.UserId] then return true end
	if game.CreatorType == Enum.CreatorType.User then return player.UserId == game.CreatorId end
	if cache[player] ~= nil then return cache[player] end
	local ok, role = pcall(player.GetRoleInGroup, player, game.CreatorId)
	cache[player] = ok and Config.GroupRoles[string.lower(role)] == true
	return cache[player]
end

function Access.ControlledAllowed()
	return RunService:IsStudio() or game.PrivateServerId ~= "" or Config.AllowControlledInPublicServers
end

return Access
