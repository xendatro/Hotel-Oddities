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
- API: data table — `SweepInterval`, `ReplicateStep`, `Defaults` (`Sight`, `Death`), `Rules` (per-enemy `Sight`/`Proximity`/`Event`/`Death`; `Sight = false` disables sight gain; `PaintingDweller` is event/death only since its rig never registers with `EnemyService`), plus `DiscoveryConfig.Resolve(enemyId: string) -> { Sight, Proximity, Event, Death }`
- Requires: `ReplicatedStorage.Configs.CreepConfig` (Creep proximity range)

### EnemyConfigs.luau
Master per-enemy stat table driving enemy models, movement, senses, damage and spawn budgeting; every enemy class and service reads its numbers from here. `CeilingDweller` is not written literally — it is a runtime clone of `Chaser` with a different model, animations, agent radius and observation settings.
- API: data table — one entry per enemy id (`Chaser`, `Blind`, `WeepingAngel`, `Mimic`, `Stalker`, `Ghost`, `Creep`, `Eye`, `Chaos`, `Sisters`, plus cloned `CeilingDweller`), each drawing from key groups: identity (`Model`, `Animations`, `Variants`, `Harmless`), locomotion/pathing (`WalkSpeed`, `ChaseSpeed`, `RunSpeed`, `FleeSpeed`, `Repath*`, `AgentParams`), idle/patrol (`IdleTime*`, `IdleNextState`, `WanderRadius`), senses (`DetectionRange`, `GiveUpRange`, `FieldOfView`, `Observation*`, `RespectsSafeRooms`), combat (`Damage`, `AttackRange`, `AttackCooldown`, `Hit/Center/EdgeDamage`, `KillRange`), and behavior-specific blocks (Blind's noise/determination set, Mimic's bystander + AFK set, Stalker's peek/stalk/flee set, Ghost's drift/lurk set, Creep's light ranges, Chaos's warning/route timings, Sisters' formation and flicker values), plus director hints (`DangerBias`, `MaxAlive`, `SpawnGrace`, `CommandSpawnDistance`, `CommandSpawnBehind`)
- Requires: `ReplicatedStorage.Configs.AnimationConfig`, `ReplicatedStorage.Configs.CreepConfig`

### GamepassConfigs.luau
Placeholder table for gamepass definitions; currently empty, so nothing is configured.
- API: data table — empty
