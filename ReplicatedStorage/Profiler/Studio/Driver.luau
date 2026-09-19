local Root = script.Parent.Parent
local Scripts = require(Root.Collectors.Scripts)
local Driver = {}

function Driver.Run(scenario,options,player)
	assert(game:GetService("RunService"):IsServer(),"Call Driver.Run in the Server datamodel of a running Studio test")
	assert(game:GetService("RunService"):IsStudio(),"Studio driver is Studio-only")
	local api = require(game:GetService("ServerStorage").Profiler.Bootstrap).Start()
	assert(api:Status().state == "idle","A run is already active")
	local runtime = game:GetService("ServerStorage").Profiler.Runtime
	assert(not runtime:FindFirstChild("BeforeDiagnostics"),"Previous Script Profiler capture is still finishing")
	player = player or game:GetService("Players"):GetPlayers()[1]
	assert(player,"No player client")
	options = table.clone(options or {}); options.mode = "diagnostic"
	assert(options.repeats == nil or options.repeats == 1,"Script Profiler driver captures one trial; use separate runs for repeats")
	options.repeats = 1
	local server = Scripts.Start("server",player)
	local client = Scripts.Start("client",player)
	local ok,id = pcall(api.Start,api,scenario,options,player)
	if not ok then Scripts.Finish(server); Scripts.Finish(client); error(id,0) end
	local hook = Instance.new("BindableFunction")
	hook.Name = "BeforeDiagnostics"
	hook:SetAttribute("RunId",id)
	hook.OnInvoke = function(runId)
		if runId == id then Scripts.Pause(server); Scripts.Pause(client) end
	end
	hook.Parent = runtime
	task.spawn(function()
		while api:Status().id == id do task.wait(0.2) end
		local captures = { server = Scripts.Finish(server), client = Scripts.Finish(client) }
		local attached,err = pcall(function() api:Command({action="attachDiagnostics",id=id,captures=captures}) end)
		hook:Destroy()
		if not attached then warn(err) end
	end)
	return id
end

return Driver
