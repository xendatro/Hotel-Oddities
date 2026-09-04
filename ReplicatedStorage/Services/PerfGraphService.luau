local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local PerfGraphConfig = require(ReplicatedStorage.Configs.PerfGraphConfig)
local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)

local PerfGraphService = {}

if not (FLAGS.PerfGraph and RunService:IsClient()) then
	return PerfGraphService
end

local addedThisFrame = 0
local removedThisFrame = 0
local paused = false

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

local churnGraph = panel:AddGraph("instances streamed in + out per frame", {
	Height = PerfGraphConfig.GraphHeight,
	Maximum = PerfGraphConfig.ChurnMaximum,
	References = PerfGraphConfig.ChurnReferences,
	Format = "%d",
	Color = PerfGraphConfig.ChurnColor,
	ClipColor = PerfGraphConfig.ClipColor,
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

panel:AddLabel("newest frame is at the right edge. bars above the top of a graph clip and turn pink.")

workspace.DescendantAdded:Connect(function()
	addedThisFrame += 1
end)

workspace.DescendantRemoving:Connect(function()
	removedThisFrame += 1
end)

RunService.RenderStepped:Connect(function(deltaTime: number)
	local added, removed = addedThisFrame, removedThisFrame
	addedThisFrame, removedThisFrame = 0, 0
	if paused then return end
	fpsGraph:Push(1 / math.max(deltaTime, 1e-6))
	churnGraph:Push(added + removed)
end)

return PerfGraphService
