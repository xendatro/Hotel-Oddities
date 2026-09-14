local services = game.ServerStorage.Services

require(services.POIDiscoveryService)

for _, service in services:GetChildren() do
	if service == services.POIDiscoveryService then continue end
	task.defer(function()
		require(service)
	end)
end

require(game.ServerStorage.Modules.Tagger)()
