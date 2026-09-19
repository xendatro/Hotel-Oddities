task.defer(function()
	require(game:GetService("ReplicatedStorage").Profiler.Bootstrap).Start()
end)

for _, service in game:GetService("ReplicatedStorage").Services:GetChildren() do
	task.defer(function()
		require(service)
	end)
end

require(game:GetService("ReplicatedStorage").Modules.Tagger)()
