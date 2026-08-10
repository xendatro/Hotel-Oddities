--- Every developer product in the game. A product at 0 has not been created on the site yet;
--- the services behind them refuse to prompt or register a receipt until it has a real id.
return {
	--- Bought by the dead player themselves, out of `ServerStorage.Services.ReviveService`.
	Revive = 3638588110,
	--- Bought by a living friend on the dead player's behalf, out of
	--- `ServerStorage.Services.FriendReviveService`.
	ReviveFriend = 0,
}
