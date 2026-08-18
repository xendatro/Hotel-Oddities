export type Entry = {
	Id: string,
	Name: string,
	Description: string,
	CoinPrice: number,
	RobuxPrice: number,
	Product: string,
	RequiresVoice: boolean?,
	Yaw: number?,
	Pitch: number?,
	Zoom: number?,
}

local Entries: { Entry } = {
	{
		Id = "Ball",
		Name = "Ball",
		Description = "Throw it to stun an enemy long enough to make your escape.",
		CoinPrice = 15,
		RobuxPrice = 5,
		Product = "Ball",
	},
	{
		Id = "Bandage",
		Name = "Bandage",
		Description = "Patch up a small amount of damage when the hotel gets its claws into you.",
		CoinPrice = 20,
		RobuxPrice = 5,
		Product = "Bandage",
	},
	{
		Id = "Energy Drink",
		Name = "Energy Drink",
		Description = "A short, violent burst of speed for emergencies that are already too close.",
		CoinPrice = 45,
		RobuxPrice = 9,
		Product = "EnergyDrink",
	},
	{
		Id = "Flashlight",
		Name = "Flashlight",
		Description = "Carry a dependable light when the hotel decides the ceiling lights are optional.",
		CoinPrice = 35,
		RobuxPrice = 7,
		Product = "Flashlight",
		Yaw = -25,
	},
	{
		Id = "Medkit",
		Name = "Medkit",
		Description = "Recover from serious injuries without waiting for the hotel to finish the job.",
		CoinPrice = 65,
		RobuxPrice = 12,
		Product = "Medkit",
		-- The white cross is on the +X face; the default angle shows the case's back corner.
		Yaw = -70,
	},
	{
		Id = "Pathfinder",
		Name = "Pathfinder",
		Description = "Place up to 20 glowing markers so the halls cannot turn you around twice.",
		CoinPrice = 90,
		RobuxPrice = 15,
		Product = "Pathfinder",
		-- Chevron display faces +Z, opposite the default camera; swing round to show it.
		Yaw = 160,
	},
	{
		Id = "Shovel",
		Name = "Shovel",
		Description = "Dig through suitable floors and open a way beneath the hotel.",
		CoinPrice = 55,
		RobuxPrice = 10,
		Product = "Shovel",
		Pitch = 8,
		Zoom = 1.15,
	},
	{
		Id = "Soda",
		Name = "Soda",
		Description = "Drink for a steady speed boost when a brisk walk is no longer enough.",
		CoinPrice = 30,
		RobuxPrice = 7,
		Product = "Soda",
	},
	{
		Id = "SpellBook",
		Name = "Spell Book",
		Description = "Read the forbidden passage to disappear from an enemy's attention for a moment.",
		CoinPrice = 120,
		RobuxPrice = 20,
		Product = "SpellBook",
		-- The cover faces ±X; the default angle shows only the page edge.
		Yaw = -70,
	},
	{
		Id = "Trap",
		Name = "Trap",
		Description = "Set a steel trap that snaps shut and holds an enemy in place.",
		CoinPrice = 75,
		RobuxPrice = 12,
		Product = "Trap",
		Pitch = 12,
	},
	{
		Id = "Visor",
		Name = "Visor",
		Description = "Wear it to shield your eyes from things that punish a direct look.",
		CoinPrice = 110,
		RobuxPrice = 18,
		Product = "Visor",
	},
	{
		Id = "Walkie Talkie",
		Name = "Walkie Talkie",
		Description = "Route your voice through a rough radio signal. Friends-only mode uses the same filter in both directions.",
		CoinPrice = 100,
		RobuxPrice = 18,
		Product = "WalkieTalkie",
		RequiresVoice = true,
	},
}

local EntriesById: { [string]: Entry } = {}
for _, entry in Entries do
	EntriesById[entry.Id] = entry
end

return {
	StartingCoins = 100,
	RobuxIcon = utf8.char(0xE002),
	Entries = Entries,
	EntriesById = EntriesById,

	Viewport = {
		FieldOfView = 40,
		Padding = 1.55,
		Yaw = 20,
		Pitch = 5,
		Zoom = 1,
	},

	Animation = {
		Card = {
			HoverScale = 1.08,
			HoverLift = 0.04,
			HoverTilt = 2.5,
			PressScale = 0.94,
			SelectedScale = 1.04,
			SelectedLift = 0.02,
			SelectedTilt = -1.5,
			HoverTime = 0.16,
			PressTime = 0.07,
			SettleTime = 0.24,
			Stagger = 0.035,
			EnterScale = 0.82,
			EnterDrop = 0.05,
		},
		Button = {
			HoverScale = 1.08,
			PressScale = 0.92,
			HoverTilt = -1.5,
			HoverTime = 0.14,
			PressTime = 0.06,
			SettleTime = 0.2,
		},
		Info = {
			FadeTime = 0.2,
			Rise = 0.02,
		},
	},
}
