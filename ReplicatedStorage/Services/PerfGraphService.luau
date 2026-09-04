local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local PerfGraphConfig = require(ReplicatedStorage.Configs.PerfGraphConfig)
local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)

local PerfGraphService = {}

if not (FLAGS.PerfGraph and RunService:IsClient()) then
	return PerfGraphService
end

local categories = PerfGraphConfig.ChurnCategories
local categoryCount = #categories
local otherIndex = categoryCount
local counts: { number } = table.create(categoryCount, 0)
local paused = false

local function categoryOf(instance: Instance): number
	for index, category in categories do
		for _, className in category.Classes do
			if instance:IsA(className) then
				return index
			end
		end
	end
	return otherIndex
end

local function record(instance: Instance)
	local index = categoryOf(instance)
	counts[index] += 1
end

local panel = DebugPanel.new("perf graphs", PerfGraphConfig.ToggleKey, PerfGraphConfig.PanelWidth)

local fpsGraph = panel:AddGraph("FPS", {
	Height = PerfGraphConfig.GraphHeight,
	Maximum = PerfGraphConfig.FpsMaximum,
	References = PerfGraphConfig.FpsReferences,
	Format = "%.0f",
	ClipColor = PerfGraphConfig.ClipColor,
	ColorFor = function(fps: number): Color3
		if fps < PerfGraphConfig.FpsBad then
			return PerfGraphConfig.FpsColorBad
		elseif fps < PerfGraphConfig.FpsWarn then
			return PerfGraphConfig.FpsColorWarn
		end
		return PerfGraphConfig.FpsColorGood
	end,
})

local series = table.create(categoryCount)
for index, category in categories do
	series[index] = { Name = category.Name, Color = category.Color }
end

local churnGraph = panel:AddStackedGraph("instances streamed in + out per frame", {
	Height = PerfGraphConfig.GraphHeight,
	Maximum = PerfGraphConfig.ChurnMaximum,
	References = PerfGraphConfig.ChurnReferences,
	Format = "%d",
	ClipColor = PerfGraphConfig.ClipColor,
	Series = series,
})

local pauseButton: TextButton
pauseButton = panel:AddButton("pause", function()
	paused = not paused
	pauseButton.Text = if paused then "resume" else "pause"
end)

panel:AddButton("clear", function()
	fpsGraph:Clear()
	churnGraph:Clear()
end)

panel:AddLabel("newest frame is at the right edge. bars above the top of a graph clip and are capped in white.")

workspace.DescendantAdded:Connect(record)
workspace.DescendantRemoving:Connect(record)

RunService.RenderStepped:Connect(function(deltaTime: number)
	if not paused then
		fpsGraph:Push(1 / math.max(deltaTime, 1e-6))
		churnGraph:Push(counts)
	end
	for index = 1, categoryCount do
		counts[index] = 0
	end
end)

return PerfGraphService
