local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryService = require(ServerStorage.Services.InventoryService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local Tools = ReplicatedStorage.Tools

local MAX_AMOUNT = 100

local ToolCommandService = {}

local function findTool(name: string): Tool?
	for _, child in Tools:GetChildren() do
		if child:IsA("Tool") and child.Name:lower() == name:lower() then
			return child
		end
	end
	return nil
end

local function parseAmount(argument: string): (string, number)
	local withoutAmount, amountText = argument:match("^(.-)%s+(%d+)$")
	if not amountText then return argument, 1 end

	local amount = math.clamp(tonumber(amountText) or 1, 1, MAX_AMOUNT)
	return withoutAmount, amount
end

function ToolCommandService:Execute(sender: Player, argument: string?): boolean
	argument = argument and argument:match("^%s*(.-)%s*$") or ""
	if argument == "" then
		warn("[give] usage: /give <tool> [amount] or /give <player> <tool> [amount]")
		return false
	end

	local itemText, amount = parseAmount(argument)
	local target = sender
	local tool = findTool(itemText)

	if not tool then
		local targetText, remaining = itemText:match("^(%S+)%s+(.+)$")
		local requestedTarget = targetText and ChatCommandService.FindPlayer(targetText)
		if requestedTarget then
			target = requestedTarget
			tool = findTool(remaining)
		end
	end

	if not tool then
		warn(`[give] no tool matches "{itemText}"`)
		return false
	end

	if not InventoryService:Add(target, tool.Name, amount) then
		warn(`[give] could not give {target.Name} {amount}x {tool.Name}`)
		return false
	end

	warn(`[give] {sender.Name} gave {target.Name} {amount}x {tool.Name}`)
	return true
end

ChatCommandService.Register("give", {
	AdminOnly = true,
	Handler = function(player: Player, argument: string?)
		ToolCommandService:Execute(player, argument)
	end,
})

return ToolCommandService
