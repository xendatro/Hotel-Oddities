local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.ViewmodelDebugConfig)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local ViewmodelService = require(ReplicatedStorage.Services.ViewmodelService)
local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local ViewmodelDebugService = {}

if not (FLAGS.ViewmodelDebug and RunService:IsClient()) then
	return ViewmodelDebugService
end

local TOOL_NAME = "Walkie Talkie"
local override = ViewmodelConfig.Overrides[TOOL_NAME]
local panel = DebugPanel.new("walkie talkie viewmodel", Config.ToggleKey)
local values = {
	Scale = override.Scale or ViewmodelConfig.Scale,
	AnchorX = override.Anchor.X,
	AnchorY = override.Anchor.Y,
	AnchorZ = override.Anchor.Z,
	ArmX = (override.ArmAnchor or override.Anchor).X,
	ArmY = (override.ArmAnchor or override.Anchor).Y,
	ArmZ = (override.ArmAnchor or override.Anchor).Z,
	RotateX = 0,
	RotateY = 0,
	RotateZ = 15,
}
local resetters: { () -> () } = {}
local output = panel:AddTextBox("")

local function updateOutput()
	output.Text = string.format(
		'["Walkie Talkie"] = { AnchorAt = "Handle", Scale = %.2f, Anchor = Vector3.new(%.2f, %.2f, %.2f), ArmAnchor = Vector3.new(%.2f, %.2f, %.2f), Rotate = CFrame.Angles(math.rad(%.0f), math.rad(%.0f), math.rad(%.0f)), },',
		values.Scale,
		values.AnchorX,
		values.AnchorY,
		values.AnchorZ,
		values.ArmX,
		values.ArmY,
		values.ArmZ,
		values.RotateX,
		values.RotateY,
		values.RotateZ
	)
end

local function apply(refresh: boolean)
	override.Scale = values.Scale
	override.Anchor = Vector3.new(values.AnchorX, values.AnchorY, values.AnchorZ)
	override.ArmAnchor = Vector3.new(values.ArmX, values.ArmY, values.ArmZ)
	override.Rotate = CFrame.Angles(
		math.rad(values.RotateX),
		math.rad(values.RotateY),
		math.rad(values.RotateZ)
	)
	if refresh then
		ViewmodelService:Refresh()
	end
	updateOutput()
end

local function addSlider(
	key: string,
	label: string,
	minimum: number,
	maximum: number,
	step: number,
	refresh: boolean
)
	local display = panel:AddSlider(label, minimum, maximum, values[key], step, function(value)
		values[key] = value
		apply(refresh)
	end)
	table.insert(resetters, function()
		display(values[key])
	end)
end

addSlider("Scale", "Scale", 0.1, 1.5, Config.Step, true)
addSlider("AnchorX", "Anchor X", -2, 2, Config.Step, false)
addSlider("AnchorY", "Anchor Y", -2, 1, Config.Step, false)
addSlider("AnchorZ", "Anchor Z", -4, -0.2, Config.Step, false)
addSlider("ArmX", "Hand X", -2, 2, Config.Step, false)
addSlider("ArmY", "Hand Y", -2, 1, Config.Step, false)
addSlider("ArmZ", "Hand Z", -4, -0.2, Config.Step, false)
addSlider("RotateX", "Rotate X", -180, 180, Config.AngleStep, false)
addSlider("RotateY", "Rotate Y", -180, 180, Config.AngleStep, false)
addSlider("RotateZ", "Rotate Z", -180, 180, Config.AngleStep, false)

panel:AddButton("reset to config defaults", function()
	values.Scale = override.Scale or ViewmodelConfig.Scale
	values.AnchorX = override.Anchor.X
	values.AnchorY = override.Anchor.Y
	values.AnchorZ = override.Anchor.Z
	values.ArmX = (override.ArmAnchor or override.Anchor).X
	values.ArmY = (override.ArmAnchor or override.Anchor).Y
	values.ArmZ = (override.ArmAnchor or override.Anchor).Z
	values.RotateX = 0
	values.RotateY = 0
	values.RotateZ = 15
	for _, reset in resetters do reset() end
	apply(true)
end)

panel:AddLabel("Changes are local to this session. Copy the generated entry into ViewmodelConfig when finished.")
updateOutput()

return ViewmodelDebugService
