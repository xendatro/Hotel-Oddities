local Root = script.Parent.Parent
local Report = require(Root.Core.Report)
local Deltas = require(Root.Core.MetricDeltas)
local HttpService = game:GetService("HttpService")
local Tests = {}

function Tests.Run()
	local phase = {phase="route",duration=5,cadence={fps=60,count=300,p50=16,p95=20,p99=24,over50=1,overBudget=20},
		metrics={renderGpuMs={count=10,mean=4,max=8},memoryMb={count=10,mean=500,max=520}},
		memoryDeltaMb=1,memorySlopeMbPerMinute=12,churn={added=2,removed=1},unavailable={probe="denied"},collectorMs=1,
		focusAtStart="unknown",scopes={scopes={},counters={}}}
	local data = {environment={graphics="QualityLevel5"},phases={phase},checks={{name="route reached",passed=true,detail="finish"}},events={}}
	local report = {schema=1,id="fixture",status="completed",valid=false,scenario={id="route",version=1,controlled=true,description="Test route"},
		options={build="before",device="test",mode="score",focus="all",duration=5,warmup=1,repeats=5},trials={},warnings={"test warning","test warning"}}
	for _=1,5 do table.insert(report.trials,{status="completed",client=data,server=data}) end
	report = HttpService:JSONDecode(HttpService:JSONEncode(report))
	report.trials[5].client.phases[1].cadence.p95=200
	report.trials[3].client.checks={{name="route missing",passed=false,detail="sentinel failure"}}
	report.trials[4].server.phases[1].uiVisible=true
	local original = HttpService:JSONEncode(report)
	local summary = Report.Format(report)
	assert(summary:find("sentinel failure",1,true) and summary:find("5:60.00/200.00",1,true),"Failure or tail outlier omitted")
	assert(summary:find("profiler panel open",1,true) and summary:find("unavailable probe: denied",1,true),"Validity/availability omitted")
	local _,warnings = summary:gsub("test warning","")
	assert(warnings==1,"Warnings not deduplicated")
	assert(#summary<#Report.Detailed(report)*0.6,"Repeated report did not shrink")
	assert(original==HttpService:JSONEncode(report),"Formatter mutated evidence")
	local candidate = HttpService:JSONDecode(original)
	for _,trial in candidate.trials do trial.client.phases[1].metrics.renderGpuMs.mean=3 end
	local deltas = Deltas.Build(report,candidate)
	local gpu
	for _,row in deltas.rows do if row.metric=="client/route/renderGpuMs.mean" then gpu=row end end
	assert(gpu and gpu.before==4 and gpu.after==3 and gpu.percent==-25,"Delta direction or weight wrong")
	for _,trial in report.trials do trial.client.phases[1].metrics.renderGpuMs.mean=0 end
	for _,row in Deltas.Build(report,candidate).rows do
		if row.metric=="client/route/renderGpuMs.mean" then assert(row.percent==nil and row.delta==3,"Zero baseline treated as a percentage") end
	end
	return {passed=7,tests={"failure/outlier retained","validity/availability retained","warnings deduplicated","summary size reduced","evidence unchanged","metric deltas","zero baseline"}}
end

return Tests
