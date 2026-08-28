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
local LIVE_STATE = "Live"
local BASE_STATE = "Base"

local override = ViewmodelConfig.Overrides[TOOL_NAME]
override.Poses = override.Poses or {}

local states = { LIVE_STATE, BASE_STATE }
for _, name in Config.PoseOrder do
	if override.Poses[name] then table.insert(states, name) end
end

local stateIndex = 1
local panel = DebugPanel.new("walkie talkie viewmodel", Config.ToggleKey)
local resetters: { () -> () } = {}
local stateButton: TextButton? = nil
local output = panel:AddTextBox("")

local function currentState(): string
	return states[stateIndex]
end

local function currentPose(): any?
	local state = currentState()
	if state == LIVE_STATE or state == BASE_STATE then return nil end
	return override.Poses[state]
end

local function angles(cframe: CFrame?): (number, number, number)
	if not cframe then return 0, 0, 0 end
	local x, y, z = cframe:ToEulerAnglesYXZ()
	return math.deg(x), math.deg(y), math.deg(z)
end

local values = {
	Scale = 0,
	AnchorX = 0,
	AnchorY = 0,
	AnchorZ = 0,
	ArmX = 0,
	ArmY = 0,
	ArmZ = 0,
	RotateX = 0,
	RotateY = 0,
	RotateZ = 0,
	Coverage = 0,
}

local function readState()
	local pose = currentPose()
	values.Scale = override.Scale or ViewmodelConfig.Scale

	if not pose then
		local anchor = override.Anchor
		local arm = override.ArmAnchor or anchor
		values.AnchorX, values.AnchorY, values.AnchorZ = anchor.X, anchor.Y, anchor.Z
		values.ArmX, values.ArmY, values.ArmZ = arm.X, arm.Y, arm.Z
		values.RotateX, values.RotateY, values.RotateZ = angles(override.Rotate)
		values.Coverage = 0.5
		return
	end

	local anchor = pose.AnchorOffset or Vector3.zero
	local arm = pose.ArmAnchorOffset or Vector3.zero
	values.AnchorX, values.AnchorY, values.AnchorZ = anchor.X, anchor.Y, anchor.Z
	values.ArmX, values.ArmY, values.ArmZ = arm.X, arm.Y, arm.Z
	values.RotateX, values.RotateY, values.RotateZ = angles(pose.RotateOffset)
	values.Coverage = if pose.Framing then pose.Framing.Coverage or 0.5 else 0.5
end

local function formatVector(x: number, y: number, z: number): string
	return string.format("Vector3.new(%.2f, %.2f, %.2f)", x, y, z)
end

local function formatAngles(cframe: CFrame?): string
	local x, y, z = angles(cframe)
	return string.format("CFrame.Angles(math.rad(%.0f), math.rad(%.0f), math.rad(%.0f))", x, y, z)
end

local function formatPose(name: string, pose: any): string
	local lines = { `\t\t\t\t{name} = \{` }
	if pose.AnchorOffset then
		table.insert(lines, `\t\t\t\t\tAnchorOffset = {formatVector(pose.AnchorOffset.X, pose.AnchorOffset.Y, pose.AnchorOffset.Z)},`)
	end
	if pose.ArmAnchorOffset then
		table.insert(lines, `\t\t\t\t\tArmAnchorOffset = {formatVector(pose.ArmAnchorOffset.X, pose.ArmAnchorOffset.Y, pose.ArmAnchorOffset.Z)},`)
	end
	if pose.RotateOffset then
		table.insert(lines, `\t\t\t\t\tRotateOffset = {formatAngles(pose.RotateOffset)},`)
	end
	if pose.Framing then
		table.insert(lines, "\t\t\t\t\tFraming = {")
		table.insert(lines, `\t\t\t\t\t\tPart = "{pose.Framing.Part}",`)
		if pose.Framing.Element then
			table.insert(lines, `\t\t\t\t\t\tElement = "{pose.Framing.Element}",`)
		end
		table.insert(lines, string.format("\t\t\t\t\t\tCoverage = %.2f,", pose.Framing.Coverage or 0.5))
		table.insert(lines, "\t\t\t\t\t},")
	end
	table.insert(lines, "\t\t\t\t},")
	return table.concat(lines, "\n")
