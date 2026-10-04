-- Server half of Bridge.client: lets an MCP Server snippet call a Playtest
-- module inside the real server VM, so EnemyService spawn blocks and other
-- module state actually reach the running game. Studio only, inert until a
-- snippet sets the attribute.
--
--   game.ServerStorage:SetAttribute("PlaytestCall", HttpService:JSONEncode({
--       id = "q1", module = "Quiet", fn = "on", args = {},
--   }))
--
-- Module paths resolve under ServerStorage.Playtest first, then
-- ReplicatedStorage.Playtest. Arguments named "@player" become the first
-- player. The result lands on ServerStorage as PlaytestResult_<id>.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

if not RunService:IsStudio() then return end

local CALL = "PlaytestCall"

local function resolveIn(root: Instance, path: string): Instance?
	local node: Instance? = root:FindFirstChild("Playtest")
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function encode(value: any): any
	local kind = typeof(value)
	if kind == "Vector3" or kind == "CFrame" or kind == "Color3" or kind == "Instance" or kind == "EnumItem" then
		return tostring(value)
	end
	if kind == "table" then
		local copy = {}
		for key, item in value do
			copy[tostring(key)] = encode(item)
		end
		return copy
	end
	return value
end

local function decodeArgs(args: { any }?): { any }
	local out = {}
	for index, arg in args or {} do
		if arg == "@player" then
			out[index] = Players:GetPlayers()[1]
		else
			out[index] = arg
		end
	end
	return out
end

local function run(raw: string)
	local ok, call = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(call) ~= "table" then return end
	local id = tostring(call.id or "last"):gsub("[^%w_]", "")
	local path = tostring(call.module or "")

	local result
	local module = resolveIn(ServerStorage, path) or resolveIn(ReplicatedStorage, path)
	if not module or not module:IsA("ModuleScript") then
		result = { ok = false, error = `no Playtest module {path}` }
	else
		local success, value = pcall(function()
			local loaded = require(module) :: any
			local fn = if call.fn then loaded[call.fn] else nil
			if type(fn) ~= "function" then error(`{path} has no function {call.fn}`) end
			return fn(table.unpack(decodeArgs(call.args)))
		end)
		result = if success then { ok = true, value = encode(value) } else { ok = false, error = tostring(value) }
	end

	local encoded = HttpService:JSONEncode(result)
	ServerStorage:SetAttribute(`PlaytestResult_{id}`, encoded)
	print(`[PlaytestServerBridge] {id} {encoded:sub(1, 300)}`)
end

ServerStorage:GetAttributeChangedSignal(CALL):Connect(function()
	local raw = ServerStorage:GetAttribute(CALL)
	if type(raw) ~= "string" or raw == "" then return end
	ServerStorage:SetAttribute(CALL, nil)
	task.spawn(run, raw)
end)
