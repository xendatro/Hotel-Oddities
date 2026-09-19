local Root = script.Parent.Parent
local Statistics = require(Root.Core.Statistics)
local Scope = require(Root.Core.Scope)
local Context = require(Root.Core.Context)
local Options = require(Root.Core.Options)
local Compare = require(Root.Core.Compare)
local Report = require(Root.Core.Report)
local Core = {}

function Core.Run()
	local passed = {}
	local function test(name,callback)
		callback(); table.insert(passed,name)
	end
	test("percentiles, truncation and non-finite samples",function()
		local s = Statistics.New(100)
		for i = 1,100 do Statistics.Add(s,i,16) end
		Statistics.Add(s,0/0); Statistics.Add(s,math.huge)
		local r = Statistics.Summary(s)
		assert(r.count == 100 and r.p50 == 50 and r.p95 == 95 and r.p99 == 99 and r.mean == 50.5)
		assert(s.over50 == 50 and s.over100 == 0 and s.overBudget == 84)
		Statistics.Add(s,101); assert(Statistics.Summary(s).truncated)
	end)
	test("wall scopes preserve method arguments, nil returns and errors",function()
		local run = Scope.Start({"test."})
		local object = { value = 9 }
		object.method = Scope.Wrap("test.method",function(self,a) return self.value+a,nil,3 end)
		local result = table.pack(object:method(2))
		assert(result.n == 3 and result[1] == 11 and result[2] == nil and result[3] == 3)
		local broken = Scope.Wrap("test.error",function() error("sentinel") end)
		assert(not pcall(broken))
		local token = Scope.Begin("test.once"); Scope.End(token); Scope.End(token)
		assert(Scope.Begin("excluded") == nil)
		local report = Scope.Stop(run)
		local found = {}
		for _, entry in report.scopes do found[entry.name] = entry end
		assert(found["test.error"].errors == 1 and found["test.once"].count == 1)
		assert(Scope.Begin("test.inactive") == nil)
	end)
	test("yielding scope counts elapsed time",function()
		local run = Scope.Start()
		Scope.Wrap("fast",function() return 1 end)()
		Scope.Wrap("wait",function() task.wait(0.025) end)()
		local rows = Scope.Stop(run).scopes
		assert(rows[1].name == "wait" and rows[1].mean >= 20 and rows[1].mean > rows[2].mean+15)
	end)
	test("cleanup unwinds once in reverse even after an error",function()
		local context = Context.new(nil,{})
		local order = {}
		context:Defer(function() table.insert(order,1) end)
		context:Defer(function() error("expected") end)
		context:Defer(function() table.insert(order,3) end)
		assert(#context:Cleanup() == 1 and order[1] == 3 and order[2] == 1)
		assert(#context:Cleanup() == 0)
	end)
	test("options reject NaN, oversized runs and invalid focus",function()
		for _, options in { {duration=0/0},{duration=10000},{repeats=1.5},{focus="invalid"},{scopes={12}} } do
			assert(not pcall(Options.Parse,options,{}))
		end
	end)
	local function fixture(id,fps)
		local report = { schema = 1,id = id,valid = true,status = "completed",scenario = { id = "test",version = 1,controlled = true },
			options = { duration = 20,warmup = 5,focus = "all",seed = 1,frameBudgetMs = 16.67,scopes = {},mode = "score" },trials = {} }
		for _ = 1,5 do
			table.insert(report.trials,{ client = { environment = { graphics="QualityLevel5",sceneSignature="fixed" },
				phases = {{ cadence = { count=1200,mean=1000/fps,p95=22 },metrics = { memoryMb={max=500} } }} },
				server = { phases = {{ metrics = { heartbeatWorkMs={mean=3} } }} } })
		end
		return report
	end
	test("comparison passes real gains and rejects faster broken workloads",function()
		local a,b = fixture("a",50),fixture("b",60)
		assert(Compare.Run(a,b,15).verdict == "pass")
		b.lifecycle = {id="changed",version=1}; assert(Compare.Run(a,b,15).verdict=="invalid")
		b.lifecycle = nil
		b.valid = false; assert(Compare.Run(a,b,15).verdict == "invalid")
	end)
	test("comparison rejects mismatches, regressions and insufficient repeats",function()
		local a,b = fixture("a",50),fixture("b",60)
		b.trials[1].client.environment.sceneSignature = "different"
		assert(Compare.Run(a,b).verdict == "invalid")
		b = fixture("b",60)
		for _, t in b.trials do t.client.phases[1].metrics.memoryMb.max = 600 end
		assert(Compare.Run(a,b).verdict == "fail")
		b = fixture("b",60); table.remove(b.trials)
		assert(Compare.Run(a,b).verdict == "inconclusive")
		b = fixture("b",50)
		assert(Compare.Run(a,b).verdict == "fail")
	end)
	test("compact baselines retain comparison evidence without mutating raw data",function()
		local a,b = fixture("a",50),fixture("b",60)
		b.trials[1].client.phases[1].frameSamplesMs = {12,14,16}
		local decoded = game:GetService("HttpService"):JSONDecode(Report.Json(b,true))
		assert(decoded.trials[1].client.phases[1].frameSamplesMs == nil)
		assert(#b.trials[1].client.phases[1].frameSamplesMs == 3)
		assert(Compare.Run(a,decoded,15).verdict == "pass")
	end)
	return { passed = #passed,tests = passed }
end

return Core
