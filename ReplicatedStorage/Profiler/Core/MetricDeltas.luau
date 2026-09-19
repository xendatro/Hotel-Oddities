local MetricDeltas = {}
local function collect(report)
	local values = {}
	local function add(key,value)
		if type(value)~="number" or value~=value then return end
		local row = values[key] or {sum=0,count=0}
		row.sum += value; row.count += 1; values[key] = row
	end
	for _,trial in report.trials do
		for _,side in {"client","server"} do
			for _,phase in trial[side] and trial[side].phases or {} do
				local prefix = side .. "/" .. (phase.phase or "steady") .. "/"
				for _,name in {"fps","p95","p99"} do add(prefix .. name,(phase.cadence or {})[name]) end
				for name,value in phase.metrics do
					add(prefix .. name .. ".mean",value.mean)
					if name=="memoryMb" then add(prefix .. name .. ".peak",value.max) end
				end
			end
		end
	end
	return values
end
local function round(value) return math.round(value*1000)/1000 end
function MetricDeltas.Build(baseline,candidate)
	local a,b = collect(baseline),collect(candidate)
	local rows = {}
	for name,x in a do
		local y = b[name]
		if not y then continue end
		local before,after = x.sum/x.count,y.sum/y.count
		if before==after then continue end
		table.insert(rows,{metric=name,before=round(before),after=round(after),delta=round(after-before),
			percent=if before~=0 then round((after/before-1)*100) else nil})
	end
	table.sort(rows,function(x,y)
		local a,b = math.abs(x.percent or 0),math.abs(y.percent or 0)
		return if a==b then x.metric<y.metric else a>b
	end)
	return {semantics="Equal-weight trial means per phase; p95/p99 are means of trial percentiles, not pooled. Positive percent means higher, not necessarily better.",rows=rows}
end
return MetricDeltas
