-- Lets an MCP Client snippet call a Playtest module inside the real client VM.
-- Snippets cannot require anything (see PLAYTESTING.md), so they write a JSON
-- call onto the LocalPlayer and this script runs it with the game's own module
-- cache. Studio only, and inert until a snippet sets the attribute.
--
--   LocalPlayer:SetAttribute("PlaytestCall", HttpService:JSONEncode({
--       id = "a1", module = "Trailer.Director", fn = "Play", args = { "Arrival" },
--   }))
--
-- The result lands on LocalPlayer as PlaytestResult_<id>: JSON with ok and
-- value or error. Module paths are relative to ReplicatedStorage.Playtest.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer
local CALL = "PlaytestCall"

local function resolve(path: string): Instance?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Playtest")
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function encode(value: any): any
	local kind = typeof(value)
	if kind == "Vector3" or kind == "CFrame" or kind == "Color3" or kind == "Vector2" or kind == "Instance" or kind == "EnumItem" then
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

local function run(raw: string)
	local ok, call = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(call) ~= "table" then return end
	local id = tostring(call.id or "last"):gsub("[^%w_]", "")

	local result
	local module = resolve(tostring(call.module or ""))
	if not module or not module:IsA("ModuleScript") then
		result = { ok = false, error = `no Playtest module {call.module}` }
	else
		local success, value = pcall(function()
			local loaded = require(module) :: any
			local fn = if call.fn then loaded[call.fn] else nil
			if type(fn) ~= "function" then error(`{call.module} has no function {call.fn}`) end
			return fn(table.unpack(call.args or {}))
		end)
		result = if success then { ok = true, value = encode(value) } else { ok = false, error = tostring(value) }
	end

	local encoded = HttpService:JSONEncode(result)
	player:SetAttribute(`PlaytestResult_{id}`, encoded)
	print(`[PlaytestBridge] {id} {encoded:sub(1, 300)}`)
end

player:GetAttributeChangedSignal(CALL):Connect(function()
	local raw = player:GetAttribute(CALL)
	if type(raw) ~= "string" or raw == "" then return end
	player:SetAttribute(CALL, nil)
	task.spawn(run, raw)
end)
