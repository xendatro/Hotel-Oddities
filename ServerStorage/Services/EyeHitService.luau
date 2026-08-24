local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local existing = CommunicationService.Find("Enemies", "EyeHit")
if existing and not existing:IsA("RemoteEvent") then
	existing:Destroy()
end

return { Remote = CommunicationService.Ensure("Enemies", "EyeHit") :: RemoteEvent }
