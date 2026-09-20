local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage.Profiler
local Settings = require(Root.Config.Settings)
local Registry = require(Root.Core.Registry)
local Report = require(Root.Core.Report)
local Access = require(script.Parent.Core.Access)
local Store = require(script.Parent.Core.Store)
local Rpc = require(script.Parent.Core.Rpc)
local Runner = require(script.Parent.Core.Runner)
local Bootstrap = {}
local api

local function child(parent,class,name)
	local item = parent:FindFirstChild(name) or Instance.new(class)
	assert(item.ClassName == class,"Profiler instance conflict: " .. name)
	item.Name = name; item.Parent = parent
	return item
end

function Bootstrap.Start()
	if api then return api end
	local existing = script.Parent:FindFirstChild("Runtime")
	if existing and existing:GetAttribute("Initialized") then
		local proxy = {}
		function proxy:Command(command,player)
			return existing.Command:Invoke(command,player)
		end
		function proxy:Start(id,options,player) return self:Command({action="start",scenario=id,options=options},player).id end
		function proxy:Status() return self:Command({action="status"}) end
		function proxy:Await(id,timeout) return self:Command({action="await",id=id,timeout=timeout}) end
		function proxy:Run(id,options,player,timeout) return self:Await(self:Start(id,options,player),timeout) end
		function proxy:Cancel(stop) return self:Command({action=if stop then "stop" else "cancel"}) end
		function proxy:Compare(a,b,target,metric) return self:Command({action="compare",baseline=a,candidate=b,target=target,metric=metric}) end
		return proxy
	end
	local remote = child(Root,"RemoteEvent","Transport")
	local runtime = child(script.Parent,"Folder","Runtime")
	local results = child(runtime,"Folder","Results")
	local store = Store.new(results)
	api = Runner.new(Registry.new(script.Parent.Scenarios),Rpc.new(remote),store,runtime)
	function api:Command(command,player)
		assert(type(command) == "table","Command must be a table")
		local action = command.action
		if action == "await" then return self:Await(command.id,command.timeout) end
		if action == "getReport" then return store.reports[command.id or self.lastRun] end
		if action == "attachDiagnostics" then
			local report = assert(store.reports[command.id],"Report not ready")
			report.scriptProfiler = command.captures; store:Put(report); return true
		end
		if action == "list" then return { scenarios = self.registry:List(), errors = self.registry.errors } end
		if action == "status" then return self:Status() end
		if action == "start" then return { id = self:Start(command.scenario,command.options,player) } end
		if action == "cancel" or action == "stop" then return self:Cancel(action == "stop") end
		if action == "history" then
			if not command.details then return table.clone(store.order) end
			local history = {}
			for _,id in store.order do
				local report = store.reports[id]
				table.insert(history,{id=id,scenario=report.scenario.id,build=report.options.build,created=report.created or "Imported",status=report.status})
			end
			return history
		end
		if action == "import" then return { id = store:Import(command.json) } end
		if action == "compare" then return self:Compare(command.baseline,command.candidate,command.target,command.metric) end
		if action == "result" then
			local report = assert(store.reports[command.id or self.lastRun],"Report not ready or was evicted")
			local content = if command.format == "json" or command.format == "baseline" then Report.Json(report,command.format == "baseline") elseif command.format == "details" then Report.Detailed(report) else Report.Format(report)
			local offset = command.offset or 1
			assert(type(offset) == "number" and offset % 1 == 0 and offset >= 1 and offset <= #content+1,"Invalid offset")
			return { id = report.id, text = string.sub(content,offset,offset+Settings.ChunkBytes-1),
				nextOffset = if offset+Settings.ChunkBytes <= #content then offset+Settings.ChunkBytes else nil,
				totalBytes = #content }
		end
		error("Unknown command: " .. tostring(action))
	end
	local request = child(runtime,"StringValue","Request")
	local response = child(runtime,"StringValue","Response")
	local busy = false
	request.Changed:Connect(function(json)
		if busy then return end
		busy = true
		local requestId
		local ok,value = pcall(function()
			assert(#json <= Settings.MaxImportBytes+4096,"Command too large")
			local command = HttpService:JSONDecode(json); requestId = command.requestId
			local player = if command.playerUserId then Players:GetPlayerByUserId(command.playerUserId) else nil
			return api:Command(command,player)
		end)
		response.Value = HttpService:JSONEncode({ requestId = requestId, ok = ok, value = if ok then value else tostring(value) })
		busy = false
	end)
	local callable = child(runtime,"BindableFunction","Command")
	callable.OnInvoke = function(command,player) return api:Command(command,player) end
	local inflight, lastRequest = {}, {}
	remote.OnServerEvent:Connect(function(player,message)
		if type(message) ~= "table" or message.kind ~= "command" or type(message.token) ~= "string" or #message.token > 100 then return end
		local function reject(code)
			if player.Parent then remote:FireClient(player,{kind="commandReply",token=message.token,ok=false,
				code=code,retryable=true,value="Profiler command not executed: " .. code}) end
		end
		if inflight[player] then reject("busy"); return end
		local now = os.clock()
		if now - (lastRequest[player] or 0) < Settings.ServerCommandInterval then reject("throttled"); return end
		lastRequest[player] = now; inflight[player] = true
		local ok,value = pcall(function()
			assert(Access.Allowed(player),"Profiler access denied")
			assert(message.command and not table.find({"getReport","attachDiagnostics","await"},message.command.action),"Server-only command")
			if api.active and message.command and (message.command.action == "cancel" or message.command.action == "stop") then
				assert(api.active.player == player,"Another developer owns the active run")
			end
			return api:Command(message.command,player)
		end)
		inflight[player] = nil
		if player.Parent then remote:FireClient(player,{ kind = "commandReply", token = message.token, ok = ok, value = if ok then value else tostring(value) }) end
	end)
	local function open(player)
		if Access.Allowed(player) then remote:FireClient(player,{ kind = "open" }) end
	end
	local chat = child(TextChatService,"TextChatCommand","ProfilerCommand")
	chat.PrimaryAlias = "/profile"
	chat.Triggered:Connect(function(source)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then open(player) end
	end)
	local function watch(player)
		player.Chatted:Connect(function(message)
			if message:lower():match("^/profile%s*$") then open(player) end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do watch(player) end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil; inflight[player] = nil
		if api.active and api.active.player == player and api.active.ctx then api.active.ctx.Cancelled = true end
	end)
	runtime:SetAttribute("State","idle")
	runtime:SetAttribute("Initialized",true)
	return api
end

return Bootstrap
