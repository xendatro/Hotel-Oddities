# ServerStorage / Classes

Roblox class-syntax classes, server only. Connections live in `self.Connections`, built by a local `setUpConnections`.

### EnemyBase.luau
Minimal base class for non-humanoid enemies (props, hazards, static horrors) that are driven by a StateMachine rather than pathfinding. It owns the active flag, the tag set applied to the model while alive, and a deferred despawn that can linger before destroying the model.
- API: `EnemyBase.extend(className: string) -> class` — makes a subclass table inheriting EnemyBase.
- API: `EnemyBase.new(model: Model, config: any, class: any?) -> self` — sets `Model`, `Config`, `Active = false`.
- API: `EnemyBase:Start()` — guards re-entry, adds `self.Tags` to the model, calls `OnStart`, starts `self.StateMachine`.
- API: `EnemyBase:Despawn()` — removes tags, calls `OnDespawn` for a linger time, then defers stopping the machine and `DestroyModels`.
- API: `EnemyBase:OnStart()` — hook, no-op by default.
- API: `EnemyBase:OnDespawn() -> number?` — hook returning seconds to linger before destruction; default `nil`.
- API: `EnemyBase:DestroyModels()` — destroys `self.Model`; override for multi-model enemies.
- Subclass: constructor must call `EnemyBase.new(model, config, TheClass)` and assign `self.StateMachine` (Start/Despawn call it unconditionally); optionally set `Class.Tags` and override `OnStart` / `OnDespawn` / `DestroyModels`. `EnemyService:Spawn` assigns `self.EnemyId` after construction and calls `:Start()`.
- Tags: applies `Enemy` (default `EnemyBase.Tags`)
- Requires: `ReplicatedStorage.Classes.StateMachine` (indirectly, via the subclass)

### NPC.luau
The full humanoid-enemy base: pathfinding with prefetch, direct-pursuit/lane-clearance movement, line-of-sight and observation checks, target acquisition, network-ownership management, and a library of shared state functions (Idle/Wander/Patrol/Attack/Stunned/RoomReaction/Despawn). Danger-weighted hallway-graph patrol and safe-room reactions live here too.
- API: `NPC.extend(className: string, parent: any?) -> class` — subclass table, optionally inheriting another NPC subclass.
- API: `NPC.new(model: Model, config: EnemyConfigs.EnemyConfig, class: any?) -> self` — needs `model.Humanoid` and `model.HumanoidRootPart`; builds `NpcAnimator` and calls `BuildStateMachine`.
- API: `NPC.FromModel(model: Instance?) -> any?` — reverse lookup for live NPCs (registered only while active).
- API: `NPC:BuildStateMachine() -> StateMachine` — default Idle/Wander/Patrol/Despawn machine; the main override point.
- Detection: `CanSee` and `IsValidTarget` scale `DetectionRange` and `GiveUpRange` by the target character's `DetectionRadius` attribute (`HumanoidStatsService.GetDetectionRadius`, 1 when absent), which is how a kit's stealth stat shortens the range at which enemies notice and keep chasing that player.
- API: `NPC:Start()` — tags the model, applies WalkSpeed, takes network ownership, starts animator and machine, mirrors state to the `State` attribute.
- API: `NPC:Despawn()` — untags, tears down ownership watchers, defers machine stop, animator destroy and model destroy.
- API: `NPC:SetSpeed(speed: number)` — sets `Humanoid.WalkSpeed`.
- API: `NPC:StopMoving()` — `MoveTo` its own position.
- API: `NPC:SetForcedDoorway(doorway: Model?)` — writes the `ForcedDoorway` attribute.
- API: `NPC:SetNetworkOwner(player: Player?)` — pins every descendant part's owner; refreshed on a loop.
- API: `NPC:FaceTowards(position: Vector3)` — instant flat snap of root CFrame.
- API: `NPC:TurnTowardsSmooth(position: Vector3, duration: number?)` — lerped turn over Heartbeat.
- API: `NPC:ReactAtRoomDoor(room: Model, movementSpeed: number?, shouldCancel: (() -> boolean)?) -> boolean` — walk to a safe-room door, turn, then play the animation set's `RoomReaction` override (the Chaser's door knock) or fall back to the cheer emote.
- API: `NPC:PrefetchPath(destination: Vector3, origin: Vector3?)` — starts an async path compute other calls can claim.
- API: `NPC:ComputePath(destination: Vector3, tolerance: number?) -> Path?` — consumes a matching prefetch or computes synchronously.
- API: `NPC:TakePrefetchedPath(destination: Vector3, tolerance: number?) -> Path?` — non-blocking claim of a finished prefetch.
- API: `NPC:GetMovementWaypoints(path: Path) -> { PathWaypoint }` — override point for waypoint filtering.
- API: `NPC:GetWaypointDistance(position: Vector3) -> number` — distance from root to a waypoint corrected for hip height.
- API: `NPC:GetClearRun(direction: Vector3, distance: number) -> number` — blockcast-measured free run in a direction.
- API: `NPC:HasMovementClearance(destination: Vector3) -> boolean` — agent-sized blockcast, ignoring players.
- API: `NPC:MoveTowards(destination: Vector3) -> boolean` — move as far as the lane allows; false when too obstructed.
- API: `NPC:MoveThrough(destination: Vector3, beyond: Vector3?)` — move to an overshot point so the NPC does not brake at waypoints.
- API: `NPC:AdvanceWaypoint(waypoints: { PathWaypoint }, index: number) -> number` — skips waypoints already effectively reached.
- API: `NPC:WalkPatrolEdge(destination: Vector3, lateralOffset: number?) -> boolean` — stepped `MoveTo` walk with per-step timeout.
- API: `NPC:WalkTo(destination: Vector3, shouldAbandon: (() -> boolean)?) -> boolean` — compute and walk one path.
- API: `NPC:Pursue(getGoal: () -> Vector3?, arriveDistance: number?, hasArrived: (() -> boolean)?, canMoveDirectly: (() -> boolean)?) -> string` — the main chase loop; returns `"Reached"` or `"Lost"`.
- API: `NPC:HasLineOfSight(part: BasePart) -> boolean` — single raycast ignoring both models.
- API: `NPC:HasLineOfSightToPlayer(player: Player) -> boolean` — alive + not vanished + clear ray.
- API: `NPC:HasPursuitSight(player: Player) -> boolean` — lenient multi-origin, multi-limb sight test used during chases.
- API: `NPC:GiveUpOn(player: Player?)` — blacklists a player as a target for 12s.
- API: `NPC:IsValidTarget(player: Player) -> boolean` — alive, not vanished, not safe-roomed, within `GiveUpRange`.
- API: `NPC:GetTargetPosition(player: Player) -> Vector3?` — root position if still a valid target.
- API: `NPC:IsTouchingPlayer(player: Player) -> boolean` — bounding-box overlap plus per-part check.
- API: `NPC:CanSee(player: Player) -> boolean` — detection range, field-of-view cone and line of sight.
- API: `NPC:IsObservedBy(player: Player) -> boolean` — that player's camera is looking at the model.
- API: `NPC:IsObserved() -> boolean` — any player, with `ObservationHold` grace.
- API: `NPC:CanAcquire() -> boolean` — honours the `AcquireAfter` cooldown.
- API: `NPC:GetNearestVisibleTarget() -> Player?` — nearest player passing `CanSee`.
- API: `NPC:GetNearestTarget() -> Player?` — nearest player passing `IsValidTarget`.
- API: `NPC:Attack(player: Player)` — routes the kill through `DeathService:Strike` with `self.EnemyId`.
- API: `NPC:BeginChase(target: Player)` — sets target, resumes animation, applies `ChaseSpeed`.
- API: `NPC:MakePerceptionEvaluator(interval: number, findTarget: (npc) -> Player?) -> () -> ()` — builds an evaluator loop that pushes into `Chase`.
- API: `NPC.SharedStates` — reusable state functions: `Attack`, `Idle`, `Wander`, `Patrol`, `Stunned`, `RoomReaction`, `Despawn`.
- Subclass: `Class = NPC.extend(name)`, `Class.new` calls `NPC.new(model, config, Class)`, and `Class:BuildStateMachine()` returns the state table/triggers/evaluators. Overriding `Start`/`Despawn` must call `NPC.Start(self)` / `NPC.Despawn(self)`. Config supplies WalkSpeed, ChaseSpeed, DetectionRange, FieldOfView, GiveUpRange, AgentParams, IdleTime*, IdleNextState, AttackCooldown, and optional ObservationRange/ObservationHold, RespectsSafeRooms, Repath*/Commit*/DirectPursuit* tuning. Optional hooks a subclass may define: `AttackLostState`, `StopMirroring`, `_laneProbeDrop`.
- Tags: applies `Enemy`; applies `Observable` when `Config.ObservationRange` is set
- Requires: `Classes.StateMachine`, `Classes.NpcAnimator`, `Classes.Race`, `Services.VanishedService`, `Configs.DangerConfig`, `DangerMapService`, `HallwayGraphService`, `RoomService`, `EnemyObservationService`, `DeathService`

