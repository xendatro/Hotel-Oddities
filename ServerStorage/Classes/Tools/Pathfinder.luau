local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local PerkService = require(ServerStorage.Services.PerkService)

--- @class Pathfinder
--- Owns how many markers are left. The markers themselves are the client's -- they exist only for
--- the player who placed them -- but the count is not the client's to keep.
---
--- One Pathfinder is one device carrying `Uses` charges, not a stack of twenty items. It is picked
--- up, held and shown as a single tool, and only when its last charge is spent does it leave the
--- inventory; a second one still in the stack takes over with a full charge. The gamepass version
--- spends nothing, so it never runs down and never leaves.
local Pathfinder = ServerTool.extend("Pathfinder")

function Pathfinder.new(tool: Tool)
	local self = ServerTool.new(tool, Pathfinder)

	-- Seeded here rather than at the grant site, so a Pathfinder that reached a player any way at
	-- all -- loot, an admin command, StarterGear -- still arrives with its charges on it.
	if tool:GetAttribute("uses") == nil then
		tool:SetAttribute("uses", self.Config.Uses)
	end

	self:On("Placed", function(player: Player)
		self:_spend(player)
	end)

	return self
end

function Pathfinder:_spend(player: Player)
	-- A cached lookup, not a web call. This runs inside a placement the player has already seen
	-- happen on their own screen, and yielding here would decide whether a marker was free several
	-- hundred milliseconds after it was planted.
	if PerkService:Owns(player, "Pathfinder") then return end

	local remaining = (self.Tool:GetAttribute("uses") or self.Config.Uses) - 1
	if remaining > 0 then
		self.Tool:SetAttribute("uses", remaining)
		return
	end

	-- Spent. Refilled before it is handed off, so the next one in the stack starts full instead of
	-- inheriting an empty device.
	self.Tool:SetAttribute("uses", self.Config.Uses)
	self:Consume(1)
end

return Pathfinder
