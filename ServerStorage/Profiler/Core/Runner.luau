local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Root = game:GetService("ReplicatedStorage").Profiler
local Settings = require(Root.Config.Settings)
local Context = require(Root.Core.Context)
local Environment = require(Root.Core.Environment)
local Options = require(Root.Core.Options)
local Phase = require(Root.Core.Phase)
local Compare = require(Root.Core.Compare)
local Scene = require(Root.Collectors.Scene)
local MP = require(Root.Collectors.MicroProfiler)
local Scripts = require(Root.Collectors.Scripts)
local Access = require(script.Parent.Access)
local Lifecycle = require(script.Parent.Parent.Config.Lifecycle)
local Runner = {}
Runner.__index = Runner

function Runner.new(registry, rpc, store, runtime)
	return setmetatable({ registry = registry, rpc = rpc, store = store, runtime = runtime }, Runner)
end

function Runner:Status()
	return if self.active then { id = self.active.id, state = self.active.state, trial = self.active.trial, phase = self.active.phase }
		else { state = "idle", lastRun = self.lastRun }
end

function Runner:Progress(state, trial, phase)
	if not self.active then return end
	self.active.state = state; self.active.trial = trial; self.active.phase = phase
	self.runtime:SetAttribute("State",state); self.runtime:SetAttribute("Trial",trial); self.runtime:SetAttribute("Phase",phase)
end

local function bounded(ctx, callback, timeout)
	local done, ok, value = false, false, nil
	local thread = task.spawn(function() ok,value = xpcall(callback,debug.traceback); done = true end)
	local deadline = os.clock()+timeout
	while not done and os.clock()<deadline and not ctx.Cancelled do task.wait(0.05) end
	if not done then pcall(task.cancel,thread); error("Operation timed out or cancelled",0) end
	if not ok then error(value,0) end
	return value
end

