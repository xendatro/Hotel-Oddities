local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local OddityRemotes = {}

function OddityRemotes.Event(name: string): RemoteEvent
	return CommunicationService.Ensure("Oddities", name)
end

return OddityRemotes
