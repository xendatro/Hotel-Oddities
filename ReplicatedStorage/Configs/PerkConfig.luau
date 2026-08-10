--- What the paid perks are worth, in one place. Shared rather than server-side because the friend
--- revive card counts its own bar down on the client, and both halves have to agree on how long the
--- offer lasts or the bar empties while the button still works.
---
--- Which pass or product each of these hangs off lives in
--- `ReplicatedStorage.Services.MarketplaceService.Gamepasses` and `.Products`.

return {
	--- `PerkService` publishes each resolved pass as an attribute of this name plus the pass's key in
	--- `MarketplaceService.Gamepasses` -- `Perk_Pathfinder`, and so on -- set on the Player itself.
	---
	--- Player attributes replicate on their own, which is the whole point: a client half of a tool can
	--- read what its owner has paid for as a local lookup instead of a remote round trip, and gets a
	--- change signal for free when a pass resolves late or is bought mid-round. Absent means no.
	AttributePrefix = "Perk_",

	--- Read by `LoadoutService`, which both the keep-items pass and either revive restore through.
	Loadout = {
		--- Attributes copied off a tool when a loadout is captured and written back when it is
		--- restored. Stack quantity is handled on its own -- these are the per-tool counters that are
		--- NOT stack size, and dropping them would hand back a full Pathfinder for the price of dying.
		Attributes = { "uses" },
	},

	Visor = {
		--- The tool granted on every spawn. Must name a Tool in `ReplicatedStorage.Tools`.
		ToolName = "Visor",
	},

	DoubleSpeed = {
		--- Multiplies the player's ordinary walk speed AND anything a drink boosts them to, so a Soda
		--- is still worth drinking with the pass on. Applied in `SpeedBoostService`, which is the only
		--- thing allowed to write a boosted `WalkSpeed`.
		Multiplier = 2,
	},

	FriendRevive = {
		--- Seconds the card stays up after a friend dies, and what the draining bar measures.
		Window = 15,

		--- Seconds a prompted purchase stays fulfillable after the card's own window has closed.
		--- Robux prompts are slow and a player may sit on one; the offer expiring underneath them
		--- would take their money and revive nobody.
		PurchaseGrace = 120,

		--- Cards shown at once. Past this the oldest is dropped rather than stacking a column of them
		--- up the side of the screen.
		MaxCards = 3,

		--- Seconds a card takes to slide in and to fade back out.
		OpenTime = 0.25,
		CloseTime = 0.2,
	},
}
