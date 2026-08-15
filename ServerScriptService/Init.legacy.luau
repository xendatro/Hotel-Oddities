for _, service in game.ServerStorage.Services:GetChildren() do
	task.defer(function()
		require(service)
	end)
end

require(game.ServerStorage.Modules.Tagger)()

