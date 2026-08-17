--- Shared terms for the enemies that must stop the instant they are looked at, and for the client
--- side prediction that makes "the instant" true rather than "one round trip later".
---
--- The server remains the authority on whether such an enemy is frozen. All the client does is act
--- on its own eyes a round trip early and carry the resulting discrepancy until it can be put back
--- without anybody watching -- so every number here is either a name both sides have to agree on or
--- a bound on how far that discrepancy is allowed to go.

local ObservedFreezeConfig = {}

--- Carried by an enemy that holds still while it is seen. The client only predicts for these: for
--- everything else being looked at changes nothing about where it is drawn, so there is nothing to
--- get ahead of.
ObservedFreezeConfig.Tag = "FreezeWhenObserved"

--- Written on the model by the server whenever its answer changes. This is the confirmation the
--- prediction is waiting for -- until it arrives the client is guessing, and the moment it does the
--- discrepancy stops growing, because a frozen enemy is one the server has stopped moving too.
ObservedFreezeConfig.FrozenAttribute = "Frozen"

--- Studs of discrepancy past which the client gives up and snaps to the truth, on screen or not.
---
--- The prediction is a bridge to a confirmation, never a replacement for one, and this is what keeps
--- that honest. A report the server declines -- the player is dead, or out of `ObservationRange`, or
--- the model is not observable at all -- confirms nothing, and without a ceiling the client would go
--- on drawing a statue while the server walked the real thing into them. A visible pop is a bad
--- moment; being killed by something you were watching stand still is a broken game.
---
--- Set to a couple of hundred milliseconds of the fastest such enemy, which no honest connection
--- reaches: at a Weeping Angel's chase speed the discrepancy is under three studs at 100ms of ping,
--- so this only ever fires when the prediction was wrong rather than merely early.
ObservedFreezeConfig.MaxOffset = 6

--- Seconds an unconfirmed pin may hold before it is treated as one of those. Generous next to any
--- round trip, because the cost of being early here is a snap the player may see and the cost of
--- being late is nothing at all -- `MaxOffset` is the bound that matters, and this only catches the
--- case where the enemy was barely moving when the guess went in and so never trips it.
ObservedFreezeConfig.ConfirmationTimeout = 1

--- Fallback speed for the brief predicted release when replication has not shown enough movement to
--- estimate one. The Weeping Angel faces down its current path, so this remains useful from rest.
ObservedFreezeConfig.ReleaseSpeed = 26

--- Seconds between view reports the client will not send inside of. Sits just above the server's own
--- rate limit, so a report fired off the moment the player's eyes land on something is one the server
--- actually reads instead of one it drops for arriving too soon after the last.
ObservedFreezeConfig.MinReportGap = 0.03

return ObservedFreezeConfig
