local RunService = game:GetService("RunService")
local Runtime = require(script.Parent.Parent.Collectors.Runtime)
local Phase = {}

function Phase.Run(ctx, definition, phase, startAt, duration)
	ctx:WaitFor(function() return workspace:GetServerTimeNow() >= startAt end, 10, "phase start")
	local collector = Runtime.new(ctx.Options, ctx.Player)
	ctx.ActiveCollector = collector
	collector:Start()
	local started = os.clock()
	local ok, err = xpcall(function()
		while os.clock() - started < duration do
			assert(not ctx.Cancelled, "Cancelled")
			if ctx.StopRequested then break end
			local dt = RunService.Heartbeat:Wait()
			if definition.Step then definition.Step(ctx, phase, os.clock() - started, dt) end
		end
	end, debug.traceback)
	local result = collector:Stop()
	ctx.ActiveCollector = nil
	result.phase = phase
	if not ok then error(err, 0) end
	return result
end

return Phase