### Healer.luau
Server tool that restores health on activation. Consumes one unit from the inventory, plays the configured sound at the character's primary part, then heals up to `MaxHealth`.
- API: `Healer.extend(className: string) -> class`
- API: `Healer.new(tool: Tool, class: any?) -> self`
- API: `Healer:OnActivated()` — the heal; overrides the ToolBase hook.
- Requires: `ServerStorage.Classes.ServerTool`; `ToolConfigs[toolName].HealAmount` / `.Sound`

### FixtureFall.luau
Prop oddity that unanchors a fixture so it falls: it welds every part to the largest one, moves them to a non-colliding group, and remembers original CFrames/collision groups so `OnStop` can restore them exactly. Also provides the shared "is it safe to fix yet" test used by repair interactions (ground timer, player distance, and nobody looking).
- API: `FixtureFall.new(config: { [string]: any }?, class: any?) -> self`
- API: `FixtureFall:OnStart() -> boolean` — drops the fixture; false if there are no parts or the model is already `OddityBusy`.
- API: `FixtureFall:OnStop()` — destroys welds, re-anchors and restores every part, clears `OddityBusy`.
- API: `FixtureFall:GroundedFor() -> number` — seconds since it fell.
- API: `FixtureFall.DescribeNotFixed(oddity, pivot: Vector3, gazeTarget, timerLabel: string, gazeIgnore: { Instance }?) -> string?` — reusable reason string, or nil when fixable.
- API: `FixtureFall:WhyNotFixed() -> string?` — the above applied to this model.
- API: `FixtureFall:IsReadyToFix() -> boolean`
- Requires: `ServerStorage.Classes.PropOddity`, `ServerStorage.Services.GazeService`; optional subclass hooks `OnFall`, `OnLoose`, `OnRestore`
- Notes: settings read via `Oddity:Setting` — `CollisionGroup`, `MinGroundTime`, `FixClearDistance`, `FixViewCone`, `FixViewDistance`

### FixturePool.luau
Class that keeps a rolling set of tagged hallway fixture models "armed" near living players, drops one as an oddity when a player walks back toward it after leaving the arm radius, and stops the oddity once it is ready to be fixed. Only runs its heartbeat loop if `OddityService:IsEnabled` for the class's scope; all distances and chances come from the owning class's `Settings`.
- API: `FixturePool.new(class: any, label: string)` — class supplies `Settings`, `Scope`, and optional `IsCandidate`
- API: `FixturePool:Setting(name: string, fallback: number) -> number`
- API: `FixturePool:Log(message: string)` — only when `Settings.DebugLog`
- API: `FixturePool:PointFor(model: Model) -> Vector3?` — cached hallway floor point
- API: `FixturePool:ArmDistance() -> number`
- API: `FixturePool:Drop(model: Model) -> boolean` — starts the oddity and tracks repair
- API: `FixturePool:GetArmed() -> { Model }`
- API: `FixturePool:GetFallen() -> { [Model]: any }`
- API: `FixturePool:Nearest(position: Vector3) -> (Model?, number)`
- Tags: reads `Settings.Tag` via `CollectionService:GetTagged`
- Requires: `ServerStorage.Services.OddityService`, `ReplicatedStorage.Services.HallwaysService`, `ReplicatedStorage.Services.VanishedService`

### CrossingPool.luau
The fixture-free twin of `FixturePool`: instead of arming tagged models it samples crossing points along every tagged maze-floor hallway, keeps a rolling set of them "armed" near living players, and starts the owning oddity when a player walks back toward one after leaving the arm radius. Triggered points go on a per-site cooldown so the same spot is not reused straight away. Only runs its heartbeat loop if `OddityService:IsEnabled` for the class's scope; all distances, spacings and chances come from the owning class's `Settings`.
- API: `CrossingPool.new(class: any, label: string)` — class supplies `Settings` and `Scope`
- API: `CrossingPool:Setting(name: string, fallback: number) -> number`
- API: `CrossingPool:Log(message: string)` — only when `Settings.DebugLog`
- API: `CrossingPool:PointFor(site: Site) -> Vector3?` — the site's hallway floor point
- API: `CrossingPool:ArmDistance() -> number`
- API: `CrossingPool:Trigger(site: Site) -> boolean` — starts the oddity and puts the site on cooldown
- API: `CrossingPool:GetArmed() -> { Site }`
- API: `CrossingPool:GetRunning() -> { [string]: Site }`
- API: `CrossingPool:Nearest(position: Vector3) -> (Site?, number)`
- Types: `Site = { Id: string, Point: Vector3, Axis: Vector3, Across: Vector3, HalfWidth: number }`
- Settings: `ArmedCount`, `ArmDistance`, `TriggerDistance`, `SameFloorTolerance`, `ApproachDot`, `ApproachMinSpeed`, `ApproachChance`, `CandidateMinDistance`, `CandidateMaxDistance`, `CandidateSpacing`, `CandidateSamples`, `SiteSpacing`, `EndInset`, `MinHallwayWidth`, `SiteCooldown`, `PollInterval`, `DebugMarker`, `DebugLog`
- Tags: reads `MazeFloor` indirectly through `HallwaysService.All`
- Requires: `ServerStorage.Services.OddityService`, `ReplicatedStorage.Services.HallwaysService`, `ReplicatedStorage.Services.CharacterService`, `ReplicatedStorage.Services.MathService`, `ReplicatedStorage.Services.VanishedService`

### HallwayOddity.luau
Base class for map-scope oddities that occupy a hallway span rather than a single prop. It resolves and picks hallway spans, caches the span's bounding box, and offers a helper for broadcasting door actions to all clients.
- API: `HallwayOddity.new(config: { [string]: any }?, class: any?) -> self`
- API: `HallwayOddity.Resolve(class, position: Vector3) -> HallwayRegion.Span?` — span at a position.
- API: `HallwayOddity.Pick(class) -> HallwayRegion.Span?` — occupied / biased / distant span depending on `RequiresPlayer` and `Settings.OccupiedChance`.
- API: `HallwayOddity:CanStart(span: HallwayRegion.Span?) -> (boolean, string?)`
- API: `HallwayOddity:Start(span: HallwayRegion.Span, duration: number?) -> boolean` — caches `BoxCFrame`/`BoxSize`, then `Oddity.Start`.
- API: `HallwayOddity:FireMapDoors(action: string, ...)` — fires `Oddities/MapDoors` to all clients with this oddity's token.
- Remotes: `Oddities/MapDoors` (fired)
- Requires: `ServerStorage.Classes.Oddity`, `ServerStorage.Services.HallwayRegionService`, `ReplicatedStorage.Services.CommunicationService`
- Notes: class fields `Scope = "Map"`, `ConfigName = "MapOddityConfig"`, `RequiresPlayer`, `IncludeRoomFloors`

### ServerTool.luau
Server-side base class for tools; a thin `ToolBase` subclass whose only addition is inventory consumption. Everything else (equip/unequip/activate lifecycle, cooldown, animation-marker waits, sound, client signalling) is inherited.
- API: `ServerTool.extend(className: string) -> class`
- API: `ServerTool.new(tool: Tool, class: any?) -> self` — delegates to `ToolBase.new`.
- API: `ServerTool:Consume(n: number?) -> boolean` — removes `n` (default 1) of `self.Name` from the holder's inventory; false when there is no owning player.
- Subclass: `Class = ServerTool.extend(name)`, `Class.new(tool, class)` forwards to `ServerTool.new(tool, class or Class)`, then override the ToolBase hooks — usually `OnActivated`, sometimes `OnEquipped` / `OnUnequipped` / `OnCleanup` / `OnDestroy`. `self.Config` is `ToolConfigs[tool.Name]`; `self.Character` / `self.Humanoid` are only populated after an Equipped event.
- Requires: `ReplicatedStorage.Classes.ToolBase`, `ServerStorage.Services.InventoryService`

### Sound.luau
Attaches an ambient `AudioEmitter` to a tagged instance: reads the instance's `Sound` attribute, finds the matching emitter template under `ReplicatedStorage.Sounds`, and clones it onto the nearest BasePart. Warns and does nothing when the template is missing.
- API: `Sound.new(instance: Instance) -> self` — clones the emitter; `self.Emitter` is nil when setup failed.
- API: `Sound:Destroy()` — destroys the cloned emitter.

