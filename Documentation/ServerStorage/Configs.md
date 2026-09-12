# ServerStorage / Configs

Pure data tables, server only.

### BadgeConfigs.luau
Placeholder table for badge award settings; currently empty, so nothing is configured.
- API: data table — empty

### DevProductConfigs.luau
Placeholder table for developer product definitions; currently empty, so nothing is configured.
- API: data table — empty

### DiscoveryConfig.luau
Tuning for the discovery/journal progress system: how fast a player "discovers" an enemy by looking at it, standing near it, witnessing an event, or dying to it. Includes a resolver that merges a per-enemy rule with the defaults.
- API: data table — `SweepInterval`, `ReplicateStep`, `Defaults` (`Sight`, `Death`), `Rules` (per-enemy `Sight`/`Proximity`/`Event`/`Death`; `Sight = false` disables sight gain — `MirrorStalker` uses it because its real body is invisible; `PaintingDweller` is event/death only since its rig never registers with `EnemyService`), plus `DiscoveryConfig.Resolve(enemyId: string) -> { Sight, Proximity, Event, Death }`
- Requires: `ReplicatedStorage.Configs.CreepConfig` (Creep proximity range)

### EnemyConfigs.luau
Master per-enemy stat table driving enemy models, movement, senses, damage and spawn budgeting; every enemy class and service reads its numbers from here. `CeilingDweller` is not written literally — it is a runtime clone of `Chaser` with a different model, animations, agent radius and observation settings.
- API: data table — one entry per enemy id (`Chaser`, `Blind`, `WeepingAngel`, `Mimic`, `Stalker`, `MirrorStalker`, `Ghost`, `Creep`, `Eye`, `Chaos`, `Sisters`, plus cloned `CeilingDweller`), each drawing from key groups: identity (`Model`, `Animations`, `Variants`, `Harmless`), locomotion/pathing (`WalkSpeed`, `ChaseSpeed`, `RunSpeed`, `FleeSpeed`, `Repath*`, `AgentParams` — the shared `Costs = { Room = 100000 }` must stay a finite number, because `math.huge` there makes `ComputeAsync` route straight into the safe rooms it is meant to keep enemies out of), idle/patrol (`IdleTime*`, `IdleNextState`, `WanderRadius`), senses (`DetectionRange`, `GiveUpRange`, `FieldOfView`, `Observation*`, `RespectsSafeRooms`, `AllowRoomReaction`), combat (`Damage`, `AttackRange`, `AttackCooldown`, `Hit/Center/EdgeDamage`, `KillRange`), and behavior-specific blocks (Blind's noise/determination and stopped-search timing, including `SearchTime`, Mimic's bystander + AFK set, Stalker's peek/stalk/flee set — `PeekFogFraction` caps the peek range to that fraction of the way from each player's fog start to fog end, `Follow*` time how quickly it teleports to the next corner once the player leaves its spot's sight, and `StalkChance` is the roll to walk up behind them once `PeekCountMin/Max` full peeks are done; while stalking it walks at the player's own measured ground speed (smoothed by `StalkPaceResponse`, never below `StalkMinSpeed`) plus up to `StalkCatchUpSpeed` extra, scaled by how far past `FollowSlack` it has fallen behind its follow point over `StalkCatchUpDistance`, and `KillDistance` is how close behind the victim it stands for the reveal, Ghost's drift/lurk set, Creep's light ranges, Chaos's warning/route timings — `SpawnDelay`/`WarningTime` are both 15s so everywhere Chaos will be within 15 seconds is already telegraphed, `WarnSpanPadding` is how far past each end of the stretch the route actually travels a warned hallway region is extended before it is clamped back to the real span, and `CrashOverrun` is how far past the end of the last straight run the crash point may sit when the raycast finds no wall, Sisters' formation and flicker values, MirrorStalker's encounter block — `Chance`, `Cooldown`, `RollCooldown`, `PollInterval`, `SpawnDelayMin/Max`, `MinGaitSpeed`, `FollowDistance`, `FollowSlack`, `SpawnDistance`, `EdgeInset`, `TurnRate`, `Check*` (the look-behind test and how long it must hold), `Reflection*` (the ceiling-reflection view test that must fail at the same time)), plus director hints (`DangerBias`, `MaxAlive`, `SpawnGrace`, `CommandSpawnDistance`, `CommandSpawnBehind`). `AllowRoomReaction = false` on `CeilingDweller` keeps it from approaching safe-room doors or playing the room reaction animation.
- Requires: `ReplicatedStorage.Configs.AnimationConfig`, `ReplicatedStorage.Configs.CreepConfig`

### GamepassConfigs.luau
Placeholder table for gamepass definitions; currently empty, so nothing is configured.
- API: data table — empty

Blind pre-listening braking uses `OvershootDuration = 1` second, alongside `OvershootRange` and `OvershootMinimum`. This bounds the shared investigation/pursuit coast without changing listening animation duration. `ListenFadeTime = 0.6` controls listening fade-in and its lead time before braking finishes; the shared search entry owns braking so blending starts after any approach movement. `ListenFadeOutTime = 0.6` controls the normal return to locomotion; urgent interruptions keep the default shorter fade.
