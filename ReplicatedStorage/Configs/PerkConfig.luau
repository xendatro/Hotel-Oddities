return {
	AttributePrefix = "Perk_",

	--- Read by `LoadoutService`, which both the keep-items pass and either revive restore through.
	Loadout = {
		Attributes = { "uses" },
	},

	Visor = {
		--- The tool granted on every spawn. Must name a Tool in `ReplicatedStorage.Tools`.
		ToolName = "Visor",
	},

	DoubleSpeed = {
		Multiplier = 2,
	},

	FriendRevive = {
		--- Seconds the card stays up after a friend dies, and what the draining bar measures.
		Window = 15,

		PurchaseGrace = 120,

		MaxCards = 3,

		--- Seconds a card takes to slide in and to fade back out.
		OpenTime = 0.25,
		CloseTime = 0.2,
	},
}
