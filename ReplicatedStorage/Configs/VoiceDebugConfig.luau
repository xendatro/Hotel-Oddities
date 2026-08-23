local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VoiceChatConfig = require(ReplicatedStorage.Configs.VoiceChatConfig)
local WalkieTalkieConfig = require(ReplicatedStorage.Configs.WalkieTalkieConfig)

export type Entry = {
	Id: string,
	Label: string,
	Table: { [string]: any },
	Key: string,
	Maximum: number,
}

return {
	ToggleKey = Enum.KeyCode.F6,
	Step = 0.01,

	--- Each entry points at the live volume field it edits.
	Entries = {
		{
			Id = "ProximityVoice",
			Label = "Proximity Voice",
			Table = VoiceChatConfig,
			Key = "Volume",
			Maximum = 5,
		},
		{
			Id = "RadioVoice",
			Label = "Radio Voice",
			Table = WalkieTalkieConfig,
			Key = "VoiceVolume",
			Maximum = 2,
		},
		{
			Id = "RadioTaggedSound",
			Label = "Radio Tagged Sound",
			Table = WalkieTalkieConfig,
			Key = "TaggedSoundVolume",
			Maximum = 1,
		},
		{
			Id = "RadioSpeaker",
			Label = "Radio Speaker",
			Table = WalkieTalkieConfig,
			Key = "RadioPhysicalVolume",
			Maximum = 2,
		},
		{
			Id = "RadioActiveStatic",
			Label = "Radio Active Static",
			Table = WalkieTalkieConfig.Effects.Static,
			Key = "ActiveVolume",
			Maximum = 2,
		},
		{
			Id = "RadioDeathStatic",
			Label = "Radio Death Static",
			Table = WalkieTalkieConfig.Effects.Static,
			Key = "DeathVolume",
			Maximum = 2,
		},
	} :: { Entry },
}
