local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local OddityService = {}

local EDIT_MODE = RunService:IsStudio() and not RunService:IsRunning()

local registry: { [string]: { [string]: any } } = {}
local scopeEnabled: { [string]: boolean } = {}
local active: { [number]: any } = {}

local function settingsFor(class: any): { [string]: any }
	local module = ReplicatedStorage.Configs:FindFirstChild(class.ConfigName)
	local config = if module then require(module) else {}

	local merged = {}
	for key, value in config do
		merged[key] = value
	end

	local effects = config.Effects
	local overrides = effects and effects[class.Kind]
	if type(overrides) == "table" then
		for key, value in overrides do
			merged[key] = value
		end
	end

	return merged
end

function OddityService:Register(class: any)
	if type(class) ~= "table" or type(class.Kind) ~= "string" or type(class.Scope) ~= "string" then
		return
	end

	local scope = registry[class.Scope]
	if not scope then
		scope = {}
		registry[class.Scope] = scope
	end
	scope[class.Kind] = class
	class.Settings = settingsFor(class)
	scopeEnabled[class.Scope] = class.Settings.Enabled ~= false
end

function OddityService:Get(scope: string, kind: string): any?
	local classes = registry[scope]
	return classes and classes[kind]
end

function OddityService:Classes(scope: string): { [string]: any }
	return registry[scope] or {}
end

function OddityService:Kinds(scope: string): { string }
	local kinds = {}
	for kind in self:Classes(scope) do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	return kinds
end

function OddityService:IsEnabled(scope: string): boolean
	return not EDIT_MODE and scopeEnabled[scope] == true
end

function OddityService:IsAmbient(class: any): boolean
	return class.Ambient ~= false and class.Settings.Ambient ~= false
end

function OddityService:Start(class: any, context: any, duration: number?): (any?, string?)
	if EDIT_MODE then return nil, "oddities are disabled in Studio edit mode" end
	if class.Settings.Enabled == false then return nil, "that oddity is disabled" end

	local oddity = class.new(class.Settings)
	local ok, reason = oddity:CanStart(context)
	if not ok then return nil, reason end

	oddity:OnStopped(function(finished: any)
		active[finished.Token] = nil
	end)

	active[oddity.Token] = oddity
	if not oddity:Start(context, duration) then
		active[oddity.Token] = nil
		return nil, "could not start that oddity"
	end
	return oddity, nil
end

function OddityService:Stop(token: number): boolean
	local oddity = active[token]
	if not oddity then return false end
	return oddity:Stop()
end

function OddityService:StopAll(scope: string?): number
	local stopping = {}
	for _, oddity in active do
		if scope == nil or oddity.Scope == scope then
			table.insert(stopping, oddity)
		end
	end
	for _, oddity in stopping do
		oddity:Stop()
	end
	return #stopping
end

function OddityService:GetActive(scope: string?): { [number]: any }
	if scope == nil then return active end

	local matching = {}
	for token, oddity in active do
		if oddity.Scope == scope then matching[token] = oddity end
	end
	return matching
end

if not EDIT_MODE then
	for _, module in ServerStorage.Classes.Oddities:GetChildren() do
		if module:IsA("ModuleScript") then
			OddityService:Register(require(module))
		end
	end

	for _, classes in registry do
		for _, class in classes do
			if not OddityService:IsAmbient(class) then continue end
			if class.Settings.Enabled == false then continue end
			if type(class.Pick) ~= "function" then continue end

			task.spawn(function()
				local settings = class.Settings
				task.wait(math.max(settings.InitialDelay or 45, 0))
				while true do
					if math.random() <= (settings.TriggerChance or 0.15) then
						local context = class.Pick(class)
						if context then
							OddityService:Start(class, context)
						end
					end
					task.wait(math.max(settings.RollInterval or 45, 1))
				end
			end)
		end
	end
end

return OddityService
