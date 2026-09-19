local Players = game:GetService("Players")
local Root = script.Parent.Parent
local Context = require(script.Parent.Context)
local Phase = require(script.Parent.Phase)
local Environment = require(script.Parent.Environment)
local Scene = require(Root.Collectors.Scene)
local MP = require(Root.Collectors.MicroProfiler)
local Scripts = require(Root.Collectors.Scripts)
local Session = {}
Session.__index = Session

function Session.new(registry)
	return setmetatable({ registry = registry }, Session)
end

function Session:Abort()
	if self.ctx then
		self.ctx.Cancelled = true
		if self.worker and self.worker ~= coroutine.running() and coroutine.status(self.worker) ~= "dead" then pcall(task.cancel, self.worker) end
		if self.ctx.ActiveCollector then self.ctx.ActiveCollector:Stop() end
		if self.mp and self.mp.library then pcall(function() self.mp.library.Control:EnableCapture(false) end) end
		if self.scripts and self.scripts.available then Scripts.Finish(self.scripts) end
		self.ctx:Cleanup()
		self.ctx = nil
	end
end

function Session:Call(action, payload)
	if action == "prepare" then
		self:Abort()
		local definition = assert(self.registry.items[payload.scenario], "Missing client scenario")
		local ctx = Context.new(Players.LocalPlayer, payload.options)
		self.ctx = ctx; self.definition = definition; self.phases = {}
		ctx.State.Data = payload.data
		if definition.Prepare then definition.Prepare(ctx) end
		self.environment = Environment.Read(payload.options)
		self.environment.sceneSignature = ctx.State.Signature or "unspecified"
		if payload.options.mode == "diagnostic" then
			self.mp = MP.Start(); self.scripts = Scripts.Start("client",Players.LocalPlayer)
		else self.mp = nil; self.scripts = nil end
		return { environment = self.environment }
	elseif action == "preparePhase" then
		if self.definition.PreparePhase then self.definition.PreparePhase(self.ctx,payload.phase) end
		return true
	elseif action == "phase" then
		local result = Phase.Run(self.ctx,self.definition,payload.phase,payload.startAt,payload.duration)
		table.insert(self.phases,result)
		if self.definition.ValidatePhase then self.definition.ValidatePhase(self.ctx,payload.phase) end
		return true
	elseif action == "finish" then
		local ctx = assert(self.ctx, "No active client session")
		if self.definition.Validate then self.definition.Validate(ctx) end
		local diagnostics
		if ctx.Options.mode == "diagnostic" then
			diagnostics = { microProfiler = MP.Finish(self.mp,ctx.Options.focus), scene = Scene.Capture(ctx.Options.focus), scripts = Scripts.Finish(self.scripts) }
		end
		local cleanupErrors = ctx:Cleanup()
		ctx:Check("cleanup",#cleanupErrors == 0,table.concat(cleanupErrors,"; "))
		local result = { phases = self.phases, checks = ctx.Checks, events = ctx.Events,
			environment = self.environment, diagnostics = diagnostics }
		self.ctx = nil
		return result
	end
	error("Unknown client action: " .. tostring(action))
end

return Session
