--- Every developer product in the game. A product at 0 has not been created on the site yet;
--- the services behind them refuse to prompt or register a receipt until it has a real id.
return {
	--- Bought by the dead player themselves, out of `ServerStorage.Services.ReviveService`.
	Revive = 3638588110,
	--- Bought by a living friend on the dead player's behalf, out of
	--- `ServerStorage.Services.FriendReviveService`.
	ReviveFriend = 0,

	--- One consumable developer product per item. Zero is a safe placeholder: the shop shows its
	--- configured preview price but refuses to prompt until the real product exists.
	Items = {
		Ball = 0,
		Bandage = 0,
		EnergyDrink = 0,
		Flashlight = 0,
		Medkit = 0,
		Pathfinder = 0,
		Shovel = 0,
		Soda = 0,
		SpellBook = 0,
		Trap = 0,
		Visor = 0,
	},
}
