--- Every gamepass in the game, by the name the code refers to it by. A pass sitting at 0 has not been
--- created on the site yet: `MarketplaceService:UserOwnsGamePass` answers false for those without
--- asking Roblox, so shipping one early gates nothing and costs nothing.
---
--- What each pass actually does lives in `ServerStorage.Services.PerkService`, tuned by
--- `ReplicatedStorage.Configs.PerkConfig`.
return {
	--- Pathfinder markers stop spending charges and recycle at the cap instead.
	Pathfinder = 0,
	--- Your inventory survives a death and comes back with you.
	KeepItems = 0,
	--- A Visor in your bag on every spawn, for free.
	Visor = 0,
	--- Walk twice as fast, drinks included.
	DoubleSpeed = 0,
}
