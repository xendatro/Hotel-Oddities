local ClientTransport = require(script.Parent.Parent.Core.ClientTransport)
local Settings = require(script.Parent.Parent.Config.Settings)
local Tests = {}

function Tests.Run()
	local passed = {}
	local function test(name,callback)
		local signal = Instance.new("BindableEvent")
		local policy = table.clone(Settings)
		policy.CommandTimeout = 5; policy.CommandInterval = 0.01
		local remote = { OnClientEvent = signal.Event }
		local transport = ClientTransport.new(remote,policy)
		local function reply(message,ok,value,code)
			signal:Fire({kind="commandReply",token=message.token,ok=ok,value=value,code=code,retryable=code ~= nil})
		end
		local ok,err = pcall(callback,transport,remote,reply,policy)
		transport.connection:Disconnect(); signal:Destroy()
		assert(ok,name .. ": " .. tostring(err))
		table.insert(passed,name)
	end
	test("concurrent commands are serialized and each gets its own result",function(transport,remote,reply)
		local wireActive,peak,done = 0,0,0
		local results,errors = {},{}
		function remote:FireServer(message)
			wireActive += 1; peak = math.max(peak,wireActive)
			task.delay(0.01,function()
				wireActive -= 1; reply(message,true,message.command.index)
			end)
		end
		for index = 1,20 do
			task.spawn(function()
				local ok,value = pcall(transport.Command,transport,{action="list",index=index})
				if ok then results[index] = value else table.insert(errors,tostring(value)) end
				done += 1
			end)
		end
		local deadline = os.clock()+6
		while done<20 and os.clock()<deadline do task.wait(0.01) end
		assert(done==20 and #errors==0,table.concat(errors,"; "))
		assert(peak==1,"Overlapping wire requests")
		for index = 1,20 do assert(results[index]==index,"Reply correlation failed") end
		assert(#transport.queue==0 and next(transport.pending)==nil)
	end)
	test("busy and throttled rejections retry without duplicate execution",function(transport,remote,reply)
		local attempts,executed = 0,0
		function remote:FireServer(message)
			attempts += 1
			if attempts<=2 then reply(message,false,"Not executed",if attempts==1 then "busy" else "throttled")
			else executed += 1; reply(message,true,"run-id") end
		end
		assert(transport:Command({action="start"})=="run-id")
		assert(attempts==3 and executed==1)
	end)
	test("lost mutation reply is not replayed and the next command recovers",function(transport,remote,reply,policy)
		policy.CommandTimeout = 0.1
		local starts,late = 0,nil
		function remote:FireServer(message)
			if message.command.action=="start" then starts += 1; late = message
			else
				reply(late,true,"old-run")
				reply(message,true,"idle")
			end
		end
		local ok,err = pcall(transport.Command,transport,{action="start"})
		assert(not ok and tostring(err):find("did not reply",1,true))
		assert(starts==1 and #transport.queue==0 and next(transport.pending)==nil)
		assert(transport:Command({action="status"})=="idle")
	end)
	test("send failures and denied commands release the queue without retry",function(transport,remote,reply)
		local calls = 0
		function remote:FireServer(message)
			calls += 1
			if calls==1 then error("send failed") end
			if calls==2 then reply(message,false,"Access denied") else reply(message,true,"ok") end
		end
		assert(not pcall(transport.Command,transport,{action="start"}))
		assert(next(transport.pending)==nil and #transport.queue==0)
		assert(not pcall(transport.Command,transport,{action="start"}))
		assert(calls==2)
		assert(transport:Command({action="list"})=="ok")
	end)
	test("busy retries have a deadline and do not strand later commands",function(transport,remote,reply,policy)
		policy.CommandTimeout = 0.1
		function remote:FireServer(message) reply(message,false,"Busy","busy") end
		assert(not pcall(transport.Command,transport,{action="list"}))
		assert(next(transport.pending)==nil and #transport.queue==0)
		function remote:FireServer(message) reply(message,true,"recovered") end
		assert(transport:Command({action="list"})=="recovered")
	end)
	return {passed=#passed,tests=passed}
end

return Tests
