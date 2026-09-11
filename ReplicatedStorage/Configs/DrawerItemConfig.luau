local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)

local Input = table.clone(DrawerConfig.Input)
Input.TouchAction = "DrawerItemPickup"

local UI = table.clone(DrawerConfig.UI)
UI.Prompt = "PickupPrompt"
UI.TextWidth = 64
UI.PickupText = "Pick Up"

return {
	Tag = "DrawerItem",
	Attribute = "ToolName",

	Remotes = {
		Folder = "DrawerItem",
		Pickup = "Pickup",
		Result = "PickupResult",
	},

	Feedback = {
		Labels = {
			Coins = "Coins",
			Gems = "Gems",
		},
		Sounds = {
			Coins = "CoinPickup",
			Gems = "GemPickup",
		},
	},

	DisplayRotations = {
		Coin = CFrame.Angles(math.rad(90), 0, 0),
	},

	Spawn = {
		TargetPercentage = 0.06,
		CurrencyTargetPercentage = 0.2,
		RefillDelay = 90,
		SurfacePadding = 0.05,
	},

	Hallway = {
		InitialAlive = 8,
		MaxAlive = 8,
		RefillDelay = 45,
		MinimumSpacing = 24,
		MinimumPlayerDistance = 20,
		PlacementAttempts = 24,
		SupportSurfaceNames = {
			CarpetRunner = true,
		},
	},

	Targeting = DrawerConfig.Targeting,
	Input = Input,
	Highlight = DrawerConfig.Highlight,
	UI = UI,

	Rarities = {
		Common = 60,
		Uncommon = 25,
		Rare = 12,
		VeryRare = 3,
	},

	Items = {
		Food = "Common",
		Bandage = "Common",
		Soda = "Common",
		["Energy Drink"] = "Uncommon",
		Flashlight = "Uncommon",
		Medkit = "Rare",
		Lantern = "Rare",
		Radar = "VeryRare",
	},

	Currencies = {
		Coin = {
			Currency = "Coins",
			Amount = 10,
			Weight = 50,
		},
		Gem = {
			Currency = "Gems",
			Amount = 10,
			Weight = 50,
		},
	},
}
