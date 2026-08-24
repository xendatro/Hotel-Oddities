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
	},

	Spawn = {
		TargetPercentage = 0.06,
		RefillDelay = 90,
		SurfacePadding = 0.05,
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
		["Player Locator"] = "VeryRare",
	},
}
