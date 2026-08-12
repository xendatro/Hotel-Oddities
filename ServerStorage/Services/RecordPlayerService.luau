local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local TagService = require(ReplicatedStorage.Services.TagService)

--- @class RecordPlayerService
--- Keeps a record turning on every `RecordPlayer` prop, forever.
---
--- The track plays as a looping 3D sound on the prop's own `Cube`, which is what makes it worth
--- doing in the world rather than as a cue: acoustic simulation muffles it through the walls
--- between it and the player, so it reads as a room somewhere further along the corridor rather
--- than as something happening to them. The record itself is warped and detuned in Studio, on the
--- template's effect chain, not here.
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
