local Statistics = require(script.Parent.Statistics)
local MetricDeltas = require(script.Parent.MetricDeltas)
local Compare = {}
local environmentKeys = { "placeId", "engine", "studio", "streaming", "players", "packageVersion", "device", "graphics", "viewport", "frameCap", "powerState", "sceneSignature" }

local function metric(trial, name)
	local side = if name == "serverHeartbeatMs" then "server" else "client"
	local data = trial[side]
	if not data then return nil end
	local values, count, time = {}, 0, 0
	for _, phase in data.phases do
		if name == "fps" then count += phase.cadence.count; time += phase.cadence.mean * phase.cadence.count / 1000
		elseif name == "p95FrameMs" then table.insert(values, phase.cadence.p95)
		elseif name == "memoryPeakMb" then table.insert(values, phase.metrics.memoryMb and phase.metrics.memoryMb.max)
		elseif name == "serverHeartbeatMs" then table.insert(values, phase.metrics.heartbeatWorkMs and phase.metrics.heartbeatWorkMs.mean)
		end
	end
	if name == "fps" then return if time > 0 then count / time else nil end
	if #values == 0 then return nil end
	return math.max(table.unpack(values))
end

local function series(report, name)
	local stream = Statistics.New(100)
	for _, trial in report.trials do
		local value = metric(trial, name)
		if not Statistics.Finite(value) then return nil end
		Statistics.Add(stream, value)
	end
	return Statistics.Summary(stream)
end

-- Decide from independent trial means, never from thousands of correlated frames.
-- This approximate t interval assumes independent runs; a fresh confirmation batch
-- is required after adaptive optimization. Missing guardrails cannot silently pass.
function Compare.Run(baseline, candidate, target, metricName)
	target = target or 15; metricName = metricName or "fps"
	local result = { verdict = "invalid", targetPercent = target, metric = metricName,
		baseline = baseline.id, candidate = candidate.id, reasons = {} }
	local function reject(reason) table.insert(result.reasons, reason); return result end
	if not Statistics.Finite(target) or target < 0 or target > 1000 then return reject("Invalid target") end
	if not table.find({ "fps", "p95FrameMs", "memoryPeakMb", "serverHeartbeatMs" }, metricName) then return reject("Unknown metric") end
	if baseline.id == candidate.id then return reject("Cannot compare a run with itself") end
	for _, report in { baseline, candidate } do
		if report.schema ~= 1 or not report.valid or report.status ~= "completed" then return reject("A run is invalid or incomplete") end
		if not report.scenario.controlled or report.options.mode ~= "score" then return reject("Requires controlled scoring runs") end
	end
	if baseline.scenario.id ~= candidate.scenario.id or baseline.scenario.version ~= candidate.scenario.version then return reject("Scenario mismatch") end
	local la,lb = baseline.lifecycle or {},candidate.lifecycle or {}
	if la.id~=lb.id or la.version~=lb.version then return reject("Game lifecycle mismatch") end
	for _, key in { "duration", "warmup", "focus", "seed", "frameBudgetMs" } do
		if baseline.options[key] ~= candidate.options[key] then return reject("Different option: " .. key) end
	end
	if table.concat(baseline.options.scopes, "|") ~= table.concat(candidate.options.scopes,"|") then return reject("Scope filter mismatch") end
	local reference = baseline.trials[1] and baseline.trials[1].client and baseline.trials[1].client.environment
	if not reference then return reject("Missing client environment") end
	for _, report in { baseline, candidate } do
		for _, trial in report.trials do
			local env = trial.client and trial.client.environment
			if not env then return reject("Missing environment") end
			for _, key in environmentKeys do
				if env[key] ~= reference[key] then return reject("Environment mismatch: " .. key) end
			end
		end
	end
	if reference.graphics == "Automatic" then return reject("Lock graphics quality before comparing") end
	result.metricDeltas = MetricDeltas.Build(baseline,candidate)
	local a, b = series(baseline, metricName), series(candidate, metricName)
	if not a or not b or a.mean <= 0 then return reject("Target metric unavailable") end
	local sign = if metricName == "fps" then 1 else -1
	local percent = sign * (b.mean / a.mean - 1) * 100
	result.before = a.mean; result.after = b.mean; result.changePercent = percent
	if a.count < 5 or b.count < 5 then result.verdict = "inconclusive"; return reject("At least five valid trials per build are required") end
	local va, vb = (a.stddev/a.mean)^2/a.count, (b.stddev/b.mean)^2/b.count
	local df = if va+vb > 0 then (va+vb)^2 / (va^2/(a.count-1)+vb^2/(b.count-1)) else 1000
	local t = if df < 5 then 2.776 elseif df < 10 then 2.571 elseif df < 20 then 2.262 elseif df < 30 then 2.093 else 2.045
	local margin = t * (b.mean/a.mean) * math.sqrt(va+vb) * 100
	result.lowerPercent = percent-margin; result.upperPercent = percent+margin
	result.method = "Approximate 95% ratio interval over independent trial summaries; repeat confirmation on fresh runs"
	result.guardrails = {}
	local missingGuard = false
	for _, key in { "p95FrameMs", "memoryPeakMb", "serverHeartbeatMs" } do
		local ga, gb = series(baseline, key), series(candidate,key)
		if ga and gb and ga.mean > 0 then
			local delta = (gb.mean/ga.mean-1)*100
			result.guardrails[key] = delta
			if delta > 5 then result.verdict = "fail"; return reject(key .. " regressed by more than 5%") end
		else missingGuard = true; result.guardrails[key] = "unavailable" end
	end
	if result.upperPercent < target then result.verdict = "fail"
	elseif result.lowerPercent >= target and not missingGuard then result.verdict = "pass"
	else result.verdict = "inconclusive" end
	if missingGuard then table.insert(result.reasons,"Use focus=all to collect all comparison guardrails") end
	return result
end

return Compare
