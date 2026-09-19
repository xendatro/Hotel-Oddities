local Settings = require(script.Parent.Parent.Config.Settings)
local Scripts = {}

-- PluginSecurity is tested, not inferred from the service existing. Ordinary
-- scripts normally cannot use this. The Studio driver calls the same collector
-- from an MCP/plugin thread and attaches its result to a diagnostic report.
function Scripts.Start(side,player)
	local handle = { side = side, player = player, started = os.clock(), available = false }
	local ok,err = pcall(function()
		local service = game:GetService("ScriptProfilerService")
		handle.service = service
		handle.connection = service.OnNewData:Connect(function(owner,json)
			if (side == "server" and owner == nil) or (side == "client" and owner == player) then handle.json = json end
		end)
		if side == "server" then service:ServerStart(1000) else service:ClientStart(player,1000) end
		handle.available = true
	end)
	if not ok then
		if handle.connection then handle.connection:Disconnect() end
		handle.reason = tostring(err)
	end
	return handle
end

function Scripts.Pause(handle)
	if not handle.available or handle.stopped then return end
	if handle.side == "server" then handle.service:ServerStop() else handle.service:ClientStop(handle.player) end
	handle.stopped = true
	handle.stoppedAt = os.clock()
end

function Scripts.Finish(handle)
	if not handle.available then return { available = false, reason = handle.reason } end
	local ok,result = pcall(function()
		local service = handle.service
		Scripts.Pause(handle)
		if handle.side == "server" then service:ServerRequestData()
		else service:ClientRequestData(handle.player) end
		local deadline = os.clock()+8
		while not handle.json and os.clock()<deadline do task.wait(0.05) end
		assert(handle.json,"Script Profiler did not return data")
		local data = service:DeserializeJSON(handle.json)
		local top = {}
		for _, entry in data.Functions or {} do
			table.insert(top,{ name = entry.Name or "anonymous",source = entry.Source or "unknown",line = entry.Line,
				totalCpuMs = (entry.TotalDuration or 0)*1000 })
		end
		table.sort(top,function(a,b) return a.totalCpuMs > b.totalCpuMs end)
		while #top > Settings.TopEntries do table.remove(top) end
		return { available = true, side = handle.side, seconds = handle.stoppedAt-handle.started, frequency = 1000, top = top,
			semantics = "Sampled CPU; includes setup/warmup; function totals overlap. Studio may include plugin work: inspect source paths." }
	end)
	handle.connection:Disconnect()
	return if ok then result else { available = false,reason = tostring(result) }
end

return Scripts
