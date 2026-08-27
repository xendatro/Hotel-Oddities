export type Kit = {
	Id: string,
	Name: string,
	Rarity: string,
	Description: string,
	Stats: { [string]: number },
	Items: { [string]: number },
	Showcase: string?,
}

local DefaultKit = "Guest"

local Entries: { Kit } = {
	{
		Id = "Guest",
		Name = "Guest",
		Rarity = "Common",
		Description = "The standard issue nothing. You checked in with what you were wearing.",
		Stats = {},
		Items = {},
	},
	{
		Id = "Handyman",
		Name = "Handyman",
		Rarity = "Common",
		Description = "You brought a shovel and a bad feeling about the basement.",
		Stats = {},
		Items = {
			Shovel = 1,
			Bandage = 2,
		},
		Showcase = "Shovel",
	},
	{
		Id = "Nightlight",
		Name = "Nightlight",
		Rarity = "Common",
		Description = "Some prefer not to be found. You brought a light anyway.",
		Stats = {
			DetectionRadius = 0.9,
		},
		Items = {
			Flashlight = 1,
		},
		Showcase = "Flashlight",
	},
	{
		Id = "Sprinter",
		Name = "Sprinter",
		Rarity = "Common",
		Description = "You checked in already halfway to the exit.",
		Stats = {
			WalkSpeed = 18,
			Stamina = 130,
		},
		Items = {},
	},
	{
		Id = "Medic",
		Name = "Medic",
		Rarity = "Uncommon",
		Description = "You read the pamphlet about incident response. Twice.",
		Stats = {
			MaxHealth = 110,
		},
		Items = {
			Medkit = 1,
			Bandage = 3,
			Soda = 2,
		},
		Showcase = "Medkit",
	},
	{
		Id = "Scout",
		Name = "Scout",
		Rarity = "Uncommon",
		Description = "Fast enough to see the thing before it sees you.",
		Stats = {
			WalkSpeed = 19,
			Stamina = 140,
			DetectionRadius = 0.95,
		},
		Items = {
			Flashlight = 1,
		},
		Showcase = "Flashlight",
	},
	{
		Id = "Trapper",
		Name = "Trapper",
		Rarity = "Uncommon",
		Description = "You like your monsters predictable and your floors booby-trapped.",
		Stats = {},
		Items = {
			Trap = 2,
			Shovel = 1,
		},
		Showcase = "Trap",
	},
	{
		Id = "GlassGuest",
		Name = "Glass Guest",
		Rarity = "Uncommon",
		Description = "Fragile and fast. The math still works out in your favor. Usually.",
		Stats = {
			MaxHealth = 70,
			WalkSpeed = 22,
		},
		Items = {
			["Energy Drink"] = 1,
		},
		Showcase = "Energy Drink",
	},
	{
		Id = "Ghost",
		Name = "Ghost",
		Rarity = "Rare",
		Description = "You move like something that isn't sure it wants to be seen.",
		Stats = {
			DetectionRadius = 0.6,
			WalkSpeed = 13,
		},
		Items = {
			Visor = 1,
			Pathfinder = 1,
		},
		Showcase = "Visor",
	},
	{
		Id = "Warden",
		Name = "Warden",
		Rarity = "Rare",
		Description = "Slow, heavy, and built to still be standing when the lights come back on.",
		Stats = {
			MaxHealth = 220,
			WalkSpeed = 12,
		},
		Items = {
			Bandage = 2,
			Shovel = 1,
			Medkit = 1,
		},
		Showcase = "Shovel",
	},
	{
		Id = "Sapper",
		Name = "Sapper",
		Rarity = "Rare",
		Description = "A trap for every doorway and a soda for the wait.",
		Stats = {},
		Items = {
			Trap = 3,
			Ball = 2,
			Soda = 2,
		},
		Showcase = "Trap",
	},
	{
		Id = "Runner",
		Name = "Runner",
		Rarity = "Rare",
		Description = "Outrunning your own detection radius has consequences.",
		Stats = {
			WalkSpeed = 22,
			SprintMultiplier = 1.7,
			DetectionRadius = 1.1,
		},
		Items = {
			["Energy Drink"] = 1,
		},
		Showcase = "Energy Drink",
	},
	{
		Id = "Adrenaline",
		Name = "Adrenaline",
		Rarity = "Epic",
		Description = "Everything hurts a little less when you're already running.",
		Stats = {
			MaxHealth = 80,
			WalkSpeed = 20,
			Stamina = 160,
			SprintMultiplier = 1.65,
			DetectionRadius = 0.85,
		},
		Items = {
			Medkit = 1,
			Trap = 2,
		},
		Showcase = "Trap",
	},
	{
		Id = "Bunker",
		Name = "Bunker",
		Rarity = "Epic",
		Description = "You are not planning to move. You are planning to endure.",
		Stats = {
			MaxHealth = 240,
		},
		Items = {
			Bandage = 3,
			Medkit = 1,
			Shovel = 1,
		},
		Showcase = "Medkit",
	},
	{
		Id = "Phantom",
		Name = "Phantom",
		Rarity = "Epic",
		Description = "Barely a signature. Barely a heartbeat. Barely here.",
		Stats = {
			DetectionRadius = 0.55,
		},
		Items = {
			Visor = 1,
			Flashlight = 1,
			Pathfinder = 1,
		},
		Showcase = "Visor",
	},
	{
		Id = "Quartermaster",
		Name = "Quartermaster",
		Rarity = "Epic",
		Description = "You brought half the storage closet and left none for housekeeping.",
		Stats = {},
		Items = {
			Trap = 2,
			Shovel = 1,
			SpellBook = 1,
			Soda = 2,
			Bandage = 2,
			Ball = 2,
		},
		Showcase = "SpellBook",
	},
	{
		Id = "Vanguard",
		Name = "Vanguard",
		Rarity = "Legendary",
		Description = "Built to take the hit, then take the stairs two at a time.",
		Stats = {
			MaxHealth = 200,
			WalkSpeed = 20,
			JumpPower = 70,
		},
		Items = {
			Medkit = 1,
			Bandage = 2,
			Trap = 1,
		},
		Showcase = "Trap",
	},
	{
		Id = "Wraith",
		Name = "Wraith",
		Rarity = "Legendary",
		Description = "The hotel keeps records. Not of you.",
		Stats = {
			DetectionRadius = 0.55,
		},
		Items = {
			SpellBook = 1,
			Pathfinder = 1,
			Trap = 2,
			Flashlight = 1,
		},
		Showcase = "SpellBook",
	},
	{
		Id = "Berserker",
		Name = "Berserker",
		Rarity = "Legendary",
		Description = "One hit is all it takes, but you'll be three rooms away by then.",
		Stats = {
			MaxHealth = 50,
			WalkSpeed = 24,
			JumpPower = 80,
			Stamina = 150,
			SprintMultiplier = 1.8,
		},
		Items = {
			Trap = 2,
			["Energy Drink"] = 2,
			Shovel = 1,
		},
		Showcase = "Trap",
	},
	{
		Id = "Concierge",
		Name = "Concierge",
		Rarity = "Legendary",
		Description = "Room service for people who don't plan on dying tonight.",
		Stats = {
			DetectionRadius = 0.85,
		},
		Items = {
			Medkit = 2,
			Bandage = 3,
			Soda = 2,
			Ball = 3,
			Flashlight = 2,
			Pathfinder = 1,
			Trap = 1,
			Shovel = 1,
		},
		Showcase = "Medkit",
	},
	{
		Id = "Apex",
		Name = "Apex",
		Rarity = "Mythic",
		Description = "Every advantage the hotel offers, stacked until the odds finally bend.",
		Stats = {
			MaxHealth = 160,
			WalkSpeed = 22,
			JumpPower = 70,
			DetectionRadius = 0.75,
		},
		Items = {
			Medkit = 1,
			Trap = 2,
			Pathfinder = 1,
			["Energy Drink"] = 2,
		},
		Showcase = "Trap",
	},
	{
		Id = "Revenant",
		Name = "Revenant",
		Rarity = "Mythic",
		Description = "It sees you leave before it registers you were ever there.",
		Stats = {
			MaxHealth = 60,
			WalkSpeed = 25,
			Stamina = 180,
			SprintMultiplier = 1.85,
			DetectionRadius = 0.6,
		},
		Items = {
			Trap = 2,
			["Energy Drink"] = 1,
			Pathfinder = 1,
			Shovel = 1,
		},
		Showcase = "Trap",
	},
	{
		Id = "Colossus",
		Name = "Colossus",
		Rarity = "Mythic",
		Description = "It does not run. It does not need to.",
		Stats = {
			MaxHealth = 260,
			WalkSpeed = 10,
			JumpPower = 30,
		},
		Items = {
			Medkit = 3,
			Trap = 4,
			Bandage = 5,
			Shovel = 2,
			Soda = 3,
			Ball = 2,
		},
		Showcase = "Shovel",
	},
	{
		Id = "Archivist",
		Name = "Archivist",
		Rarity = "Mythic",
		Description = "A ledger of every close call, cross-referenced and reloaded.",
		Stats = {
			DetectionRadius = 0.9,
		},
		Items = {
			Trap = 3,
			Medkit = 2,
			Pathfinder = 2,
			["Energy Drink"] = 3,
			Flashlight = 2,
			Soda = 2,
			Ball = 2,
		},
		Showcase = "Pathfinder",
	},
}

local EntriesById: { [string]: Kit } = {}
for _, kit in Entries do
	EntriesById[kit.Id] = kit
end

return {
	Entries = Entries,
	EntriesById = EntriesById,
	DefaultKit = DefaultKit,
}
