local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local InventoryService = require(ServerStorage.Services.InventoryService)

local Tools = ReplicatedStorage.Tools

local ALLOWED_USER_IDS = {
	[265199502] = true,
	[1936118388] = true,
}

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

local function findPlayer(name: string): Player?
	local lowered = name:lower()
	local userId = tonumber(name)
	for _, player in Players:GetPlayers() do
		if player.Name:lower() == lowered
			or player.DisplayName:lower() == lowered
			or (userId and player.UserId == userId)
		then
			return player
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
	if not RunService:IsStudio() and not ALLOWED_USER_IDS[sender.UserId] then
		warn(`[give] {sender.Name} ({sender.UserId}) is not allowed to use /give`)
		return false
	end

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
		local requestedTarget = targetText and findPlayer(targetText)
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

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		local command, argument = message:match("^/(%S+)%s*(.*)$")
		if command and command:lower() == "give" then
			ToolCommandService:Execute(player, if argument ~= "" then argument else nil)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return ToolCommandService