### SpeedDrink.luau
Server tool that grants a temporary speed boost. Plays an open sound, waits `UseDelay`, plays a drink sound, consumes one, then hands a cloned visual effect to `SpeedBoostService` for the boost's duration.
- API: `SpeedDrink.extend(className: string) -> class`
- API: `SpeedDrink.new(tool: Tool, class: any?) -> self`
- API: `SpeedDrink:OnActivated()` — the whole drink sequence.
- Requires: `ServerStorage.Classes.ServerTool`, `ServerStorage.Services.SpeedBoostService`
- Notes: config keys `OpenSound`, `DrinkSound`, `Visual`, `UseDelay`, `WalkSpeed`, `Duration`, `FovBoost` (sounds and visual are descendants of the Tool, not global assets)

### TrapObject.luau
Bear-trap style placeable that snaps shut on the first non-Ghost NPC to touch it. Springing despawns the NPC, plays the trap animation until its "Finished" marker, plays the close sound, and schedules the trap for removal.
- API: `TrapObject.new(trap: Model) -> self` — connects Touched on every descendant part plus Destroying.
- API: `TrapObject:Spring(model: Instance?)` — fires once (`Closed` attribute guards re-entry); ignores Ghost and anything that is not a live NPC.
- API: `TrapObject:Destroy()` — disconnects all connections.
- Requires: `ServerStorage.Classes.NPC` (for `NPC.FromModel`), `StunService`, `AudioService`, `ToolConfigs.Trap`

