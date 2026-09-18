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
}

local Sessions: { [Player]: Session } = {}

local function recording(): boolean
	if not AnalyticsConfig.Enabled then return false end
	return AnalyticsConfig.LogInStudio or not RunService:IsStudio()
end

local function sessionOf(player: Player): Session
	local session = Sessions[player]
	if not session then
		session = { Id = HttpService:GenerateGUID(false), Step = 0 }
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

function AnalyticsService:StartRun(player: Player): string
	local session = { Id = HttpService:GenerateGUID(false), Step = 0 }
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

function AnalyticsService:GetStep(player: Player): number
	local session = Sessions[player]
	return session and session.Step or 0
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
