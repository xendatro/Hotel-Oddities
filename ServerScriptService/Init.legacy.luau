for _, service in game.ServerStorage.Services:GetChildren() do
	require(service)
end

require(game.ServerStorage.Modules.Tagger)()

