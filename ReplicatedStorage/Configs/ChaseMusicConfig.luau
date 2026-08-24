return {
	FadeInSpeed = 3,
	FadeOutSpeed = 1.2,

	Enemies = {
		Chaser = {
			Template = "ChaserChase",
			Range = 70,
			FullVolumeDistance = 20,
			Volume = 0.6,
		},
		CeilingDweller = {
			Template = "CeilingDwellerChase",
			Range = 70,
			FullVolumeDistance = 20,
			Volume = 0.9,
		},
		Mimic = {
			{
				Template = "MimicChase",
				Range = 70,
				FullVolumeDistance = 20,
				Volume = 1.15,
			},
			{
				Template = "MimicChase2",
				Range = 70,
				FullVolumeDistance = 20,
				Volume = 0.45,
			},
		},
	},
}
