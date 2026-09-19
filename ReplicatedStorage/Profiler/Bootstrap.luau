local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Root = script.Parent
local Registry = require(Root.Core.Registry)
local Session = require(Root.Core.ClientSession)
local Transport = require(Root.Core.ClientTransport)
local Panel = require(Root.UI.Panel)
local Bootstrap = {}
local api

function Bootstrap.Start()
	if api then return api end
	assert(game:GetService("RunService"):IsClient(),"Use ServerStorage.Profiler on the server")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui",10)
	local existing = playerGui:FindFirstChild("ProfilerBridge")
	if existing and existing:FindFirstChild("Command") then
		local proxy = {}
		function proxy:Open() return existing.Command:Invoke({action="open"}) end
		function proxy:Command(command) return existing.Command:Invoke(command) end
		function proxy:Export(id,format) return existing.Command:Invoke({action="export",id=id,format=format}) end
		return proxy
	end
	local remote = assert(Root:WaitForChild("Transport",30),"Profiler server did not start")
	local transport = Transport.new(remote)
	local session = Session.new(Registry.new(Root.Scenarios))
	local panel
	api = { transport = transport, session = session }
	function api:Open()
		panel = panel or Panel.new(transport)
		panel:Show()
		if session.ctx and session.ctx.ActiveCollector then session.ctx.ActiveCollector.uiVisible = true end
		return panel
	end
	function api:Command(command) return transport:Command(command) end
	function api:Export(id,format) return transport:Export(id,format) end
	local bridge = Instance.new("Folder")
	bridge.Name = "ProfilerBridge"; bridge.Parent = Players.LocalPlayer:WaitForChild("PlayerGui",10)
	local request = Instance.new("StringValue"); request.Name = "Request"; request.Parent = bridge
	local response = Instance.new("StringValue"); response.Name = "Response"; response.Parent = bridge
	local callable = Instance.new("BindableFunction"); callable.Name = "Command"; callable.Parent = bridge
	callable.OnInvoke = function(command)
		if command.action == "open" then api:Open(); return true end
		if command.action == "export" then return api:Export(command.id,command.format) end
		return api:Command(command)
	end
	request.Changed:Connect(function(json)
		local requestId
		local ok,value = pcall(function()
			local command = HttpService:JSONDecode(json); requestId = command.requestId
			if command.action == "open" then api:Open(); return true end
			return transport:Command(command)
		end)
		response.Value = HttpService:JSONEncode({ requestId = requestId,ok = ok,value = if ok then value else tostring(value) })
	end)
	remote.OnClientEvent:Connect(function(message)
		if message.kind == "started" then
			if panel then panel:Hide() end
		elseif message.kind == "rpc" then
			session.worker = task.spawn(function()
				local ok,value = xpcall(function() return session:Call(message.action,message.payload) end,debug.traceback)
				remote:FireServer({ kind = "reply",token = message.token,ok = ok,value = if ok then value else tostring(value) })
			end)
		elseif message.kind == "abort" then session:Abort()
		elseif message.kind == "stop" then if session.ctx then session.ctx.StopRequested = true end
		elseif message.kind == "open" then task.spawn(function() api:Open() end)
		elseif message.kind == "completed" then
			if panel then panel.lastId = message.id end
			if panel and panel.openAfterRun then
				panel.openAfterRun = false
				task.spawn(function() panel:Show(); panel:LoadReport() end)
			end
		end
	end)
	remote:FireServer({ kind = "ready" })
	return api
end

return Bootstrap
