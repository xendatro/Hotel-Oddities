local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local TagService = require(ReplicatedStorage.Services.TagService)

local RecordPlayerService = {}

local RECORD_TAG = "RecordPlayer"
local RECORD_SOUND = "Record"
local RECORD_BUS = "SFX"

TagService:Listen(RECORD_TAG, function(model: Model): AudioPlayer
	return AudioService:Play3DSound(RECORD_SOUND, model.Cube, true, RECORD_BUS)
end, function(_, player: AudioPlayer)
	AudioService:StopSound(player)
end, workspace)

return RecordPlayerService