function Runner:Trial(report, index, definition, player)
	local ctx = Context.new(player,report.options)
	self.active.ctx = ctx
	local server = { phases = {}, environment = Environment.Read(report.options) }
	local trial = { status = "failed", server = server }
	local mp, scripts
	local ok, err = xpcall(function()
		self:Progress("preparing",index,"")
		ctx:WaitFor(function() return self.rpc.ready[player] end,Settings.RequestTimeout,"profiler client readiness")
		if definition.Controlled then
			ctx:Defer(function() if Lifecycle.AfterTrial then Lifecycle.AfterTrial(ctx,definition) end end)
			if Lifecycle.BeforeTrial then bounded(ctx,function() Lifecycle.BeforeTrial(ctx,definition) end,Settings.RequestTimeout) end
		end
		if definition.Prepare then bounded(ctx,function() definition.Prepare(ctx) end,Settings.RequestTimeout) end
		self.rpc:Call(ctx,"prepare",{ scenario = definition.Id, options = report.options, data = ctx.ClientData },Settings.RequestTimeout)
		if report.options.mode == "diagnostic" then mp = MP.Start(); scripts = Scripts.Start("server",player) end
		for _, phase in definition.Phases or { "steady" } do
			self:Progress("warming",index,phase)
			if definition.PreparePhase then bounded(ctx,function() definition.PreparePhase(ctx,phase) end,Settings.RequestTimeout) end
			self.rpc:Call(ctx,"preparePhase",{ phase = phase },Settings.RequestTimeout)
			ctx:Sleep(report.options.warmup)
			local startAt = workspace:GetServerTimeNow()+0.5
			local clientDone, clientOk, clientError = false, false, nil
			local clientThread = task.spawn(function()
				clientOk,clientError = pcall(function()
					return self.rpc:Call(ctx,"phase",{ phase = phase, startAt = startAt, duration = report.options.duration },report.options.duration+15)
				end)
				clientDone = true
			end)
			ctx:Defer(function() if coroutine.status(clientThread) ~= "dead" then task.cancel(clientThread) end end)
			self:Progress("measuring",index,phase)
			local measured = Phase.Run(ctx,definition,phase,startAt,report.options.duration)
			table.insert(server.phases,measured)
			ctx:Check("full duration: " .. phase,not definition.Controlled or measured.duration >= report.options.duration*0.95)
			ctx:WaitFor(function() return clientDone end,15,"client measurement")
			assert(clientOk,clientError)
			if definition.ValidatePhase then definition.ValidatePhase(ctx,phase) end
			if ctx.StopRequested then break end
		end
		self:Progress("finishing",index,"")
		if definition.Validate then definition.Validate(ctx) end
		if definition.Controlled and Lifecycle.Validate then Lifecycle.Validate(ctx,definition) end
		local captureHook = self.runtime:FindFirstChild("BeforeDiagnostics")
		if captureHook then captureHook:Invoke(report.id) end
		trial.client = self.rpc:Call(ctx,"finish",{},Settings.RequestTimeout)
		if report.options.mode == "diagnostic" then
			server.diagnostics = bounded(ctx,function()
				return { microProfiler = MP.Finish(mp,report.options.focus), scene = Scene.Capture(report.options.focus), scripts = Scripts.Finish(scripts) }
			end,Settings.DiagnosticTimeout)
		end
		trial.status = "completed"
		trial.stopped = ctx.StopRequested == true
	end,debug.traceback)
	if not ok then
		trial.error = tostring(err)
		trial.status = if ctx.Cancelled then "cancelled" else "failed"
		self.rpc.remote:FireClient(player,{ kind = "abort" })
		if ctx.ActiveCollector then ctx.ActiveCollector:Stop() end
		if mp and mp.library then pcall(function() mp.library.Control:EnableCapture(false) end) end
		if scripts and scripts.available then Scripts.Finish(scripts) end
	end
	local cleanupErrors = ctx:Cleanup()
	ctx:Check("cleanup",#cleanupErrors == 0,table.concat(cleanupErrors,"; "))
	server.checks = ctx.Checks; server.events = ctx.Events
	return trial
end

function Runner:Start(id, input, player)
	assert(not self.active,"A profiler run is already active")
	assert(not self.runtime:FindFirstChild("BeforeDiagnostics"),"Script Profiler capture is still finishing")
	player = player or Players:GetPlayers()[1]
	assert(player and Access.Allowed(player),"Profiler access denied")
	local definition = assert(self.registry.items[id],"Unknown scenario")
	assert(not definition.Controlled or Access.ControlledAllowed(),"Controlled tests require Studio or a private server")
	local options = Options.Parse(input,definition)
	assert(not definition.DiagnosticOnly or options.mode == "diagnostic","This scenario requires diagnostic mode")
	local runId = HttpService:GenerateGUID(false)
	local report = { schema = Settings.SchemaVersion, id = runId, created = DateTime.now():ToIsoDate(), options = options,
		lifecycle = if definition.Controlled then {id=Lifecycle.Id,version=Lifecycle.Version} else nil,
		scenario = { id = id, version = definition.Version, description = definition.Description, controlled = definition.Controlled == true },
		trials = {}, status = "running", valid = false, warnings = {} }
	self.active = { id = runId, state = "starting", player = player }
	self.runtime:SetAttribute("RunId",runId)
	self.rpc.remote:FireClient(player,{kind="started",id=runId})
	task.spawn(function()
		local ok, err = xpcall(function()
			for index = 1, options.repeats do
				local trial = self:Trial(report,index,definition,player)
				table.insert(report.trials,trial)
				if trial.status ~= "completed" then report.status = trial.status; break end
				if trial.stopped then break end
			end
			if report.status == "running" then report.status = "completed" end
			report.valid = report.status == "completed"
			for _, trial in report.trials do
				for _, sideName in {"server","client"} do
					local side = trial[sideName]
					if not side then report.valid = false; continue end
					for _, check in side.checks or {} do if not check.passed then report.valid = false end end
					for _, phase in side.phases or {} do
						if phase.cadence.count < 10 or phase.cadence.truncated or phase.samplesDropped > 0 or phase.focusLost or phase.focusAtStart == false or phase.uiVisible then
							report.valid = false
							local reasons = {}
							if phase.cadence.count < 10 then table.insert(reasons,"fewer than 10 frame samples") end
							if phase.cadence.truncated or phase.samplesDropped > 0 then table.insert(reasons,"samples truncated/dropped") end
							if phase.focusLost or phase.focusAtStart == false then table.insert(reasons,"window lost focus") end
							if phase.uiVisible then table.insert(reasons,"profiler panel open during measurement") end
							table.insert(report.warnings,sideName .. "/" .. phase.phase .. ": " .. table.concat(reasons,", "))
						end
					end
				end
			end
		end,debug.traceback)
		if not ok then report.status = "failed"; report.valid = false; table.insert(report.warnings,tostring(err)) end
		if not definition.Controlled then table.insert(report.warnings,"Observational recording; not eligible for a controlled improvement claim") end
		if options.mode == "diagnostic" then table.insert(report.warnings,"Profilers add overhead; diagnostic runs are not scored against score-mode baselines") end
		table.insert(report.warnings,"Studio/background throttling and device power state can dominate FPS; use fixed foreground conditions for comparisons")
		self.store:Put(report)
		self.lastRun = runId; self.active = nil
		self.runtime:SetAttribute("State","idle"); self.runtime:SetAttribute("LastRun",runId)
		if player.Parent then self.rpc.remote:FireClient(player,{ kind = "completed", id = runId }) end
	end)
	return runId
end

function Runner:Cancel(stop)
	assert(self.active,"No active run")
	local ctx = self.active.ctx
	if ctx then
		if stop then ctx.StopRequested = true else ctx.Cancelled = true end
	end
	self.rpc.remote:FireClient(self.active.player,{ kind = if stop then "stop" else "abort" })
	return true
end

function Runner:Await(id, timeout)
	timeout = timeout or 3600
	assert(type(timeout)=="number" and timeout==timeout and timeout>0 and timeout<=3600,"Wait timeout must be in (0,3600] seconds")
	local deadline = os.clock()+timeout
	repeat
		local report = self.store.reports[id]
		local hook = self.runtime:FindFirstChild("BeforeDiagnostics")
		if report and not (hook and hook:GetAttribute("RunId")==id) then return report end
		assert(report or (self.active and self.active.id==id),"Unknown or evicted run")
		task.wait(0.05)
	until os.clock()>=deadline
	return nil,{id=id,state="pending",progress=self:Status()}
end

function Runner:Run(id, options, player, timeout)
	return self:Await(self:Start(id,options,player),timeout)
end

function Runner:Compare(baselineId,candidateId,target,metric)
	local a = assert(self.store.reports[baselineId],"Baseline not found")
	local b = assert(self.store.reports[candidateId],"Candidate not found")
	local result = Compare.Run(a,b,target,metric)
	b.comparison = result; self.store:Put(b)
	return result
end

return Runner
