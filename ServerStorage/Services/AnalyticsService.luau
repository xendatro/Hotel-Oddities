local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local RobloxAnalytics = game:GetService("AnalyticsService")

local AnalyticsConfig = require(ServerStorage.Configs.AnalyticsConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local AnalyticsService = {}

type Session = {
	Id: string,
	Step: number,
	StartedAt: number,
}

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Value,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Value,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Value,
}

local Sessions: { [Player]: Session } = {}
local StepNames: { [number]: string } = {}

for _, step in AnalyticsConfig.Steps do
	StepNames[step.Number] = step.Name
end

local function recording(): boolean
	if not AnalyticsConfig.Enabled then return false end
	return AnalyticsConfig.LogInStudio or not RunService:IsStudio()
end

local function newSession(): Session
	return { Id = HttpService:GenerateGUID(false), Step = 0, StartedAt = os.clock() }
end

local function sessionOf(player: Player): Session
	local session = Sessions[player]
	if not session then
		session = newSession()
		Sessions[player] = session
	end
	return session
end

local function logOnboarding(player: Player, step: AnalyticsConfig.Step)
	if not AnalyticsConfig.Onboarding then return end

	task.spawn(function()
		local profile = DataSaveService:Wait(player)
		if not profile or player.Parent == nil then return end
		if (profile.Data.OnboardingStep or 0) >= step.Number then return end

		profile.Data.OnboardingStep = step.Number
		pcall(function()
			RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step.Number, step.Name)
		end)
	end)
end

local function customFields(player: Player, event: AnalyticsConfig.Event, fields: { [string]: any }?): { [string]: string }?
	local custom = {}
	local any = false
	for index, name in event.Fields do
		local key = FIELD_KEYS[index]
		if not key then break end

		local value = if fields then fields[name] else nil
		if value == nil and name == AnalyticsConfig.StepField then
			value = AnalyticsService:GetStepName(player)
		end
		if value == nil then continue end

		custom[key] = tostring(value)
		any = true
	end
	return if any then custom else nil
end

function AnalyticsService:StartRun(player: Player): string
	local session = newSession()
	Sessions[player] = session
	return session.Id
end

function AnalyticsService:LogStep(player: Player, stepId: string)
	local step = AnalyticsConfig.Steps[stepId]
	if not step then
		warn(`[analytics] no funnel step named "{stepId}"`)
		return
	end
	if not recording() or player.Parent == nil then return end

	local session = sessionOf(player)
	if step.Number <= session.Step then return end
	session.Step = step.Number

	pcall(function()
		RobloxAnalytics:LogFunnelStepEvent(
			player,
			AnalyticsConfig.Funnel,
			session.Id,
			step.Number,
			step.Name
		)
	end)

	logOnboarding(player, step)
end

function AnalyticsService:LogEvent(player: Player, eventId: string, value: number?, fields: { [string]: any }?)
	local event = AnalyticsConfig.Events[eventId]
	if not event then
		warn(`[analytics] no custom event named "{eventId}"`)
		return
	end
	if not recording() or player.Parent == nil then return end

	local custom = customFields(player, event, fields)
	local amount = if type(value) == "number" then value else 1

	pcall(function()
		RobloxAnalytics:LogCustomEvent(player, event.Name, amount, custom)
	end)
end

function AnalyticsService:LogEconomy(
	player: Player,
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	if not AnalyticsConfig.Economy.Enabled then return end
	if not recording() or player.Parent == nil then return end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return end

	local flowType = if flow == "Sink"
		then Enum.AnalyticsEconomyFlowType.Sink
		else Enum.AnalyticsEconomyFlowType.Source

	pcall(function()
		RobloxAnalytics:LogEconomyEvent(
			player,
			flowType,
			currency,
			amount,
			math.max(0, math.floor(balance)),
			transactionType,
			sku
		)
	end)
end

function AnalyticsService:GetStep(player: Player): number
	local session = Sessions[player]
	return session and session.Step or 0
end

function AnalyticsService:GetStepName(player: Player): string
	return StepNames[self:GetStep(player)] or AnalyticsConfig.NoStep
end

function AnalyticsService:GetRunTime(player: Player): number
	local session = Sessions[player]
	if not session then return 0 end
	return os.clock() - session.StartedAt
end

Players.PlayerAdded:Connect(function(player: Player)
	AnalyticsService:StartRun(player)
	AnalyticsService:LogStep(player, "Joined")

	player.CharacterAdded:Connect(function()
		AnalyticsService:LogStep(player, "Spawned")
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	Sessions[player] = nil
end)

return AnalyticsService
