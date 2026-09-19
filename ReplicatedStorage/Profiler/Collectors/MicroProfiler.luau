local Settings = require(script.Parent.Parent.Config.Settings)
local MicroProfiler = {}
local library

function MicroProfiler.Start()
	local ok, value = pcall(function()
		library = library or require(script.Parent.Parent.Vendor.LibMP)
		assert(library.Control:IsBackendReady(), "MicroProfiler backend unavailable or version-incompatible")
		assert(library.Control:EnableProfiler(true) ~= false, "Profiler could not be enabled")
		assert(library.Control:SetFrameLimit(128),"Could not set capture frame limit")
		assert(library.Control:EnableCapture(true),"Could not start capture")
		return { library = library, available = true }
	end)
	return if ok then value else { available = false, reason = tostring(value) }
end

-- This is diagnostic work, outside scoring. Inclusive scope totals overlap and
-- are CPU-core work, not frame duration. GPU ticks use their own conversion scale.
function MicroProfiler.Finish(handle, focus)
	if not handle.available then return handle end
	local session, iterator
	local ok, result = pcall(function()
		local lib = handle.library
		lib.Control:EnableCapture(false)
		task.wait(0.2)
		local snapshot = lib.Control:CaptureToBufferSync()
		assert(snapshot, "No capture returned")
		session = lib.Session.OpenFromBuffer(snapshot)
		assert(session and session:IsValid(), "Invalid MicroProfiler snapshot")
		local scales = session:FetchGlobalDesc()
		local totals = {}
		iterator = session:CreateLogIterator()
		iterator:Configure({ SkipEvents = true })
		local state = iterator:GetState()
		local steps = 0
		while iterator:Step() do
			steps += 1
			if steps > 500000 then break end
			if not state:IsExit() or state:ThreadStackIsUnderflowed() or state:ThreadStackWasOverflowed() then continue end
			local element = iterator:GetCurrentThreadStackElement(state:ThreadStackDepth())
			if not element then continue end
			local timerId = state:TimerId()
			local gpu = state:IsGpuThread()
			local duration = (state:Timestamp() - element:EnterTimestamp()) * (if gpu then scales.TickToMsGpu else scales.TickToMsCpu)
			if duration < 0 or duration > 60000 then continue end
			local key = tostring(timerId) .. (if gpu then "/gpu" else "/cpu")
			local row = totals[key]
			if not row then
				local desc = session:FetchTimerDesc(timerId)
				local group = session:FetchGroupDesc(desc.GroupId)
				row = { name = desc.TimerName, group = group.GroupName, gpu = gpu, inclusiveMs = 0, maxMs = 0, count = 0 }
				totals[key] = row
			end
			row.inclusiveMs += duration; row.maxMs = math.max(row.maxMs, duration); row.count += 1
		end
		local rows = {}
		for _, row in totals do
			local name = string.lower(row.name .. " " .. row.group)
			local relevant = focus == "all" or focus == "memory"
				or (focus == "render" and (row.gpu or name:find("render") or name:find("draw")))
				or (focus == "functions" and (name:find("script") or name:find("luau") or name:find("profiler/")))
				or (focus == "server" and (name:find("physics") or name:find("heartbeat") or name:find("script")))
				or (focus == "network" and (name:find("network") or name:find("replic")))
			if relevant then table.insert(rows, row) end
		end
		table.sort(rows, function(a,b) return a.inclusiveMs > b.inclusiveMs end)
		while #rows > Settings.TopEntries do table.remove(rows) end
		return { available = true, libraryVersion = lib.Versions.Library,
			firstFrame = session:GetFrameIdMin(), lastFrame = session:GetFrameIdMax(), snapshotBytes = buffer.len(snapshot),
			truncated = steps > 500000, top = rows,
			semantics = "Recent process-wide capture; Studio can include editor/client/server threads. Edge scopes excluded; inclusive totals overlap. Not full-run or side-isolated CPU." }
	end)
	if iterator then pcall(function() iterator:Dispose() end) end
	if session then pcall(function() session:Dispose() end) end
	pcall(function() handle.library.Control:EnableCapture(false) end)
	pcall(function() handle.library.Control:EnableProfiler(false) end)
	return if ok then result else { available = false, reason = tostring(result) }
end

return MicroProfiler
