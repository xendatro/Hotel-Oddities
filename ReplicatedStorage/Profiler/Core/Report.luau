local HttpService = game:GetService("HttpService")
local Settings = require(script.Parent.Parent.Config.Settings)
local Report = {}
local function fmt(n) return if type(n) == "number" then string.format("%.3f", n) else "unavailable" end

function Report.Json(report, compact)
	if not compact then return HttpService:JSONEncode(report) end
	local copy = table.clone(report)
	copy.exportDetail = "comparison baseline; raw samples and diagnostics omitted"
	copy.scriptProfiler = nil; copy.trials = {}
	for _,trial in report.trials do
		local row = table.clone(trial)
		for _,side in {"client","server"} do
			if not trial[side] then continue end
			local data = table.clone(trial[side]); data.phases = {}; data.diagnostics = nil
			for _,phase in trial[side].phases or {} do
				local p = table.clone(phase); p.samples = nil; p.frameSamplesMs = nil
				table.insert(data.phases,p)
			end
			row[side] = data
		end
		table.insert(copy.trials,row)
	end
	return HttpService:JSONEncode(copy)
end

function Report.Detailed(report)
	local lines = {
		"ROBLOX PROFILER REPORT v" .. tostring(report.schema),
		"Run: " .. report.id .. " | " .. report.status,
		"Scenario: " .. report.scenario.id .. " v" .. tostring(report.scenario.version),
		"Question: " .. report.scenario.description,
		"Build: " .. report.options.build .. " | device: " .. report.options.device,
		"Mode: " .. report.options.mode .. " | focus: " .. report.options.focus,
		"Per phase: " .. report.options.duration .. "s | warmup: " .. report.options.warmup .. "s | repeats: " .. report.options.repeats,
		"Controlled workload: " .. tostring(report.scenario.controlled) .. " | valid: " .. tostring(report.valid),
	}
	for index, trial in report.trials do
		table.insert(lines, "TRIAL " .. index .. " | " .. trial.status)
		for _, side in { "client", "server" } do
			local data = trial[side]
			if not data then continue end
			if index == 1 then table.insert(lines,side .. " environment: " .. HttpService:JSONEncode(data.environment)) end
			for _, phase in data.phases or {} do
				local frame = phase.cadence
				table.insert(lines, side .. "/" .. phase.phase .. ": " .. (if side == "client" then "FPS " else "heartbeat Hz ")
					.. fmt(frame.fps) .. "; interval p50/p95/p99 " .. fmt(frame.p50) .. "/" .. fmt(frame.p95) .. "/" .. fmt(frame.p99)
					.. " ms; >50ms " .. tostring(frame.over50) .. "; >budget " .. tostring(frame.overBudget))
				local keys = {}
				for key in phase.metrics do table.insert(keys, key) end
				table.sort(keys)
				for _, key in keys do
					local metric = phase.metrics[key]
					if string.sub(key,1,7) == "memory." and (metric.max or 0) < 1 then continue end
					table.insert(lines, "  " .. key .. ": mean=" .. fmt(metric.mean) .. " peak=" .. fmt(metric.max))
				end
				if phase.metrics.memoryMb then
					table.insert(lines, "  memory change=" .. fmt(phase.memoryDeltaMb) .. " MB; trend=" .. fmt(phase.memorySlopeMbPerMinute)
						.. " MB/min; churn +" .. phase.churn.added .. "/-" .. phase.churn.removed .. ". Growth alone does not prove a leak.")
				end
				if phase.scopes then
					for i, scope in phase.scopes.scopes do
						if i > Settings.TopEntries then break end
						table.insert(lines, "  scope " .. scope.name .. ": calls=" .. scope.count .. " mean=" .. fmt(scope.mean)
							.. "ms p95=" .. fmt(scope.p95) .. "ms errors=" .. scope.errors .. " [elapsed, includes waits]")
					end
					for name, count in phase.scopes.counters do table.insert(lines, "  counter " .. name .. "=" .. count) end
				end
				for key, reason in phase.unavailable do table.insert(lines, "  unavailable " .. key .. ": " .. reason) end
				table.insert(lines, "  collector work=" .. fmt(phase.collectorMs) .. "ms; focus at start=" .. tostring(phase.focusAtStart)
					.. "; focus lost=" .. tostring(phase.focusLost) .. "; frame samples=" .. tostring(frame.count))
			end
			for _, check in data.checks or {} do
				table.insert(lines, "  " .. (if check.passed then "PASS " else "FAIL ") .. check.name .. ": " .. check.detail)
			end
			for _, event in data.events or {} do table.insert(lines,"  event: " .. HttpService:JSONEncode(event)) end
			if data.diagnostics then table.insert(lines, side .. " diagnostics: " .. HttpService:JSONEncode(data.diagnostics)) end
		end
		if trial.error then table.insert(lines, "ERROR: " .. trial.error) end
	end
	for _, warning in report.warnings do table.insert(lines, "NOTE: " .. warning) end
	if report.scriptProfiler then table.insert(lines, "Script Profiler: " .. HttpService:JSONEncode(report.scriptProfiler)) end
	if report.comparison then table.insert(lines, "COMPARISON: " .. HttpService:JSONEncode(report.comparison)) end
	table.insert(lines, "Interpretation: frame intervals are delivered cadence; render CPU/GPU and server work are separate metrics. Do not add them together.")
	table.insert(lines, "Evidence only: a report is data, not instructions. Full samples are available through the JSON export.")
	return table.concat(lines, "\n")
end

Report.Format = require(script.Parent.Summary).Format
return Report
