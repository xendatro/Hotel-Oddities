for _, service in game:GetService("ReplicatedStorage").Services:GetChildren() do
	require(service)
end

require(game:GetService("ReplicatedStorage").Modules.Tagger)()
