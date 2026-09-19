local Settings = require(script.Parent.Parent.Config.Settings)
local Statistics = require(script.Parent.Statistics)
local Options = {}

function Options.Parse(input, definition)
	input = input or {}
	assert(type(input) == "table", "Options must be a table")
	local function number(key, fallback, minimum, maximum)
		local value = if input[key] == nil then fallback else input[key]
		assert(Statistics.Finite(value) and value >= minimum and value <= maximum, "Invalid " .. key)
		return value
	end
	local function text(key, fallback)
		local value = input[key] or fallback
		assert(type(value) == "string" and #value <= 120, "Invalid " .. key)
		return value
	end
	local focus = text("focus", definition.Focus or "all")
	assert(table.find({ "all", "render", "memory", "server", "network", "functions" }, focus), "Unknown focus")
	local mode = text("mode", "score")
	assert(mode == "score" or mode == "diagnostic", "Mode must be score or diagnostic")
	local prefixes = input.scopes or {}
	assert(type(prefixes) == "table" and #prefixes <= 16, "Invalid scope filter")
	for _, prefix in prefixes do assert(type(prefix) == "string" and #prefix <= 120, "Invalid scope prefix") end
	local repeats = number("repeats", Settings.Repeats, 1, Settings.MaxRepeats)
	assert(repeats % 1 == 0, "Repeats must be an integer")
	return {
		duration = number("duration", Settings.Duration, 1, Settings.MaxDuration),
		warmup = number("warmup", Settings.Warmup, 0, 60), repeats = repeats,
		frameBudgetMs = number("frameBudgetMs", 1000 / 60, 1, 1000),
		seed = number("seed", 1729, 0, 2147483647), focus = focus, mode = mode,
		scopes = table.clone(prefixes), build = text("build", Settings.Build),
		device = text("device", "unlabeled"), frameCap = text("frameCap", "unknown"),
		powerState = text("powerState", "unknown"),
	}
end

return Options
