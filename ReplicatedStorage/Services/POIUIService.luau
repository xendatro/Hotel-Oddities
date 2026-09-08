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

local basePosition = frame.Position
local labels: { { Label: TextLabel, Transparency: number, Order: number } } = {
	{ Label = eyebrow, Transparency = Popup.EyebrowTransparency, Order = 0 },
	{ Label = title, Transparency = Popup.TitleTransparency, Order = 1 },
	{ Label = counter, Transparency = Popup.CounterTransparency, Order = 3 },
}

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

local function counterText(count: number, total: number): string
	if total > 0 then
		return string.format(Popup.CounterText, count, total)
	end
	return string.format(Popup.CounterTextUnknownTotal, count)
end

local function reset()
	TweenProxyService.CancelAll(tweens)

	frame.Position = basePosition + UDim2.fromOffset(0, Popup.SlideOffset)
	rule.Size = UDim2.fromOffset(0, rule.Size.Y.Offset)
	rule.BackgroundTransparency = 1

	for _, entry in labels do
		entry.Label.TextTransparency = 1
	end
end

local function animateIn(entry: { Name: string, Count: number, Total: number })
	local stagger = Popup.Stagger
	local rise = TweenInfo.new(Popup.InTime * 1.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(Popup.InTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	eyebrow.Text = Popup.EyebrowText
	title.Text = entry.Name
	counter.Text = counterText(shownCount, entry.Total)
	gui.Enabled = true

	play(frame, rise, { Position = basePosition })

	for _, label in labels do
		play(label.Label, fade, { TextTransparency = label.Transparency }, stagger * label.Order)
	end

	play(
		rule,
		TweenInfo.new(Popup.RuleTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromOffset(Popup.RuleWidth, rule.Size.Y.Offset),
			BackgroundTransparency = Popup.RuleTransparency,
		},
		stagger * 2
	)

	if entry.Count > shownCount then
		local countUp = TweenProxyService.Proxy(
			"NumberValue",
			shownCount,
			entry.Count,
			TweenInfo.new(Popup.CountUpTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			function(value: number)
				counter.Text = counterText(math.floor(value + 0.5), entry.Total)
			end
		)
		table.insert(tweens, countUp)
		task.delay(stagger * 3, function()
			if table.find(tweens, countUp) then countUp:Play() end
		end)
	end

	shownCount = entry.Count
end

local function animateOut()
	local info = TweenInfo.new(Popup.OutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	play(frame, info, { Position = basePosition - UDim2.fromOffset(0, Popup.ExitDrift) })
	play(rule, info, { BackgroundTransparency = 1 })
	for _, label in labels do
		play(label.Label, info, { TextTransparency = 1 })
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