end

local function updateOutput()
	local lines = {
		`\t\t["{TOOL_NAME}"] = \{`,
		`\t\t\tAnchorAt = "{override.AnchorAt}",`,
		string.format("\t\t\tScale = %.2f,", override.Scale or ViewmodelConfig.Scale),
		`\t\t\tAnchor = {formatVector(override.Anchor.X, override.Anchor.Y, override.Anchor.Z)},`,
	}
	local arm = override.ArmAnchor
	if arm then
		table.insert(lines, `\t\t\tArmAnchor = {formatVector(arm.X, arm.Y, arm.Z)},`)
	end
	table.insert(lines, `\t\t\tRotate = {formatAngles(override.Rotate)},`)
	table.insert(lines, string.format("\t\t\tPoseSpeed = %.0f,", override.PoseSpeed or 9))
	table.insert(lines, "\t\t\tPoses = {")
	for _, name in states do
		if name == LIVE_STATE or name == BASE_STATE then continue end
		table.insert(lines, formatPose(name, override.Poses[name]))
	end
	table.insert(lines, "\t\t\t},")
	table.insert(lines, "\t\t},")
	output.Text = table.concat(lines, "\n")
end

local function apply(refresh: boolean)
	local pose = currentPose()
	override.Scale = values.Scale

	if not pose then
		override.Anchor = Vector3.new(values.AnchorX, values.AnchorY, values.AnchorZ)
		override.ArmAnchor = Vector3.new(values.ArmX, values.ArmY, values.ArmZ)
		override.Rotate = CFrame.Angles(
			math.rad(values.RotateX),
			math.rad(values.RotateY),
			math.rad(values.RotateZ)
		)
	else
		pose.ArmAnchorOffset = Vector3.new(values.ArmX, values.ArmY, values.ArmZ)
		if pose.Framing then
			pose.Framing.Coverage = values.Coverage
		else
			pose.AnchorOffset = Vector3.new(values.AnchorX, values.AnchorY, values.AnchorZ)
			pose.RotateOffset = CFrame.Angles(
				math.rad(values.RotateX),
				math.rad(values.RotateY),
				math.rad(values.RotateZ)
			)
		end
	end

	if refresh then ViewmodelService:Refresh() end
	updateOutput()
end

local function setState(index: number)
	stateIndex = (index - 1) % #states + 1
	local state = currentState()
	if state == LIVE_STATE then
		ViewmodelService:SetPoseOverride(false)
	else
		ViewmodelService:SetPoseOverride(true, if state == BASE_STATE then nil else state)
	end
	readState()
	for _, reset in resetters do reset() end
	if stateButton then stateButton.Text = `state: {state} (click to cycle)` end
	updateOutput()
end

stateButton = panel:AddButton("", function()
	setState(stateIndex + 1)
end)

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
addSlider("Coverage", "Screen coverage (framed states)", 0.1, 1, Config.Step, false)
addSlider("AnchorX", "Anchor X", -2, 2, Config.Step, false)
addSlider("AnchorY", "Anchor Y", -2, 1, Config.Step, false)
addSlider("AnchorZ", "Anchor Z", -4, 2, Config.Step, false)
addSlider("ArmX", "Hand X", -2, 2, Config.Step, false)
addSlider("ArmY", "Hand Y", -2, 1, Config.Step, false)
addSlider("ArmZ", "Hand Z", -4, 2, Config.Step, false)
addSlider("RotateX", "Rotate X", -180, 180, Config.AngleStep, false)
addSlider("RotateY", "Rotate Y", -180, 180, Config.AngleStep, false)
addSlider("RotateZ", "Rotate Z", -180, 180, Config.AngleStep, false)

panel:AddButton("reset this state", function()
	readState()
	for _, reset in resetters do reset() end
	apply(true)
end)

panel:AddLabel(
	"Live follows the game; the other states hold the viewmodel still so you can tune them. Base uses"
		.. " absolute anchors, poses use offsets from it, and framed states solve their own placement so"
		.. " only coverage and hand offset apply. Changes are local to this session - paste the whole"
		.. " generated entry into ViewmodelConfig, poses included."
)

readState()
setState(1)

return ViewmodelDebugService
