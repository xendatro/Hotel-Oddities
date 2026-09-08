local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local POIConfig = require(ReplicatedStorage.Configs.POIConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local POIUIService = {}

if not RunService:IsClient() then
	return POIUIService
end

local Popup = POIConfig.Popup
local Remotes = POIConfig.Remotes

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild(POIConfig.Gui.ScreenGui, 30) :: ScreenGui?
local card = gui and gui:FindFirstChild(POIConfig.Gui.Card)

if not (gui and card and card:IsA("Frame")) then
	warn("[POIUIService] POIGui or its Card is missing")
	return POIUIService
end

local frame = card :: Frame
local eyebrow = frame:FindFirstChild("Eyebrow") :: TextLabel
local title = frame:FindFirstChild("Title") :: TextLabel
local rule = frame:FindFirstChild("Rule") :: Frame
local counter = frame:FindFirstChild("Counter") :: TextLabel

if not (eyebrow and title and rule and counter) then
	warn("[POIUIService] POIGui is missing Eyebrow, Title, Rule or Counter")
	return POIUIService
end

local DiscoveredRemote = CommunicationService.Get(Remotes.Folder, Remotes.Discovered) :: RemoteEvent
local SyncRemote = CommunicationService.Get(Remotes.Folder, Remotes.Sync) :: RemoteEvent

type Line = { Object: GuiObject, Transparency: number, Order: number, Base: UDim2 }

local basePosition = frame.Position
local lines: { Line } = {
	{ Object = eyebrow, Transparency = Popup.EyebrowTransparency, Order = 0, Base = eyebrow.Position },
	{ Object = title, Transparency = Popup.TitleTransparency, Order = 1, Base = title.Position },
	{ Object = rule, Transparency = Popup.RuleTransparency, Order = 2, Base = rule.Position },
	{ Object = counter, Transparency = Popup.CounterTransparency, Order = 3, Base = counter.Position },
}
local ruleHeight = rule.Size.Y.Offset

local tweens: { Tween } = {}
local queue: { { Name: string, Count: number, Total: number } } = {}
local shownCount = 0
local running = false

local function play(instance: Instance, info: TweenInfo, goal: { [string]: any }, delay: number?): Tween
	local tween = TweenService:Create(instance, info, goal)
	table.insert(tweens, tween)
	if delay and delay > 0 then
		task.delay(delay, function()
			if table.find(tweens, tween) then tween:Play() end
		end)
	else
		tween:Play()
	end
	return tween
end

local function queueProxy(proxy: Tween, delay: number)
	table.insert(tweens, proxy)
	task.delay(delay, function()
		if table.find(tweens, proxy) then proxy:Play() end
	end)
end

local function fade(object: GuiObject, transparency: number, info: TweenInfo, delay: number?)
	if object:IsA("TextLabel") then
		play(object, info, { TextTransparency = transparency }, delay)
	else
		play(object, info, { BackgroundTransparency = transparency }, delay)
	end
end

local function counterText(count: number, total: number): string
	if total > 0 then
		return string.format(Popup.CounterText, count, total)
	end
	return string.format(Popup.CounterTextUnknownTotal, count)
end

local function reset()
	TweenProxyService.CancelAll(tweens)

	frame.Position = basePosition
	rule.Size = UDim2.fromOffset(0, ruleHeight)
	title.MaxVisibleGraphemes = 0

	for _, line in lines do
		line.Object.Position = line.Base + UDim2.fromOffset(0, Popup.Rise)
		if line.Object:IsA("TextLabel") then
			line.Object.TextTransparency = 1
		else
			line.Object.BackgroundTransparency = 1
		end
	end
end

local function animateIn(entry: { Name: string, Count: number, Total: number })
	local stagger = Popup.Stagger
	local rise = TweenInfo.new(Popup.InTime * 1.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local appear = TweenInfo.new(Popup.InTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	eyebrow.Text = Popup.EyebrowText
	title.Text = entry.Name
	title.MaxVisibleGraphemes = 0
	counter.Text = counterText(shownCount, entry.Total)
	gui.Enabled = true

	for _, line in lines do
		local delay = stagger * line.Order
		play(line.Object, rise, { Position = line.Base }, delay)
		fade(line.Object, line.Transparency, appear, delay)
	end

	play(
		rule,
		TweenInfo.new(Popup.RuleTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(Popup.RuleWidth, ruleHeight) },
		stagger * 2
	)

	local graphemes = utf8.len(entry.Name) or #entry.Name
	queueProxy(
		TweenProxyService.Proxy(
			"NumberValue",
			0,
			graphemes,
			TweenInfo.new(Popup.TypeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			function(value: number)
				title.MaxVisibleGraphemes = math.floor(value)
			end
		),
		stagger
	)

	if entry.Count > shownCount then
		queueProxy(
			TweenProxyService.Proxy(
				"NumberValue",
				shownCount,
				entry.Count,
				TweenInfo.new(Popup.CountUpTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				function(value: number)
					counter.Text = counterText(math.floor(value + 0.5), entry.Total)
				end
			),
			stagger * 3
		)
	end

	shownCount = entry.Count
end

local function animateOut()
	local info = TweenInfo.new(Popup.OutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	play(frame, info, { Position = basePosition - UDim2.fromOffset(0, Popup.ExitDrift) })
	play(rule, info, { Size = UDim2.fromOffset(0, ruleHeight) })
	for _, line in lines do
		fade(line.Object, 1, info)
	end
end

local function run()
	if running then return end
	running = true

	task.spawn(function()
		while true do
			local entry = table.remove(queue, 1)
			if not entry then break end

			reset()
			animateIn(entry)
			task.wait(Popup.Hold)
			animateOut()
			task.wait(Popup.OutTime)
			gui.Enabled = false
			task.wait(Popup.QueueGap)
		end

		running = false
	end)
end

function POIUIService:Show(name: string, count: number?, total: number?)
	if type(name) ~= "string" or name == "" then return end

	table.insert(queue, {
		Name = name,
		Count = if type(count) == "number" then count else shownCount + 1,
		Total = if type(total) == "number" then total else 0,
	})
	run()
end

DiscoveredRemote.OnClientEvent:Connect(function(name: any, count: any, total: any)
	POIUIService:Show(name, count, total)
end)

SyncRemote.OnClientEvent:Connect(function(_discovered: any, count: any)
	if type(count) == "number" then
		shownCount = count
	end
end)

reset()
gui.Enabled = false
SyncRemote:FireServer()

return POIUIService
