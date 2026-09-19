local Statistics = {}

function Statistics.Finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Percentiles use nearest rank on retained samples. Count/sum cover every sample;
-- truncated distributions are explicitly marked and must not qualify a benchmark.
function Statistics.New(limit)
	return { count = 0, sum = 0, sumSquares = 0, min = math.huge, max = -math.huge,
		values = {}, limit = limit or 100000, over50 = 0, over100 = 0, overBudget = 0 }
end

function Statistics.Add(stream, value, budget)
	if not Statistics.Finite(value) then return end
	stream.count += 1
	stream.sum += value
	stream.sumSquares += value * value
	stream.min = math.min(stream.min, value)
	stream.max = math.max(stream.max, value)
	if value > 50 then stream.over50 += 1 end
	if value > 100 then stream.over100 += 1 end
	if budget and value > budget then stream.overBudget += 1 end
	if #stream.values < stream.limit then table.insert(stream.values, value) end
end

function Statistics.Summary(stream)
	if stream.count == 0 then return { count = 0, available = false } end
	local sorted = table.clone(stream.values)
	table.sort(sorted)
	local function percentile(q)
		return sorted[math.clamp(math.ceil(#sorted * q), 1, #sorted)]
	end
	local n = stream.count
	return {
		available = true, count = n, retained = #sorted, truncated = #sorted < n,
		mean = stream.sum / n, min = stream.min, max = stream.max,
		stddev = if n > 1 then math.sqrt(math.max(0, (stream.sumSquares - stream.sum^2 / n) / (n-1))) else 0,
		p50 = percentile(0.5), p95 = percentile(0.95), p99 = percentile(0.99),
	}
end

function Statistics.Slope(rows, field)
	local n, x, y, xx, xy = 0, 0, 0, 0, 0
	for _, row in rows do
		local value = row[field]
		if Statistics.Finite(value) then
			n += 1; x += row.t; y += value; xx += row.t^2; xy += row.t * value
		end
	end
	local denominator = n * xx - x^2
	return if n > 1 and denominator > 0 then (n * xy - x * y) / denominator else nil
end

return Statistics
