local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.FlashlightDebugConfig)
local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local FlashlightConfig = require(ReplicatedStorage.Configs.FlashlightConfig)
local FlashlightService = require(ReplicatedStorage.Services.FlashlightService)

local FlashlightDebugService = {}

if not (FLAGS.FlashlightDebug and RunService:IsClient()) then
	return FlashlightDebugService
end

local WHITE = Color3.new(1, 1, 1)

local defaults = {
	Color = FlashlightConfig.Color,
	Master = FlashlightConfig.Master,
	CameraOffset = FlashlightConfig.CameraOffset,
	Cones = {},
}
for index, cone in FlashlightConfig.Cones do
	defaults.Cones[index] = table.clone(cone)
end

local panel = DebugPanel.new("flashlight beam", Config.ToggleKey)
local output = panel:AddTextBox("")
local selected = #FlashlightConfig.Cones
local coneButton: TextButton
local displays: { [string]: (number) -> () } = {}

local function formatNumber(value: number): string
	if value == math.floor(value) then return string.format("%d", value) end
	return string.format("%.2f", value)
end

local function warmthOf(color: Color3): number
	local span = 1 - Config.WarmColor.B
	if span <= 0 then return 0 end
	return math.clamp((1 - color.B) / span, 0, 1)
end

local function updateOutput()
	local color = FlashlightConfig.Color
	local offset = FlashlightConfig.CameraOffset
	local lines = {
		`\tColor = Color3.fromRGB({math.round(color.R * 255)}, {math.round(color.G * 255)}, {math.round(color.B * 255)}),`,
		`\tMaster = {formatNumber(FlashlightConfig.Master)},`,
		"",
		`\tCameraOffset = Vector3.new({formatNumber(offset.X)}, {formatNumber(offset.Y)}, {formatNumber(offset.Z)}),`,
		"",
		"\tCones = {",
	}
	for _, cone in FlashlightConfig.Cones do
		table.insert(
			lines,
			string.format(
				'\t\t{ Name = "%s", Angle = %s, Range = %s, Brightness = %s, Shadows = %s },',
				cone.Name,
				formatNumber(cone.Angle),
				formatNumber(cone.Range),
				formatNumber(cone.Brightness),
				tostring(cone.Shadows)
			)
		)
	end
	table.insert(lines, "\t},")
	output.Text = table.concat(lines, "\n")
end

local function apply()
	FlashlightService:Refresh()
	updateOutput()
end

local function refreshConeSliders()
	local cone = FlashlightConfig.Cones[selected]
	if not cone then return end

	coneButton.Text = `cone: {cone.Name} ({selected}/{#FlashlightConfig.Cones})`
	displays.Angle(cone.Angle)
	displays.Range(cone.Range)
	displays.Brightness(cone.Brightness)
end

coneButton = panel:AddButton("cone", function()
	selected += 1
	if selected > #FlashlightConfig.Cones then selected = 1 end
	refreshConeSliders()
end)

local function addConeSlider(key: string, label: string, maximum: number, step: number)
	displays[key] = panel:AddSlider(label, 0, maximum, 0, step, function(value)
		local cone = FlashlightConfig.Cones[selected]
		if not cone then return end
		cone[key] = value
		apply()
	end)
end

addConeSlider("Angle", "Angle", 180, Config.AngleStep)
addConeSlider("Range", "Range", 60, Config.AngleStep)
addConeSlider("Brightness", "Brightness", 6, Config.Step)

local masterDisplay = panel:AddSlider("Master brightness", 0, 4, FlashlightConfig.Master, Config.Step, function(value)
	FlashlightConfig.Master = value
	apply()
end)

local warmthDisplay = panel:AddSlider("Warmth", 0, 1, warmthOf(FlashlightConfig.Color), Config.Step, function(value)
	FlashlightConfig.Color = WHITE:Lerp(Config.WarmColor, value)
	apply()
end)

local function addOffsetSlider(axis: string): (number) -> ()
	return panel:AddSlider(`Offset {axis}`, -3, 3, FlashlightConfig.CameraOffset[axis], Config.Step, function(value)
		local offset = FlashlightConfig.CameraOffset
		FlashlightConfig.CameraOffset = Vector3.new(
			if axis == "X" then value else offset.X,
			if axis == "Y" then value else offset.Y,
			if axis == "Z" then value else offset.Z
		)
		apply()
	end)
end

local offsetDisplays = {
	X = addOffsetSlider("X"),
	Y = addOffsetSlider("Y"),
	Z = addOffsetSlider("Z"),
}

panel:AddButton("reset to config defaults", function()
	FlashlightConfig.Color = defaults.Color
	FlashlightConfig.Master = defaults.Master
	FlashlightConfig.CameraOffset = defaults.CameraOffset
	for index, cone in defaults.Cones do
		local live = FlashlightConfig.Cones[index]
		if live then
			live.Angle = cone.Angle
			live.Range = cone.Range
			live.Brightness = cone.Brightness
			live.Shadows = cone.Shadows
		end
	end

	masterDisplay(defaults.Master)
	warmthDisplay(warmthOf(defaults.Color))
	offsetDisplays.X(defaults.CameraOffset.X)
	offsetDisplays.Y(defaults.CameraOffset.Y)
	offsetDisplays.Z(defaults.CameraOffset.Z)
	refreshConeSliders()
	apply()
end)

panel:AddLabel(
	"Cones stack from the widest wash to the narrowest core; the overlap is what makes the falloff smooth."
		.. " ShadowMap lighting drops cones below roughly 40 degrees entirely, however bright they are."
		.. " Equip a flashlight and turn it on to see changes. Paste the block above into FlashlightConfig."
)

refreshConeSliders()
updateOutput()

return FlashlightDebugService