### SurfaceWalker.luau
Kinematic surface locomotion for any humanoid rig -- the NPC-side counterpart to the player Wallstick. Takes a rig, an optional `NpcAnimator`, and a surface normal (e.g. `-Vector3.yAxis` for a ceiling), anchors the root, disables collisions and platform-stands the humanoid, then pivots the rig along a polyline of surface contact points at constant speed with frame-rate-independent turn smoothing, feet planted on the surface and the walk/run animation driven through the animator. Works for any NPC (`SurfaceWalker.new(npc.Model, npc.Animator, normal)`) or bare rig; restores all saved physics state on `Destroy`.
- API: `SurfaceWalker.CeilingContact(position: Vector3, exclusions: { Instance }, fallbackY: number?) -> Vector3` -- static; raycasts 60 studs up from just above the position (excluding the given instances and all player characters) and returns the ceiling hit, or the position at `fallbackY` (default +60) on a miss
- API: `SurfaceWalker.CeilingRoute(route: { node }, exclusions: { Instance }, lateralOffset: number?, fallbackY: number?) -> { Vector3 }` -- static; maps a hallway-graph route to per-node ceiling contacts at the same X/Z, optionally offset sideways across the travel direction (used by Sisters' side-by-side spacing and the CeilingDweller walk-in)
- API: `SurfaceWalker.new(model: Model, animator: any?, surfaceNormal: Vector3) -> self`
- API: `SurfaceWalker:PlaceAt(contact: Vector3, direction: Vector3?)` -- snap the rig onto the surface at a contact point
- API: `SurfaceWalker:WalkAlong(points: { Vector3 }, speed: number, gait: ("Walk" | "Run")?) -> boolean` -- yields until the path completes; false if stopped, destroyed or deparented mid-walk
- API: `SurfaceWalker:Stop()` -- cancels the current walk
- API: `SurfaceWalker:Destroy()` -- disconnects and restores collision/anchoring/humanoid state
- Requires: `Services.MathService` (`ExpAlpha`)

## Enemies

### Enemies\Blind.luau
A deaf-to-sight, hearing-driven hunter: it registers an "ear" with `HearingService` and builds *Determination* from noises, which decays in silence and controls its speed tier (Investigate / Alert / Chase). Distinct behaviours are the flinch-and-turn "notice", coasting past a noise position after overshooting, playing the looping `Listen` animation override while standing at its search point, and only killing when highly certain.
- API: `Blind.new(model: Model, config) -> self` — adds the heard-noise and determination fields.
- API: `Blind:BuildStateMachine() -> StateMachine` — Investigate/Pursue/Attack/Search plus the shared Idle/Wander/Patrol/Despawn and a Stunned wrapper that stops the listen override; evaluators `Hearing` and `Contact`.
- Requires: `ServerStorage.Classes.NPC`, `HearingService`, `Configs.HeartbeatConfig`
- Notes: overrides `NPC.new` and `BuildStateMachine`; writes the heartbeat `PursuitAttribute` on the model while pursuing or attacking; the Search state plays `Config.Animations.Listen` (preloaded at construction) through `NpcAnimator:PlayOverride` for the greater of `SearchTime` and the track's length, and Investigate/Pursue/Attack/Stunned each stop it on entry

### Enemies\CeilingDweller.luau
A Chaser that spawns on the ceiling and physically drops onto the floor before behaving normally: `Start` tweens the model down with collisions and humanoid states disabled, cues the victim's client camera ("Drop" then "Scream"), and only then hands off to `NPC.Start`.
- API: `CeilingDweller.new(model: Model, config, initialTarget: Player?, dropFloorPosition: Vector3?, dropFloorNormal: Vector3?) -> self`
- API: `CeilingDweller:BuildStateMachine() -> StateMachine` — reuses `Chaser.BuildStateMachine`.
- API: `CeilingDweller:Start()` — the drop sequence, then `NPC.Start`.
- Remotes: `Enemies/CeilingDwellerCamera` (fired)
- Requires: `ServerStorage.Classes.Enemies.Chaser`, `TweenProxyService`
- Notes: overrides `Start` and `BuildStateMachine`; the state machine is pre-set to `Chase` before the drop so it lands already hunting

### Enemies\Chaos.luau
Not an NPC at all — a fast-moving hazard that sweeps a precomputed route of points, killing any player whose distance to the travelled segment is within `KillRange` and granting a discovery event on near misses. It pivots the model along the route each Heartbeat rather than pathfinding.
- API: `Chaos.new(model: Model, config, route: { Vector3 }, warningToken) -> self` — root part is `model.Chaos`; two-state Run/Despawn machine.
- API: `Chaos:TravelRoute()` — lerps along each route leg, sweeping for kills; the final leg ends at the wall crash point, where it despawns.
- API: `Chaos:OnStart()` — anchors the root.
- API: `Chaos:OnDespawn() -> number?` — cancels the warning token, disables particles, lingers for their lifetime.
- Tags: applies `Enemy`, `Chaos`
- Requires: `ServerStorage.Classes.EnemyBase`, `DeathService`, `EnemyDiscoveryService`, `RoomService`, `MathService.DistanceToSegment`
- Notes: extends EnemyBase; overrides `OnStart` / `OnDespawn`

### Enemies\Chaser.luau
The plain sight-based pursuer and the template most humanoid enemies build on: see a player, chase, attack, and fall back to Patrol. It publishes `ChaseTargetUserId` for clients, reacts at safe-room doors when the target escapes into one, and randomly re-skins the model from `Config.Variants` (skin colour and hair) at construction.
- API: `Chaser.new(model: Model, config) -> self` — applies the visual variant first.
- API: `Chaser:BuildStateMachine() -> StateMachine` — Idle/Wander/Patrol/Chase/Attack/Search/RoomReaction/Stunned/Despawn with a `Perception` evaluator.
- API: `Chaser.Chase(changeState, npc, target: Player, allowRoomReaction: boolean?)` — the chase state, exported so subclasses (Mimic) can call it.
- Requires: `ServerStorage.Classes.NPC`, `RoomService`
- Notes: sets `Chaser.AttackLostState = "Search"`; overrides `BuildStateMachine`; every calm state clears the chase-target attribute

### Enemies\Creep.luau
An ambient, stationary eye-cluster: it clones its eye plate into a randomly scattered pattern from a weighted variant table, kills the hallway lights around itself via `LightService`, and simply despawns (granting discovery) when a player walks within `DespawnRange`. It never moves or attacks.
- API: `Creep.new(model: Model, config) -> self` — picks a variant, scatters eye plates, builds an Ambient state with a Proximity evaluator.
- API: `Creep:OnStart()` — anchors the root and claims the hallway light disable.
- API: `Creep:OnDespawn() -> number?` — releases the light claim.
- Tags: applies `Enemy`, `Creep`
- Requires: `ServerStorage.Classes.EnemyBase`, `LightService`, `EnemyDiscoveryService`, `Configs.CreepConfig`
- Notes: extends EnemyBase; overrides `OnStart` / `OnDespawn`

### Enemies\Eye.luau
A static staring hazard that damages players for looking at it: damage accrues per player from the view angle (centre hurts more than edge, with a falloff exponent) and is applied in discrete hits, telling the client each time. A `Visor` tool, a safe room, or being vanished makes a player immune (via `Vanished.IsForEye`, so the Gravity Warper's `IgnoreExceptEye` tag does not protect against it); a stun pauses the stare.
- API: `Eye.new(model: Model, config) -> self` — Stare/Stunned machine, per-player damage progress table.
- API: `Eye.FromModel(model: Instance?) -> any?` — reverse lookup for live Eyes.
- API: `Eye:GetViewAngle(player: Player) -> number?` — nil when out of range or not vulnerable.
- API: `Eye:OnStart()` — anchors parts, plays the looping `eye_idle` track, registers in the lookup.
- API: `Eye:OnDespawn() -> number?` — unregisters and stops the animation.
- Remotes: `Enemies/EyeHit` (fired)
- Tags: applies `Enemy`, `Eye`, `Observable`
- Requires: `ServerStorage.Classes.EnemyBase`, `EnemyObservationService`, `EyeHitService`, `DeathService`, `RoomService`
- Notes: extends EnemyBase; overrides `OnStart` / `OnDespawn`; `Eye:_burnWatchers` clears the death cause again if the hit did not actually kill

### Enemies\Ghost.luau
An NPC that ignores pathfinding entirely and floats along published `GhostMotion` legs so clients can interpolate the same motion. Its distinguishing behaviour is Lurk: it fades out, plants itself at a danger-biased unobserved hallway spot, and re-fades and hides for a while the moment anyone looks at it; drifting near a player makes it Vanish.
- API: `Ghost.new(model: Model, config) -> self`
- API: `Ghost:Start()` — anchors every part, disables the humanoid state machine, adds the `Ghost` tag, then `NPC.Start`.
- API: `Ghost:Despawn()` — removes the tag, then `NPC.Despawn`.
- API: `Ghost:BuildStateMachine() -> StateMachine` — Drift/Lurk/Vanish/Despawn.
- API: `Ghost:FloatTo(goal: Vector3) -> boolean` — flies one leg; true if it ended up near a player.
- Tags: applies `Ghost` (plus `Enemy` from NPC)
- Requires: `ServerStorage.Classes.NPC`, `Services.GhostMotionService`, `Services.HallwaysService`, `ServerStorage.Services.GazeService`, `GhostAreaService`, `DangerMapService`, `Configs.GhostConfig`
- Notes: overrides `Start`, `Despawn`, `BuildStateMachine`; has no Chase/Attack states at all

### Enemies\Mimic.luau
The most elaborate enemy: it copies a random living player's appearance, name, verified badge and held walkie-talkie, then runs one of many "encounter modes" (Mirror, Withdraw, Shadow, Wallface, Turnaway, Passerby, Blocker, Afk, Emote, Spin, Approach) that all read as another player behaving oddly — including handing network ownership to the victim so the client mirrors its own movement. Getting too close, fleeing, or turning away trips it into a chase, where it reveals a built-from-parts monster face, floats, and on a kill assumes the victim's identity.
- API: `Mimic.new(model: Model, config) -> self`
- API: `Mimic:Start()` — `NPC.Start`, preloads the Fly override, picks and assumes an identity.
- API: `Mimic:Despawn()` — clears reveal/float/mirroring, then `NPC.Despawn`.
- API: `Mimic:BuildStateMachine() -> StateMachine` — Idle(loiter)/AfkIdle/Wander/Patrol/Stalk/Chase/Attack/Search/Stunned/Despawn with a `Perception` evaluator.
- API: `Mimic:RollEncounterMode(allowAfk: boolean?) -> string`
- API: `Mimic:PickIdentity() -> Player?` — prefers a player who cannot currently see it.
- API: `Mimic:AssumeIdentity(player: Player)` — applies name, badge, HumanoidDescription and radio copy on a background thread.
- API: `Mimic:StartMirroring(target: Player)` / `Mimic:StartSpinning(target: Player)` / `Mimic:StopMirroring()` — hand control of the model to a client and take it back.
- API: `Mimic:SetHeadLock(target: Player?)` / `Mimic:SetAttackActive(active: boolean)` — attributes clients read.
- API: `Mimic:SetFacing(direction: Vector3?)` / `Mimic:ClearFacing()` — AlignOrientation-based facing while walking.
- API: `Mimic:StartFloat()` / `Mimic:StopFloat()` — hip-height rise with a sine bob; shows/hides the chase face.
- API: `Mimic:ShowChaseFace()` / `Mimic:HideChaseFace()` — builds the welded eyes/mouth/teeth model procedurally.
- Remotes: `Enemies/Mirror` (fired), `Enemies/MimicReveal` (fired)
- Requires: `ServerStorage.Classes.NPC` extended from `Enemies.Chaser`, `Services.MimicMotionService`, `Configs.MimicConfig`, `Configs.AnimationConfig`, `HallwayGraphService`, `RoomService`, `EnemyDiscoveryService`
- Notes: overrides `Start`, `Despawn`, `BuildStateMachine`; delegates the actual chase to `Chaser.Chase(..., false)`; sets `_laneProbeDrop` while floating so lane checks account for the raised hips

### Enemies\Sisters.luau
A pair of translucent, harmless figures that patrol the hallway ceilings forever. At start it clones itself into a twin, makes both rigs see-through, and walks them upside down via `SurfaceWalker`, endlessly pathfinding between random `HallwayGraphService` nodes. Both sisters are driven as one formation: a single virtual center walks the ceiling-snapped route and every Heartbeat each sister is placed abreast of it at her assigned side of `SideSpacing`, so they stay exactly side by side through corners; when a new leg reverses direction the side assignments are negated so the pair turns in place instead of circling each other. Both heads track the nearest player through the neck attachment each Heartbeat. No kill sweep, no light flicker, no forget-and-despawn — it patrols until despawned externally (config `Harmless = true` blocks touch kills).
- API: `Sisters.new(model: Model, config, startTip: Vector3, direction: Vector3, destinationTip: Vector3?) -> self` — only `startTip`/`direction` are used now; the destination is accepted for the old call sites and ignored.
- API: `Sisters:Start()` — clones the twin, prepares both models, places them on the ceiling, starts the patrol and face loops.
- API: `Sisters:Despawn()` — disconnects, destroys walkers, animators and both models.
- API: `Sisters:Patrol()` — the endless node-to-node ceiling walk loop, one formation leg at a time.
- API: `Sisters:GetCenter() -> Vector3` — midpoint of the pair.
- Tags: applies `Enemy`, `Sisters`
- Requires: `Classes.NpcAnimator`, `Classes.StateMachine`, `Classes.SurfaceWalker`, `EnemyService` (collision group), `ReplicatedStorage\Services\HallwayGraphService`, `ReplicatedStorage\Services\CharacterService`
- Notes: standalone class — it extends neither EnemyBase nor NPC, but exposes the same `new` / `Start` / `Despawn` / `EnemyId` contract `EnemyService:Spawn` needs

### Enemies\Stalker.luau
Follows a player from behind without ever being seen: it tails at `FollowDistance` while unobserved, for as long as it takes, and being looked at throws it into a Flee state that sprint-routes to a hide spot, rejecting any path that would carry it through a player's view cone. The stalk ends only when it closes to `StrikeDistance` of the victim, at which point it Reveals — seizing their camera, turning to face them, and killing. It also owns the shared Peek behaviour states.
- API: `Stalker.new(model: Model, config, spot: PeekSpotService.PeekSpot?, player: Player?) -> self` — passing a spot starts it in `Seek` (peek mode) instead of Idle.
- API: `Stalker:Start()` — hides the name display, sets the walk track, then `NPC.Start`.
- API: `Stalker:Despawn()` — releases the camera and exits Peek, then `NPC.Despawn`.
- API: `Stalker:BuildStateMachine() -> StateMachine` — Idle/Wander/Patrol/Stalk/Reveal/Flee/Stunned/Despawn plus all `Peek.States`.
- API: `Stalker:OnPeekFinished(reason: string, player: Player?)` — the Peek callback; a completed peek may roll into a stalk based on local danger.
- Remotes: `Enemies/FaceStalker` (fired)
- Requires: `ServerStorage.Classes.NPC`, `Enemies.Behaviors.Peek`, `PeekSpotService`, `HideSpotService`, `DangerMapService`, `EnemyObservationService`
- Notes: overrides `Start`, `Despawn`, `BuildStateMachine`; warns to output when a retreat ends `NoPath`/`Stuck`/`Obstructed`

### Enemies\WeepingAngel.luau
Chases normally but freezes solid the instant any player observes it, and resumes the moment it is unobserved. Every non-Frozen state is wrapped in a `released` helper that clears the frozen attribute, and the perception evaluator runs at 0.05s so the freeze feels instantaneous.
- API: `WeepingAngel.new(model: Model, config) -> self` — tags the model for the shared observed-freeze system.
- API: `WeepingAngel:BuildStateMachine() -> StateMachine` — Idle/Patrol/Frozen/Chase/Attack/Stunned/Despawn, starting in Patrol.
- Tags: applies `ObservedFreezeConfig.Tag` (plus `Enemy` from NPC)
- Requires: `ServerStorage.Classes.NPC`, `Configs.ObservedFreezeConfig`
- Notes: overrides `BuildStateMachine` only; Chase and Attack both re-check `IsObserved` and bail to Frozen

### Enemies\Behaviors\Peek.luau
A shared, non-class behaviour module: a set of state functions letting any NPC hide at a `PeekSpotService` spot, lean out into view, hold, and pull back a fixed number of times. It anchors the NPC and poses it by CFrame rather than walking, and abandons if the player closes in, looks directly at it, or the arc leaves every player's screen.
- API: `Peek.StateNames` — ordered list `{ "Seek", "Lurk", "Peek", "Retreat", "Rest" }` for trigger tables.
- API: `Peek.States` — map of those ids to state functions, to be merged into the host's state table.
- API: `Peek.GetFindOptions(config) -> PeekSpotService.FindOptions` — builds find options from the enemy config.
- API: `Peek.Enter(npc: any)` — anchors the root, stops movement, rolls `PeeksLeft`.
- API: `Peek.Exit(npc: any)` — unanchors, restores the humanoid state machine and walk speed.
- Requires: `PeekSpotService`, `EnemyObservationService`; the host NPC must implement `OnPeekFinished(reason: string, player: Player?)` and supply config keys `PeekCountMin/Max`, `MinPeekDistance`, `MaxPeekDistance`, `RearArc`, `ViewCone`, `PeekWaitTime`, `LeanTime`, `HoldTimeMin/Max`, `RetreatTime`, `RestTimeMin/Max`, `RetryInterval`, `SeenHoldTime`

### Oddity.luau
Root of the whole oddity hierarchy: a self-contained, timed anomaly with a numeric `Token`, a merged settings table, and a run window. `Oddity.extend(kind, parent)` builds subclasses; the two intermediate bases are `PropOddity` (`Scope = "Prop"`, context is a `Model`) and `PlayerOddity` (`Scope = "Player"`, context is a `Player`), alongside `HallwayOddity` (`Scope = "Map"`, context is a hallway span). Concrete oddities live in `Classes\Oddities\`, are auto-registered by `OddityService` at require time, and must satisfy the contract: a `.new(config)` returning `Base.new(config, Class)`, an optional `OnStart(context) -> boolean?` (return `false` to abort) and `OnStop()` hook, an optional static `Pick(class)` that chooses a context for ambient auto-spawning, and an optional static `IsAvailable(class)` / `CanStart(context)` gate; `OddityService:Start` instantiates the class with its config, checks `CanStart`, calls `Start`, and `Start` schedules its own `Stop` after the duration.
- API: `Oddity.extend(kind: string, parent: any?) -> class` — makes a subclass table with `ClassName`/`Kind` set
- API: `Oddity.new(config: { [string]: any }?, class: any?)` — assigns the next `Token`, empty callback list, inactive
- API: `Oddity:OnStopped(callback: (any) -> ())` — queue a one-shot callback fired on stop
- API: `Oddity:Setting(name: string, fallback: number) -> number` — numeric config lookup with default
- API: `Oddity:RandomDuration() -> number` — random value between `MinDuration` (45) and `MaxDuration` (120)
- API: `Oddity:CanStart(context: any) -> (boolean, string?)` — base always allows; subclasses override
- API: `Oddity:Start(context: any, duration: number?) -> boolean` — pcalls `OnStart`, then `task.delay`s `Stop` when duration > 0
- API: `Oddity:Stop() -> boolean` — pcalls `OnStop`, runs and clears the stop callbacks
- API: `Oddity:Elapsed() -> number` — seconds since start, 0 when inactive
- API: `Oddity:Remaining() -> number` — seconds left, 0 when inactive

### PropOddity.luau
Intermediate base for oddities that act on a single prop `Model` in the workspace; the start context is the model itself and the default duration is 0 (runs until something stops it). Reads settings from `PropOddityConfig` and is never ambient, so props are driven by their own pool/services rather than `OddityService`'s auto-spawn loop.
- API: `PropOddity.new(config: { [string]: any }?, class: any?)` — adds `self.Model`
- API: `PropOddity:CanStart(model: Model?) -> (boolean, string?)` — rejects non-models and models outside workspace
- API: `PropOddity:Start(model: Model, duration: number?) -> boolean` — stores the model, defaults duration to 0
- Requires: `Classes\Oddity`; `Configs\PropOddityConfig` via `ConfigName`

### PlayerOddity.luau
Intermediate base for oddities that afflict one player; the start context is the `Player`, and the oddity auto-stops when that player's humanoid dies. Reads settings from `PlayerOddityConfig` and is not ambient — `PlayerOddityService` picks and starts these.
- API: `PlayerOddity.new(config: { [string]: any }?, class: any?)` — adds `Player`, `Character`, `Humanoid`, `Died`
- API: `PlayerOddity.IsAvailable(class: any) -> boolean` — static availability gate, base returns true
- API: `PlayerOddity:CanStart(player: Player?) -> (boolean, string?)` — requires a living humanoid
- API: `PlayerOddity:Start(player: Player, duration: number?) -> boolean` — caches character/humanoid, hooks `Humanoid.Died`
- API: `PlayerOddity:Stop() -> boolean` — disconnects the death hook, then base stop
- Requires: `Classes\Oddity`, `ReplicatedStorage\Services\CharacterService`; `Configs\PlayerOddityConfig` via `ConfigName`

### PlayerOddityTool.luau
Shared server-side base for inventory items that trigger a player oddity on their holder. It selects the configured effect or one configured choice, asks `PlayerOddityService` to start it, consumes one item only after a successful start, and shows a notification when the effect is rejected.
- API: `PlayerOddityTool.new(tool: Tool, class: any?) -> PlayerOddityTool`
- API: `PlayerOddityTool:OnActivated()` — starts the configured player oddity and consumes the item on success
- API: `PlayerOddityTool:_ChooseEffect() -> (string?, {[string]: any}?)`
- Remotes: `Notifications/Show` (fired on rejection)
- Requires: `Classes\ServerTool`, `Services\PlayerOddityService`, `ReplicatedStorage.Services.CommunicationService`

## Oddities

### Oddities\ChaosWarning.luau
Extends `HallwayOddity`. Fires the client `MapDoors` remote so every door in the hallway box (room floors included) slams open and shut in chaos mode as a telegraph, with no light effects.
- API: `ChaosWarning.new(config: { [string]: any }?)`
- API: `ChaosWarning:OnStart() -> boolean` — sends `Start` with opening/closing speeds and door intervals, tagged `"ChaosWarning"`
- API: `ChaosWarning:OnStop()` — sends `Stop`
- Remotes: `Oddities/MapDoors` (fired)
- Requires: `Classes\HallwayOddity`

### Oddities\DoorsOpen.luau
Extends `HallwayOddity`. Swings all doors in an occupied hallway span open once and holds them, requiring a living player in the span.
- API: `DoorsOpen.new(config: { [string]: any }?)`
- API: `DoorsOpen:OnStart() -> boolean` — sends `Start` with `OpeningSpeed` (0.75)
- API: `DoorsOpen:OnStop()` — sends `Stop`
- Remotes: `Oddities/MapDoors` (fired)
- Requires: `Classes\HallwayOddity`

### Oddities\HallwayBlocker.luau
Extends `HallwayOddity`. Clones the `Gate` prop into a hallway span and drops it to the floor so the corridor is walled off, then destroys it on stop. Picking prefers spans nobody is looking at, skips spans already blocked, and keeps clear of junctions with three or more exits.
- API: `HallwayBlocker.new(config: { [string]: any }?)` — adds `self.Blocker`
- API: `HallwayBlocker.Pick(class: any) -> HallwayRegion.Span?` — weighted-distant span, unseen preferred
- API: `HallwayBlocker:OnStart() -> boolean` — clones/aligns the gate, records the span as active
- API: `HallwayBlocker:OnStop()` — destroys the gate, frees the span
- Requires: `Classes\HallwayOddity`, `Services\GazeService`, `Services\HallwayRegionService`, `Services\HallwayGraphService`, `ReplicatedStorage\Services\HallwaysService`, `ReplicatedStorage.Props.Other.Gate`

### Oddities\HallwayChaos.luau
Extends `HallwayOddity`. Full panic event in one hallway: lights flicker chaotically along the span for the whole duration while every door in the box slams open and shut.
- API: `HallwayChaos.new(config: { [string]: any }?)` — adds `self.LightClaim`
- API: `HallwayChaos:OnStart() -> boolean` — claims a chaos flicker, fires `MapDoors` `Start` in `"Chaos"` mode
- API: `HallwayChaos:OnStop()` — releases the flicker claim, fires `MapDoors` `Stop`
- Remotes: `Oddities/MapDoors` (fired)
- Requires: `Classes\HallwayOddity`, `Services\LightService`

### Oddities\HallwayCrush.luau
Extends `HallwayOddity`. Closes both walls of a straight hallway in until they meet, sealing the corridor. `HallwayWallService` supplies the frame, the junction mouths and the wall strips; the run is a **single junction-free stretch** of corridor, taken from `HallwayWallService.Limit` — the span with every mouth from either side cut out of it, then the remaining stretch that the target position stands in (or the longest one, when the pick had no target), capped to `MaxLength` only if that stretch is on its own longer than it. So the two ends of a run are the two intersections that bound it, and no intersection is ever inside one: a junction never has walls closing across it, and anyone standing in one is outside the effect entirely rather than relying on the lethal-interval and mouth-sealing rules below to spare them. Ambient picks that chose their span for being occupied pass that player's own position through, so the stretch that closes is the one they are standing in rather than the longest stretch elsewhere along the same span. Every wall inside the run closes over its **full extent**, cut only at the ends of the run itself. The map already segments its walls at each junction -- measured over 1986 walls, none covers more than half of an opening on its own side, and the furthest any reaches into one is the 1.24-stud stub the map itself builds into the corner -- so an opening simply has no wall part to move, and cutting at the junction mouths was only lopping the last stud off each wall and leaving a notch where the corridor stepped back out to full width. Each remaining in-span piece keeps its outer face pinned and grows inward -- thickness `+= offset`, centre moves in by `offset / 2` -- so the corridor narrows with no sightline opening up behind the wall. The map's five wall layers share exact top, bottom, end and face planes with each other, which z-fights badly once they are split and moved, so each layer takes its own tiny nudge from `LAYER_NUDGE` (end overshoot, height, and for Wainscot a hair of extra thickness since it matches Wallpaper exactly) with Wallpaper as the reference; pieces cut from the same wall overlap their shared ends rather than abutting, and the two sides use different overshoots and heights so nothing lines up when they meet at the seal. Everything is measured off the recorded base size, so it all reverts on stop. Split wallpaper pieces get a compensating `OffsetStudsU` so the tiling stays continuous across the new seam. Pilasters, hallway lanterns, paintings and whole doorways shift inward by the same offset, each doorway's `DoorHeader` is instead thickened like the wall it belongs to (it is the wall above the door, so translating it alone left a notch), the station's centred `CeilingBeam` shrinks by twice it, and each doorway gains three generated jamb slabs that line the reveal the moving door leaves behind, so walking through a door leads down a short stub before the room. Any opening the run leaves in a connecting hallway's wall is sealed shut as the run closes — held over from when a run could swallow whole intersections, and now idle on a map whose corridors all offer a junction-free stretch, since a run that stops at its junctions leaves no opening behind: for each junction, the wall segments flanking the opening are cloned and extended lengthwise toward each other, staying in that hallway's own wall plane, meeting in the middle with the same `SealOverlap`. Each layer is handled separately and skipped where it already runs unbroken across the junction -- crown moulding usually does -- so from the connecting hallway the branch reads as solid papered wall flush with the wall either side of it, with only the carpet left to give it away. The clones are parented to the effect's own model and sit a hair proud of the wall they extend, so nothing z-fights and the map's own walls are never touched. Standing in an opening as it seals is lethal, so nobody is left inside it. Floors, carpet runners and ceilings are untouched, because the corridor only ever narrows. Only the stretches where **both** sides actually have a closing wall are lethal: the per-side wall coverage is merged (gaps up to a doorway wide are closed so a door never creates a safe pocket), intersected, then inset by `SafeMargin`, so standing in a T or L mouth -- where one side is open corridor and nothing is closing on you -- is never counted as being crushed, in either orientation. Each doorway also registers an alcove -- the tunnel from its inner face out to the original wall plane, which covers that doorway's whole half of the corridor, because nothing is closing in from a side that has an opening in it -- so being pushed toward a door by the closing wall is never lethal, however far in the wall has come -- and it reaches `DoorwayMargin` studs past each edge of the opening, so standing off to one side of a door is safe rather than lethal. Standing in an alcove is never lethal, so sheltering in the recess behind a moving door is safe. Enemies caught in a lethal stretch are despawned through `EnemyBase:Despawn` the moment the gap first closes past `KillWidth`. The kill is client-initiated: the region, its lethal intervals and the closing curve are broadcast on `Oddities/MapCrush`, `ReplicatedStorage.Services.HallwayCrushDamageService` decides from the local character's own position and reports back, and the server re-validates within `KillTolerance` before recording cause `HallwayCrush` and applying the kill, once per player. A server backstop kills anyone still inside `BackstopDelay` after the corridor seals, so a silent or stalled client cannot walk away. On stop the walls slide back over `OpenTime` and every edited part, clone and pivot is restored exactly.
- API: `HallwayCrush.new(config: { [string]: any }?)` — adds `self.Candidate`, `self.Edits`, `self.Movers`, `self.Headers`, `self.Seals`, `self.SealRegions`, `self.Shifters`, `self.Shrinkers`, `self.Reveals`, `self.Structure`, `self.Killed`
- API: `HallwayCrush.Resolve(class: any, position: Vector3) -> Candidate?` — manual placement candidate, on the junction-free stretch the request position stands in
- API: `HallwayCrush.Pick(class: any) -> Candidate?` — random span biased toward occupied ones by `OccupiedChance`, closing the stretch the occupant is in and otherwise the longest stretch of the span
- API: `HallwayCrush:CanStart(context: any) -> (boolean, string?)`, `HallwayCrush:Start(context: any, duration: number?) -> boolean`
- API: `HallwayCrush.Resolve` and `HallwayCrush.Pick` keep the capped run inside one contiguous junction-free interval and centre occupied selections around the player's position
- API: `HallwayCrush:OnStart() -> boolean` — splits the walls, collects the fixtures, builds the reveals, computes the lethal intervals, broadcasts the region and starts the closing loop
- API: `HallwayCrush:Crush(player: Player, slack: number) -> boolean` — validates and applies one kill; used by both the client report and the backstop
- API: `HallwayCrush:OnStop()` — retracts over `OpenTime`, then restores every edit and frees the span
- Remotes: `Oddities/MapCrush` (fired to clients on start/stop, listens for the client's `"Crushed"` report)
- Tags: reads `HallwayWall`, `HallwayStation`, `PictureFrame`, `Doorway`
- Requires: `Classes\HallwayOddity`, `Classes\Oddity`, `Services\HallwayWallService`, `Services\HallwayRegionService`, `Services\DeathService`, `Services\EnemyService` (despawns enemies caught in the seal), `ReplicatedStorage\Services\HallwaysService`, `ReplicatedStorage\Services\CharacterService`, `ReplicatedStorage\Services\HallwayCrushDamageService`

### Oddities\HallwayVoid.luau
Extends `HallwayOddity`. Opens a bottomless pit in a hallway: the span is trimmed back to the far edge of each junction it meets — measured from the crossing corridor's own footprint, whether that corridor runs through the junction or merely ends at it, plus `IntersectionInset` — so an intersection and every side-corridor mouth keep their floor, then the floor slabs and carpet runners overlapping that rectangle are subtracted from — each part is resized to its first remaining piece and cloned for the rest, so cross-hallway floors at an intersection lose only the overlap and nothing is left hanging over the hole. Dark walls line the shaft, sunk beneath the thickest floor or carpet slab they sit under so nothing z-fights, stacked translucent layers fade the drop to black, a single plank crosses the gap end to end — its angle comes from two endpoints whose sideways offset is clamped inside the hallway walls, so `PlankAngle` is only honoured up to the tilt the corridor width allows and the plank never enters a wall — and anything that falls past `KillDepth` inside the opening dies with cause `HallwayVoid`. Every edited part is restored on stop.
- API: `HallwayVoid.new(config: { [string]: any }?)` — adds `self.Candidate`, `self.Edits`, `self.Structure`, `self.KillConnection`
- API: `HallwayVoid.Resolve(class: any, position: Vector3) -> Candidate?` — manual placement candidate for a position
- API: `HallwayVoid.Pick(class: any) -> Candidate?` — random span whose floor can be cut, unoccupied and unseen
- API: `HallwayVoid:CanStart(context: any) -> (boolean, string?)`, `HallwayVoid:Start(context: any, duration: number?) -> boolean`
- API: `HallwayVoid:OnStart` clamps the crossing plank's angle and length to the opening width using `WidthPadding`
- API: `HallwayVoid:OnStart() -> boolean` — cuts the floor, builds the shaft, arms the kill loop
- API: `HallwayVoid:OnStop()` — destroys the shaft, restores every cut part, frees the span
- Tags: reads `MazeFloor`, re-applies it to cut floor pieces
- Requires: `Classes\HallwayOddity`, `Classes\Oddity`, `Services\GazeService`, `Services\DeathService`, `Services\HallwayRegionService`, `Services\RoomService`, `ReplicatedStorage\Services\HallwaysService`, `ReplicatedStorage\Services\HallwayGraphService`, `ReplicatedStorage\Services\CharacterService`

### Oddities\LanternFall.luau
Extends `FixtureFall` (via `PropOddity`). Unanchors a ceiling lantern so it falls, killing its light while it is down and restoring the light plus the `Floor1Light` tag when the fixture is put back.
- API: `LanternFall.new(config: { [string]: any }?)` — adds `self.LightClaim`
- API: `LanternFall:OnFall(model: Model)` — disables the model's lights, removes tag `Floor1Light`
- API: `LanternFall:OnRestore(model: Model)` — re-adds the tag and releases the light claim
- Tags: applies/removes `Floor1Light`
- Requires: `Classes\FixtureFall`, `Services\LightService`

### Oddities\PaintingDweller.luau
Extends `PropOddity`. Spawns a humanoid rig hidden behind a painting's `Canvas`, tweens it forward through a hole decal so it lunges out of the wall, flickers nearby lights and shakes nearby players' cameras, then attacks any living non-vanished player who comes within reach until it retreats and is destroyed on stop. Only paintings whose canvas has empty space (no hallway, no room) behind it are eligible. Presented to players as the "Painting Lurker" enemy: kills record the `PaintingDweller` death cause, popping grants event discovery to every nearby player it shakes, and it has its own Index entry.
- API: `PaintingDweller.new(config: { [string]: any }?)` — adds rig, canvas, decal, GUI and animation state
- API: `PaintingDweller:IsCandidate(model: Model) -> boolean` — anchored wide canvas with dead space behind it
- API: `PaintingDweller:OnStart() -> boolean` — builds the rig, hides decals, plays the pop tween with the one-shot `StartAnimation` handing off to the looping `ThrashAnimation`, starts the attack poll
- API: `PaintingDweller:GroundedFor() -> number` — seconds since the pop
- API: `PaintingDweller:WhyNotFixed() -> string?` — reason the fixture cannot be reset yet
- API: `PaintingDweller:IsReadyToFix() -> boolean`
- API: `PaintingDweller:OnStop()` — retreat tween, destroys the rig, restores decals and clears `OddityBusy`
- Remotes: `Oddities/PaintingDwellerPop` (fired to nearby players)
- Tags: reads `Room`
- Requires: `Classes\PropOddity`, `Classes\FixtureFall` (for `DescribeNotFixed`), `Services\DeathService`, `Services\EnemyDiscoveryService`, `Services\LightService`, `ReplicatedStorage\Services\CommunicationService`, `ReplicatedStorage\Services\CharacterService`, `ReplicatedStorage\Services\HallwaysService`, `ReplicatedStorage\Services\VanishedService`, `ReplicatedStorage.Enemies` rig templates

### Oddities\PaintingFall.luau
Extends `FixtureFall` (via `PropOddity`). Knocks a wall painting loose and shoves it away from the hallway centre line with a lift and a random spin so it clatters onto the floor.
- API: `PaintingFall.new(config: { [string]: any }?)`
- API: `PaintingFall:OnLoose(model: Model, root: BasePart)` — applies the linear and angular impulses
- Requires: `Classes\FixtureFall`, `ReplicatedStorage\Services\HallwaysService`, `ReplicatedStorage\Services\MathService`

### Oddities\PlayerHeadStare.luau
Extends `PlayerOddity`. Tells one player's client to run the head-stare effect for the duration; only available when at least `MinimumPlayersForHeadStare` (default 3) players are alive.
- API: `PlayerHeadStare.new(config: { [string]: any }?)`
- API: `PlayerHeadStare.IsAvailable(class: any) -> boolean` — living-player count gate
- API: `PlayerHeadStare:CanStart(player: Player?) -> (boolean, string?)` — base check plus the population gate
- API: `PlayerHeadStare:OnStart() -> boolean` — fires the remote with the duration
- API: `PlayerHeadStare:OnStop()` — fires the remote with 0 to cancel
- Remotes: `Oddities/HeadStare` (fired to the victim)
- Requires: `Classes\PlayerOddity`, `ReplicatedStorage\Services\CommunicationService`, `ReplicatedStorage\Services\CharacterService`

### Oddities\PlayerSize.luau
Extends `PlayerOddity`. Rescales the victim's character by a random multiplier from the config's `SizeOptions` list and restores the original scale on stop.
- API: `PlayerSize.new(config: { [string]: any }?)` — adds `self.OriginalScale`
- API: `PlayerSize:OnStart() -> boolean` — aborts when `SizeOptions` is missing or empty
- API: `PlayerSize:OnStop()` — restores the original scale
- Requires: `Classes\PlayerOddity`

### Oddities\PlayerHeadSize.luau
Extends `PlayerOddity`. Sets the victim humanoid's `HeadScale` to `HeadSizeMultiplier` times its existing value, which scales the head and attached accessories for every client, then restores the original value on stop.
- API: `PlayerHeadSize.new(config: { [string]: any }?)` — adds the tracked head-scale value and original scale
- API: `PlayerHeadSize:OnStart() -> boolean` — applies `HeadSizeMultiplier` (default 1.5)
- API: `PlayerHeadSize:OnStop()` — restores the original head scale
- Requires: `Classes\PlayerOddity`

### Oddities\PlayerTransparency.luau
Extends `PlayerOddity`. Makes every fully opaque part of the victim's character slightly see-through (including parts added while it runs) and restores them on stop.
- API: `PlayerTransparency.new(config: { [string]: any }?)` — adds the original-transparency map and `DescendantAdded` hook
- API: `PlayerTransparency:OnStart() -> boolean` — applies `OddTransparency` (0.1) and watches for new parts
- API: `PlayerTransparency:OnStop()` — disconnects and restores
- Requires: `Classes\PlayerOddity`

### Oddities\RatScurry.luau
Extends `Oddity` directly with `Scope = "Prop"` and `ConfigName = "PropOddityConfig"`, but takes a `CrossingPool.Site` as its context instead of a model. Clones the `Rat` prop just inside one hallway wall, runs it across the corridor to the opposite wall with a bounce and a tail-side wiggle, plays a one-shot positional squeak, then destroys it. Harmless — the rat has no humanoid and never collides or queries.
- API: `RatScurry.new(config: { [string]: any }?)` — adds `self.Site`, `self.Rat` and the heartbeat connection
- API: `RatScurry:CanStart(site: any) -> (boolean, string?)` — needs a site with `Point`/`Across` and the rat template present
- API: `RatScurry:Start(site: any, duration: number?) -> boolean` — duration defaults to the crossing time plus `Linger`
- API: `RatScurry:OnStart() -> boolean` — clones the rat, picks a random side to start from, drives the run each heartbeat
- API: `RatScurry:OnStop()` — disconnects and destroys the rat
- Settings: `RatModel` (default `Rat`), `Sound` (`ReplicatedStorage.Sounds` template name), `Speed`, `EdgeMargin`, `Linger`, `BobHeight`, `BobRate`, `WiggleAngle`, `WiggleRate`
- Requires: `Classes\Oddity`, `ReplicatedStorage\Services\AudioService`, `ReplicatedStorage.Props.Other.Rat`
- Notes: parents the rat under a `workspace.Oddities` folder it creates on demand

### Oddities\Transparency.luau
Extends `HallwayOddity`. Fades every eligible world part that sits mostly inside a hallway box to near-invisible, so the corridor's geometry seems to vanish; skips character parts and anything tagged `TransparencyIgnore`, and uses a module-level refcount so overlapping instances restore correctly.
- API: `Transparency.new(config: { [string]: any }?)` — adds the claimed-part set and the `DescendantAdded` hook
- API: `Transparency:OnStart() -> boolean` — box query plus a non-queryable sweep, then watches new parts
- API: `Transparency:OnStop()` — decrements claims and restores parts whose last claim dropped
- Tags: reads `TransparencyIgnore`
- Requires: `Classes\HallwayOddity`

## Tools

### Tools\Big Character.luau
Server half of the Big Character item: starts the `Size` player oddity with a fixed `1.1` character scale and consumes one item on success.
- API: `BigCharacter.new(tool: Tool)`
- Requires: `Classes\PlayerOddityTool`

### Tools\Big Head.luau
Server half of the Big Head item: starts the `HeadSize` player oddity and consumes one item on success.
- API: `BigHead.new(tool: Tool)`
- Requires: `Classes\PlayerOddityTool`

### Tools\Random Oddity.luau
Server half of the Random Oddity item: chooses evenly among big head, big character, small character and transparency, then consumes one item on success.
- API: `RandomOddity.new(tool: Tool)`
- Requires: `Classes\PlayerOddityTool`

### Tools\Small Character.luau
Server half of the Small Character item: starts the `Size` player oddity with a fixed `0.9` character scale and consumes one item on success.
- API: `SmallCharacter.new(tool: Tool)`
- Requires: `Classes\PlayerOddityTool`

### Tools\Transparency.luau
Server half of the Transparency item: starts the player `Transparency` oddity and consumes one item on success.
- API: `Transparency.new(tool: Tool)`
- Requires: `Classes\PlayerOddityTool`

### Tools\Bandage.luau
Server half of the Bandage tool: a bare `Healer` subclass, so activation consumes one and heals `HealAmount` from `ToolConfigs`.
- API: `Bandage.new(tool: Tool)`
- Requires: `Classes\Healer` (extends `ServerTool`)

### Tools\Camcorder.luau
Server half of the camcorder: the gamepass gate. On `Record` it verifies the caller owns the tool and is alive, and — only when `CaptureConfig.RequireGamepass` is set — that they hold the pass named by `Config.Gamepass`, refusing while that pass id is still `0`. With the flag off the tool is available to everyone, which is how it ships until the pass is linked. Never consumes — the camcorder is unlimited use.
- API: none beyond the `ServerTool` hooks.
- Remotes: `Tools/Signal` — listens `Record`, fires `Allowed` / `Denied`
- Requires: `Classes.ServerTool`, `Configs.CaptureConfig`, `MarketplaceService`, `PerkService`

### Tools\Camera.luau
Server half of the tripod Camera: validates the client's placement CFrame, hands it to PhotoCameraService, and consumes the tool so each camera is single use.
- API: `Camera.new(tool: Tool) -> self`
- Remotes: `Tools/Signal` (listened, `Place`)
- Requires: `Classes\ServerTool`, `Services.PhotoCameraService`

### Tools\Energy Drink.luau
Server half of the Energy Drink tool: a bare `SpeedDrink` subclass, so activation consumes one and applies the configured walk-speed and FOV boost.
- API: `EnergyDrink.new(tool: Tool)`
- Requires: `Classes\SpeedDrink` (extends `ServerTool`)

### Tools\Flashlight.luau
Server half of the flashlight: activation toggles the `SpotLight` in the handle and plays the handle's click emitter; the light is forced off when unequipped or destroyed.
- API: `Flashlight.new(tool: Tool)` — starts disabled
- API: `Flashlight:SetEnabled(enabled: boolean)` — sets `self.Enabled` and the handle spotlight
- API: `Flashlight:OnActivated()` — toggle plus click sound
- API: `Flashlight:OnUnequipped()` / `Flashlight:OnDestroy()` — force off
- Requires: `Classes\ServerTool`

### Tools\Gravity Warper.luau
Server half of the Gravity Warper: on activation it verifies a ceiling exists above the holder, consumes one, tags the character with `Vanished.EyeExemptTag` ("IgnoreExceptEye") so every enemy except the Eye treats them as absent, and fires `GravityWarp/Warp` to the holder's client so `GravityWarpService` runs the ceiling tween. Player, character and root are captured before `Consume`, because consuming the last charge destroys the Tool synchronously. The tag and the `GravityWarping` attribute clear when the client reports done over `GravityWarp/Finished` (fired on every client exit path, so the gate spans the real warp including the descent and re-activation cannot slip in while the client is still finishing), on death, or on a fallback timer of `AscendTime + Duration + DescendTime + 5` if the report never arrives; a stale delayed clear cannot evict a newer warp's pending entry.
- API: `GravityWarper.new(tool: Tool)`
- Remotes: `GravityWarp/Warp` (ensured and fired), `GravityWarp/Finished` (ensured and listened)
- Tags: applies/removes `IgnoreExceptEye` on the character
- Requires: `Classes\ServerTool`, `ReplicatedStorage.Services.CharacterService`, `ReplicatedStorage.Services.CommunicationService`, `ReplicatedStorage.Services.VanishedService`

### Tools\Medkit.luau
Server half of the Medkit tool: a bare `Healer` subclass, identical behaviour to Bandage with its own config values.
- API: `Medkit.new(tool: Tool)`
- Requires: `Classes\Healer` (extends `ServerTool`)

### Tools\Pathfinder.luau
Server half of the Pathfinder: tracks a `uses` attribute on the tool and spends one each time a marker is placed, consuming an inventory item and resetting the counter when it hits zero. Players who own the `Pathfinder` perk spend nothing.
- API: `Pathfinder.new(tool: Tool)` — seeds the `uses` attribute and registers the `Placed` handler
- Requires: `Classes\ServerTool`, `Services\PerkService`, `Services\InventoryService` (via `ServerTool:Consume`)

### Tools\Soda.luau
Server half of the Soda tool: a bare `SpeedDrink` subclass with its own config values.
- API: `Soda.new(tool: Tool)`
- Requires: `Classes\SpeedDrink` (extends `ServerTool`)

### Tools\SpellBook.luau
Server half of the spell book: on activation it tags the caster as vanished, freezes their walk speed, plays the `Book` animation with book particle effects that follow the tool and a VFX dummy welded in the caster's place, waits for the `BookEnd` marker, then consumes one book. Cleanup stops the track, destroys the effects and dummy, untags and unfreezes the caster.
- API: `SpellBook.new(tool: Tool)`
- API: `SpellBook:OnActivated()` — the cast sequence
- API: `SpellBook:OnCleanup()` / `SpellBook:OnDestroy()` — tear down effects and restore the caster
- Tags: applies `Vanished.Tag`
- Requires: `Classes\ServerTool`, `ReplicatedStorage\Services\VanishedService`, `ReplicatedStorage.Props.Other` (`BookEffects`, `VFXDummy`)

### Tools\Trap.luau
Server half of the bear trap: activation consumes one, plays the placement sound and clones the `Trap` prop at the player's pivot, destroying the oldest placed trap once more than `MaxInWorld` exist.
- API: `Trap.new(tool: Tool)`
- API: `Trap:OnActivated()` — place and prune
- Requires: `Classes\ServerTool`, `ReplicatedStorage.Props.Other.Trap`

### Tools\Visor.luau
Server half of the visor: equipping clones the tool's face `Accessory` onto the character (renamed `VisorWorn`, with a `FaceFrontAttachment` at the configured CFrame), hides the tool handle, and hides every other face accessory including ones added later; unequipping or destruction restores all of it.
- API: `Visor.new(tool: Tool)` — caches the handle's transparency/shadow state
- API: `Visor:OnEquipped()` — wear the visor
- API: `Visor:OnUnequipped()` / `Visor:OnDestroy()` — remove and restore
- Requires: `Classes\ServerTool`

### Tools\Walkie Talkie.luau
Server half of the walkie talkie: asks `WalkieTalkieService` to reconcile the owner whenever the tool is created, equipped, unequipped or destroyed, so a powered radio rebuilds its audio graph onto whichever tool instance the player currently holds.
- API: `WalkieTalkie.new(tool: Tool)`
- API: `WalkieTalkie:OnEquipped()` / `WalkieTalkie:OnUnequipped()` / `WalkieTalkie:OnDestroy()`
- Requires: `Classes\ServerTool`, `Services\WalkieTalkieService`
