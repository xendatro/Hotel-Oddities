# ServerStorage / Services

Server only, self-initializing at require time via `ServerScriptService\Init.legacy.luau`. Never add an `:Init()` method.

### BadgeService.luau
Wrapper around Roblox's BadgeService that awards only badge ids listed in BadgeConfigs and keeps a per-player ownership cache. Ownership is prefetched asynchronously when a player joins and cleared when they leave.
- API: `BadgeService:AwardBadge(player: Player, id: number) -> boolean` — refuses unknown ids and already-owned badges
- API: `BadgeService:GetBadges(player: Player) -> { [number]: boolean }` — cached ownership map
- API: `BadgeService:OwnsBadge(player: Player, id: number) -> boolean` — cache lookup only, never yields
- Requires: `ServerStorage.Configs.BadgeConfigs`, `CharacterService.ForEachPlayer` / `.CleanupOnLeave`

### CeilingVentService.luau
Watches players approaching parts tagged `CeilingVent` and, when one walks under an armed vent while uncrouched, looking at it and moving toward it, opens the vent door and drops a CeilingDweller through it. Before a vent arms it now telegraphs: 10 seconds (`WALK_IN_LEAD`) before the vent's `ArmAt` time, a harmless CeilingDweller rig (tags and `EnemyId` stripped) spawns on the ceiling at an out-of-sight hallway-graph node, walks upside-down along the ceiling to the vent via `SurfaceWalker`, the door opens, it pitches ~85° while still crawling and climbs through the opening on an eased bezier (in toward the vent centre, then up), and the door closes; the walk-in starts `SPAWN_READY_DELAY` (3s) earlier and the vent cannot trigger until 3 seconds after the crawler is inside, leaving the `ArmAt` jumpscare timing unchanged (skipped gracefully when no path, hidden start point or model is available, and cancelled by a forced spawn). Also culls unengaged, unobserved dwellers and exposes a debug list of vents. Entirely inert unless `FLAGS.Enemies`.
- API: `CeilingVentService:GetVents() -> { { Vent: Instance, Floor: Vector3, Triggered: boolean } }` — vents with a solved floor drop point, sorted by full name
- API: `CeilingVentService:SpawnFromNearest(player: Player) -> boolean` — force-triggers the closest untriggered vent, cancelling any in-progress walk-in
- Remotes: `Enemies/CeilingDwellerCamera` (fired), `Enemies/CeilingVentDoor` (fired)
- Tags: listens `CeilingVent`; reads `MazeFloor` for the drop raycast
- Requires: `Services.VanishedService`, `CrouchConfig`, `DangerConfig.ProgrammaticVents`, `DangerMapService`, `EnemyService`, `EnemyDirectorService`, `TagService`, `HallwayGraphService`, `NpcAnimator`, `EnemyConfigs.CeilingDweller`, `Classes.SurfaceWalker`

### ChaosService.luau
Picks a random graph node far from every player, walks the hallway graph greedily node by node — random unvisited neighbor each step — until no unvisited neighbor remains, then appends a crash waypoint raycast into the wall along the final running direction; Chaos despawns there. A single polling scheduler fires each light's red warning (`LightService:WarnRed`) and each straight span's `ChaosWarning` oddity `WarningTime` (7s) before Chaos's timed arrival, holding any warning whose players are outside its cull range until they come near or it expires. The spawn is re-checked for player clearance when the delay elapses.
- API: `ChaosService:Spawn(onSpawned: ((any) -> ())?) -> boolean` — greedy route from a uniform random far-from-players node
- API: `ChaosService:SpawnThrough(player: Player, onSpawned: ((any) -> ())?) -> boolean` — Dijkstra approach to the caller's nearest node, then greedy continuation
- API: `ChaosService:CancelPending() -> number` — cancels every scheduled spawn/warning, returns how many
- Requires: `Services.HallwaysService`, `EnemyConfigs.Chaos`, `HallwayGraphService`, `LightService:WarnRed`, `MapOddityService:Warn`, `EnemyService`

### ChaseFlickerService.luau
Background loop that flickers the lights in the hallway containing a chased player whenever a CeilingDweller or Mimic is in a Chase or Attack state. No public API; disabled when `FLAGS.Enemies` is off.
- Requires: `EnemyService:ForEachActive`, `LightService:FlickerHallwayContaining`

### ChatCommandService.luau
Shared registry for `/command` chat commands: other modules call `.Register` and this service parses every player's chat, matches the command name or alias, enforces the admin gate and invokes the handler. Handlers receive `(player, argument)` where `argument` is the trimmed remainder of the message or `nil` when empty; admin-only commands are allowed in Studio or for the hardcoded `AdminUserIds`. Registered by `ComputerCommandService` (`/hack`, admin), `EnemyCommandService` (`/spawn`, `/peek`, `/despawn`, `/vent`, `/enemies`, non-admin), plus `InvincibleCommandService`, `MapCommandService`, `MapOddityCommandService`, `LanternSwingCommandService`, `PlayerOddityCommandService`, `ToolCommandService` and `Services.FixtureCommandService`.
- API: `ChatCommandService.Register(name: string, options: { Aliases: { string }?, AdminOnly: boolean?, Handler: (player: Player, argument: string?) -> () })` — names and aliases are lowercased; registering the same name again adds another handler and every handler for a matched name runs
- API: `ChatCommandService.IsAllowed(player: Player) -> boolean` — true in Studio or for an id in `AdminUserIds`
- API: `ChatCommandService.FindPlayer(name: string) -> Player?` — matches Name, DisplayName or UserId, case-insensitively
- API: `ChatCommandService.AdminUserIds` — mutable `{ [number]: true }` table of allowed user ids

### ComputerCommandService.luau
Implements the admin `/hack` chat command: lists every tagged computer with its assigned minigame and hacked state, teleports the caller in front of one, or force-sets computers hacked/locked. Computers are named by cycling a fixed game order per maze, and can be addressed by game name prefix or by `room_<name>`.
- API: `ComputerCommandService:Execute(sender: Player, argument: string?) -> boolean` — handles `list`, `win <game|room|all>`, `reset [game|room|all]`, or a bare target to teleport to
- Tags: reads `ComputerConfig.Tag`
- Requires: `ChatCommandService` (registers `/hack`, admin-only), `ComputerService`, `ComputerConfig`

### ComputerService.luau
Tracks which computer models each player has hacked, as per-player server state rather than an instance attribute, and replicates the set to that player. Auto-tags every eligible `Computer` model in the workspace, stamps each with a unique `ComputerConfig.IdAttribute` string attribute, and validates client completion reports by distance and rate. Sync payloads are streaming-safe: `{ Hacked = { id, ... }, Total = n }` (ids and a server-counted total, never Instance references, which deserialize to nil for streamed-out models). Re-syncs everyone when the tagged set changes, and answers rate-limited client sync requests fired back over the Sync remote.
- API: `ComputerService:IsHacked(player: Player, model: Model) -> boolean`
- API: `ComputerService:GetProgress(player: Player) -> (number, number)` — hacked count, total tagged computers
- API: `ComputerService:SetHacked(player: Player, model: Model, hacked: boolean)` — syncs the player on change
- Remotes: `ComputerConfig.Remotes.Folder/Complete` (listened), `.../Sync` (fired, and listened for client refresh requests)
- Tags: applies `ComputerConfig.Tag`
- Requires: `ComputerConfig`

### CrouchService.luau
Receives crouch state from the client and mirrors it onto the character as the `CrouchConfig.Stealth.Attribute`, rate-limiting reports and coalescing rapid toggles. Clears the attribute on each respawn.
- Remotes: `Crouch/Update` (listened)
- Requires: `CrouchConfig`

### DangerDebugService.luau
Studio-only listener that accepts a whitelist of numeric danger-field overrides from the client debug panel, rebakes the danger map and resets the enemy director. Returns immediately unless `FLAGS.DangerDebug` and running in Studio.
- Remotes: `Danger/SetConfig` (listened)
- Requires: `DangerMapService:Rebake`, `EnemyDirectorService:Reset`

### DangerMapService.luau
Bakes and serves the map-wide "danger" field: measures the extent of all `MazeFloor` parts, builds field settings anchored at the `Start` part, and samples weighted spawn points from it. Points inside a `SpawnSafeZone` part are dropped at bake time, so nothing drawing from the baked points ever spawns in the spawn safe zone. Rebakes once at require time and caches cumulative weight tables per danger bias.
- API: `DangerMapService:Rebake(overrides: { [string]: any }?)` — re-measures floors and re-bakes points
- API: `DangerMapService:GetSettings() -> DangerField.FieldSettings?`
- API: `DangerMapService:GetExtent() -> number`
- API: `DangerMapService:GetDanger(position: Vector3) -> number` — 0 when no settings are baked
- API: `DangerMapService:GetPoints() -> { SpawnPoint }`
- API: `DangerMapService:PickPoint(bias: number, accept: (SpawnPoint) -> boolean, attempts: number) -> SpawnPoint?` — danger-weighted draw with rejection
- Tags: reads `MazeFloor`, `Start`
- Requires: `Services.DangerFieldService`, `SpawnZoneService`, `DangerConfig`

### DataSaveService.luau
ProfileService front-end: loads, reconciles and releases one `PlayerData` profile per player, and lets other code either grab a loaded profile or yield until it arrives. The template holds currency, sword ownership, inventory, processed receipts, discovered enemies and discovered map intervals.
- API: `DataSaveService:Get(player: Player) -> Profile?` — nil until the profile finishes loading
- API: `DataSaveService:Wait(player: Player) -> Profile?` — yields the calling thread until loaded
- Requires: `ServerStorage.Services.ProfileService` (third-party), `ItemShopConfig`

### DeathService.luau
Records why each player died — from client kill reports, explicit strikes, or the killer model's `EnemyId` — and on death fires the death screen with that cause and a revive token. Validates client kill claims against room safety, the `Enemy` tag, `Harmless`, and the Mimic's attack window.
- API: `DeathService:RecordCause(player: Player, causeId: string?)` — stamps or refreshes the cause
- API: `DeathService:Strike(player: Player, enemy: Model, causeId: string?)` — records the cause and tells the client which enemy struck
- API: `DeathService:ClearCause(player: Player, causeId: string)` — clears only if it is still the current cause
- API: `DeathService:GetCause(player: Player) -> string?` — nil once older than `DeathConfig.CauseMemory`
- Remotes: `Death/Kill` (listened and fired to all), `Death/Strike` (fired), `Death/Show` (fired)
- Requires: `DeathConfig`, `ReviveService:Offer`, `FriendReviveService:Offer`, `EnemyDiscoveryService:GrantDeath`, `RoomService`

### DevProductService.luau
Registers one MarketplaceService receipt handler per entry in `DevProductConfigs`, running the configured grant inside a pcall and only reporting `PurchaseGranted` on success.
- Requires: `ReplicatedStorage.Services.MarketplaceService:CreateReceipt`, `ServerStorage.Configs.DevProductConfigs`

### DrawerItemService.luau
Populates drawers with pickable item displays: clones a Tool from `ReplicatedStorage.Tools` into a script-free, anchored display model, measures the drawer's bounds and handle direction to seat it on the front surface, and keeps roughly `TargetPercentage` of drawers stocked on a refill timer. Handles client pickup requests with reach, debounce and inventory checks, avoiding repeating the last drawer or item.
- Remotes: `DrawerItemConfig.Remotes.Folder/Pickup` (listened)
- Tags: listens `DrawerConfig.Tag`; applies `DrawerItemConfig.Tag`
- Requires: `DrawerConfig`, `DrawerItemConfig`, `InventoryService:Wait` / `:Add`, `ReplicatedStorage.Tools`

### DrawerService.luau
Owns the open/closed state of drawer models as attributes, plays the open/close sound, and auto-closes drawers left open longer than `AutoCloseDelay`. Client toggle requests are rate-limited and distance-checked.
- API: `DrawerService:SetOpen(model: Model, open: boolean)` — sets the state attributes and plays the sound
- Remotes: `Drawer/Toggle` (listened)
- Tags: reads `DrawerConfig.Tag`
- Requires: `DrawerConfig`, `AudioService`

### ElevatorService.luau
Teleports players from the lobby elevator into the maze: on hitbox touch it shows the loading screen, waits for the client fade and a minimum loading time, streams the destination in, then pivots the character to a part tagged with `ElevatorConfig.SpawnTag` (preferring one inside `Maze15`).
- API: `ElevatorService:SendToMap(player: Player, instant: boolean?) -> boolean` — returns whether streaming succeeded; `instant` skips the fade, loading screen and cooldown
- Remotes: `Elevator/Loading` (fired), `Elevator/FadeComplete` (listened) — both optional, looked up with `.Find`
- Tags: listens `ElevatorConfig.Tag`; reads `ElevatorConfig.SpawnTag`
- Requires: `ElevatorConfig`, `HallwayStreamingService:PrepareTeleport`

### EnemyCommandService.luau
Registers the developer enemy chat commands — `/spawn <id|all>`, `/peek`, `/despawn`, `/vent`, `/enemies` — routing Chaos, Sisters and CeilingDweller to their own placement services and everything else in front of (or behind) the caller. Results are reported via `warn`. Inert unless both `FLAGS.Enemies` and `FLAGS.EnemyCommands`.
- Requires: `ChatCommandService` (registers all five commands, not admin-only), `EnemyConfigs`, `EnemyService`, `ChaosService:SpawnThrough` / `:CancelPending`, `SistersService:SpawnInHallway`, `StalkerService:SpawnPeeking`, `CeilingVentService:SpawnFromNearest` / `:GetVents`

### EnemyDebugService.luau
Builds a periodic snapshot of every active enemy's id, state and position and broadcasts it to all players for the stats HUD, along with the director's current Stalker target name.
- API: `EnemyDebugService:GetSnapshot() -> { { Id: string, State: string, Position: Vector3 } }`
- Remotes: `Enemies/DebugSnapshot` (fired)
- Requires: `StatsHUDConfig.Enemies.Interval`, `EnemyService:GetActive`, `EnemyDirectorService:GetStalkerTarget`

### EnemyDirectorService.luau
The population manager: on a heartbeat tick it tops up resident enemy counts, schedules Chaos runs, rotates the Stalker across players, spawns Ghosts, and despawns expired enemies that are unengaged and out of sight. Placement scores candidate danger points or hallway-graph nodes by danger, player proximity and enemy spacing, and rejects anything visible from a player's eye. Defines no-op stubs for its whole API first and returns early unless `FLAGS.Enemies` and `FLAGS.Director`.
- API: `EnemyDirectorService:CanAfford(enemyId: string) -> boolean` — alive count below `MaxAlive`
- API: `EnemyDirectorService:Adopt(enemy: any, enemyId: string, selfManaged: boolean?)` — take an externally spawned enemy into the population
- API: `EnemyDirectorService:GetStalkerTarget() -> Player?`
- API: `EnemyDirectorService:GetPopulation() -> { Residents: { [string]: string }, Enemies: { string } }` — resident counts as `"alive/target"`
- API: `EnemyDirectorService:Reset()` — despawns non-self-managed enemies and clears all timers
- Tags: reads `Enemy`
- Requires: `DangerConfig.Director`, `EnemyConfigs`, `DangerMapService`, `HallwayGraphService`, `EnemyObservationService:GetEyes`, `ChaosService`, `SistersService`, `StalkerService`, `GhostAreaService`

### EnemyDiscoveryService.luau
Tracks per-player 0-1 discovery progress for each enemy in the bestiary, gained by looking at an enemy for long enough, standing near one, scripted events, or dying to it. Progress is persisted to the player's profile, replicated in steps, and a reveal is queued for the next respawn after a death-granted gain.
- API: `EnemyDiscoveryService:Get(player: Player, enemyId: string) -> number`
- API: `EnemyDiscoveryService:GetAll(player: Player) -> { [string]: number }` — cloned copy
- API: `EnemyDiscoveryService:Grant(player: Player, enemyId: string?, amount: number) -> (number, number)` — before, after; does not replicate
- API: `EnemyDiscoveryService:Set(player: Player, enemyId: string, progress: number)` — persists and replicates
- API: `EnemyDiscoveryService:Clear(player: Player)` — wipes all progress
- API: `EnemyDiscoveryService:GrantEvent(player: Player, enemyId: string?)` — the config's Event award
- API: `EnemyDiscoveryService:GrantDeath(player: Player, enemyId: string?)` — the Death award, queues the reveal
- Remotes: `Index/Update` (fired and listened as a resync request), `Index/Reveal` (fired)
- Requires: `ServerStorage.Configs.DiscoveryConfig`, `DataSaveService` (`profile.Data.DiscoveredEnemies`), `EnemyObservationService:GetView`, `EnemyService`

### EnemyObservationService.luau
Server-side record of what each client reports it can see: validated lists of `Enemy`+`Observable` models plus the camera eye and look vector, rate-limited and treated as stale after 0.2s. Everything else queries it to ask whether an enemy is being watched, or for a player's viewpoint (falling back to the root part when no fresh report exists).
- API: `EnemyObservationService:IsObservedBy(player: Player, model: Model) -> boolean`
- API: `EnemyObservationService:IsReporting(player: Player) -> boolean` — has a fresh report
- API: `EnemyObservationService:GetViewAngle(player: Player, model: Model) -> number?` — degrees off-centre, nil if unobserved
- API: `EnemyObservationService:GetView(player: Player) -> (Vector3?, Vector3?)` — eye and look, with a root-part fallback
- API: `EnemyObservationService:GetViews() -> { View }` — one per living player
- API: `EnemyObservationService.IsWithinCone(view: View, point: Vector3, cone: number) -> boolean` — dot-product cone test
- API: `EnemyObservationService:GetEyes() -> { Vector3 }` — eye positions only
- Remotes: `Enemies/UpdateView` (listened)
- Tags: reads `Enemy`, `Observable`

### EnemyService.luau
The enemy factory and registry: sets up the Enemies/Players/Furniture collision groups, clones the configured model, tags it with its `EnemyId`, hands it to the matching class in `ServerStorage.Classes.Enemies` and keeps the instance in an active list until its model is destroyed. Also strips ProximityPrompts from `Furniture` models and assigns character parts to the Players group.
- API: `EnemyService:EnsureCollisionGroup()` — registers the three groups and their non-collidable pairs
- API: `EnemyService:Spawn(enemyId: string, spawnCFrame: CFrame, ...: any) -> any?` — extra args are forwarded to the enemy class constructor; nil when `FLAGS.Enemies` is off
- API: `EnemyService:GetActive() -> { any }` — cloned list
- API: `EnemyService:ForEachActive(callback: (enemy: any) -> ())`
- API: `EnemyService:DespawnAll()`
- API: `EnemyService.CollisionGroup` — the string `"Enemies"`
- Tags: reads `Furniture`
- Requires: `ServerStorage.Classes.Enemies.*`, `EnemyConfigs`, `ReplicatedStorage.Enemies` models, `Services.PerfLoggerService`

### EyeHitService.luau
Only exists to guarantee the `Enemies/EyeHit` RemoteEvent, replacing any wrongly-typed instance of that name. Returns a table holding the remote rather than a service.
- API: data table — a single `Remote` key holding the `Enemies/EyeHit` RemoteEvent
- Remotes: `Enemies/EyeHit` (ensured)

### FixtureCommandService.luau
Registers a chat command for a FixturePool or CrossingPool so a developer can teleport to the nearest armed target or force the nearest one to fire. Warns feedback to the server output; ignores arguments starting with `swing`. Targets may be Instances (FixturePool models) or plain site tables (CrossingPool sites), which are described by their `Id`.
- API: `FixtureCommand.Bind(pool: any, label: string, names: { string })` — first name is the command, the rest become aliases
- Arguments: `drop` / `fall` / `run` force the nearest target; anything else teleports the caller to the nearest armed one
- Requires: `ServerStorage.Services.ChatCommandService`; expects a pool exposing `GetArmed`, `PointFor`, `Nearest`, `ArmDistance` and either `Drop` or `Trigger`

### FriendReviveService.luau
Sells a paid "revive your friend" offer: when a player has a pending death, every friend in the server is offered a prompt, and a claimed offer triggers a developer-product purchase that grants the revive. Friendship results are cached per user-id pair and cleared on leave; the whole service no-ops unless the ReviveFriend product id is configured.
- API: `FriendReviveService:Offer(target: Player)` — opens a timed offer window and fires it to every friend of `target`
- Remotes: `Revive/Offer` (fired), `Revive/Withdraw` (fired), `Revive/Request` (listened)
- Requires: `PerkConfig.FriendRevive`, `MarketplaceService` (`Products.ReviveFriend`, `:CreateReceipt`), `ReviveService` (`:HasPendingDeath`, `:Grant`)

### GamepassService.luau
Caches each player's gamepass ownership at join time by querying every id in `GamepassConfigs`, and keeps the cache fresh when a purchase prompt completes. Failed lookups are cached as `false` with a warning.
- API: `GamepassService:UserOwnsGamepass(player: Player, id: number) -> boolean` — cache lookup only, never yields
- Requires: `ServerStorage.Configs.GamepassConfigs`, `CharacterService.ForEachPlayer` / `.CleanupOnLeave`

### GazeService.luau
Server-side line-of-sight library: builds a short-lived cache of living, non-vanished player viewers (eye position and look vector from `EnemyObservationService`) and answers whether a point, part or model falls inside a viewer's cone with a clear raycast. Also provides a small Tracker object that accumulates seen/unseen durations across updates.
- API: `Gaze.Viewers() -> { Viewer }` — cached ~0.05s
- API: `Gaze.ViewerFor(player: Player) -> Viewer?`
- API: `Gaze.Sees(viewer: Viewer, target: Target, options: Options?) -> boolean` — options: `Cone`, `MaxDistance`, `Samples`, `Horizontal`, `LineOfSight`, `Ignore`, `Players`
- API: `Gaze.IsLookedAtBy(player: Player, target: Target, options: Options?) -> boolean`
- API: `Gaze.IsLookedAt(target: Target, options: Options?) -> (boolean, Player?)`
- API: `Gaze.Watchers(target: Target, options: Options?) -> { Player }`
- API: `Gaze.new(target: Target, options: Options?) -> Tracker`
- API: `Tracker:Update() -> boolean` — refreshes `Watchers`, `SeenFor`, `UnseenFor`
- API: `Tracker:Retarget(target: Target)` — swaps target and resets timers
- Requires: `ServerStorage.Services.EnemyObservationService`, `ReplicatedStorage.Services.CharacterService`, `ReplicatedStorage.Services.VanishedService`

### GhostAreaService.luau
Picks hover points for the Ghost enemy by choosing a hallway weighted by its floor area, sampling a random point over it, and lifting the point to the ghost's hover height. Points within `VanishDistance` of any living player or inside a `SpawnSafeZone` part are rejected, up to 12 attempts.
- API: `GhostAreaService:IsPlayerNear(position: Vector3) -> boolean` — any alive player within `Config.VanishDistance`
- API: `GhostAreaService:GetRandomPoint() -> Vector3?` — area-weighted hover point, or nil if none is clear
- Requires: `EnemyConfigs.Ghost`, `ReplicatedStorage.Services.HallwaysService`, `CharacterService.GetAliveRoot`, `SpawnZoneService`

### HallwayGridService.luau
Finds hallway "corner mouths" near a viewer — graph nodes with a side branch roughly perpendicular to the line of sight — and returns the physical corner position derived from the widths of the crossing and branching hallways. Used to place things just out of view around a corner.
- API: `HallwayGridService:GetCorners(eye: Vector3, floorY: number, minDistance: number, maxDistance: number) -> { Corner }` — each corner carries `Position`, `Axis` (eye-to-corner), `Lateral` (into the branch) and fixed `Depths = { 0, 2 }`
- Requires: `HallwayGraphService`, `ReplicatedStorage.Services.HallwaysService`, `MathService.Horizontal`

### HallwayRegionService.luau
Helpers for treating a straight hallway span as a region: comparing spans (in either direction), finding the span at a position, building a padded bounding box for it, checking for players inside, and picking random spans that are distant, occupied, or danger-weighted.
- API: `HallwayRegion.Same(first: Span, second: Span) -> boolean` — direction-agnostic within `SpatialPadding`
- API: `HallwayRegion.At(position: Vector3, includeRoomFloors: boolean?) -> Span?`
- API: `HallwayRegion.Box(span: Span) -> (CFrame, Vector3)` — padded volume using the config height windows
- API: `HallwayRegion.HasPlayer(span: Span) -> boolean`
- API: `HallwayRegion.RandomDistant() -> Span?`
- API: `HallwayRegion.RandomDistantWeighted(dangerWeight: number, accept: ((Span) -> boolean)?) -> Span?`
- API: `HallwayRegion.RandomBiased(occupiedChance: number) -> Span?`
- API: `HallwayRegion.RandomOccupied() -> Span?`
- Requires: `ReplicatedStorage.Configs.MapOddityConfig`, `ReplicatedStorage.Services.HallwaysService`, `ServerStorage.Services.DangerMapService`, `ReplicatedStorage.Services.CharacterService`

### HallwayWallService.luau
Geometry over the **walls** of a straight hallway span, the counterpart to `HallwayRegionService`'s floor-level view. Builds a `Frame` (centre, axis, across, half width, floor height and an along-range), trimming that range to the contiguous run of `MazeFloor` covering the centre line so a span never reaches into a connector whose walls are not tagged. `Mouths` reports, per side, the along-intervals where a perpendicular corridor or room floor opens through the side plane; `CutPoints` unions those boundaries from **both** sides into one sorted cut list, which is what makes opposite walls terminate at the same places. `Limit` snaps a frame outward to whole cells around a position without exceeding a length budget. `Walls` returns the tagged wall strips that run parallel to the span, sit in the side band by their inner face and are thin enough to be a wall — the inner-face test plus a thickness cap is what rejects perpendicular walls crossing the corridor at a junction — each carrying its along-range, side sign, across offset, thickness, and the local axes that map to thickness and length.
- API: `HallwayWallService.Frame(span: Hallways.StraightSpan) -> Frame?`
- API: `HallwayWallService.Length(frame: Frame) -> number`
- API: `HallwayWallService.Contains(frame: Frame, position: Vector3, margin: number?) -> boolean`
- API: `HallwayWallService.Mouths(frame: Frame) -> { Mouth }` — `{ Minimum, Maximum, Sign }` per side opening
- API: `HallwayWallService.CutPoints(frame: Frame) -> { number }` — sorted, both-side union, ends included
- API: `HallwayWallService.Closing(frame: Frame) -> { Interval }` — the span with every mouth, from either side, cut out of it
- API: `HallwayWallService.Limit(frame: Frame, position: Vector3, maximumLength: number) -> Frame`
- API: `HallwayWallService.Walls(frame: Frame) -> { Wall }`
- API: `HallwayWallService.Fixtures(frame: Frame, tag: string, margin: number?) -> { Instance }` — tagged parts/models inside the frame
- API: `HallwayWallService.Merge(intervals: { Interval }, gap: number?) -> { Interval }` — sort and coalesce, optionally closing gaps up to `gap`
- API: `HallwayWallService.Intersect(first: { Interval }, second: { Interval }) -> { Interval }`
- API: `HallwayWallService.Inset(intervals: { Interval }, amount: number) -> { Interval }` — trim both ends, dropping anything that collapses
- API: `HallwayWallService.HeightWindow`, `HallwayWallService.BelowWindow` — the vertical window `Contains` uses, exposed so clients can run the same test
- Tags: reads `HallwayWall`
- Requires: `ReplicatedStorage.Services.HallwaysService`

### HallwayStreamingService.luau
Custom per-player streaming layer: it slices the `Maze15` map into per-hallway chunk Models (cut at junctions and lounge connectors), reparents map assets into them, and each Heartbeat tick adds/removes `PersistentPerPlayer` membership so each player only holds their current hallway plus warmed branches. It also gates teleports until the destination chunks are confirmed streamed in on the client, and repairs models the client reports as missing. If `StreamingConfig.Enabled` or `workspace.StreamingEnabled` is false it degrades to a plain `RequestStreamAroundAsync` wrapper.
- API: `HallwayStreamingService:PrepareTeleport(player: Player, position: Vector3) -> boolean` — yields until the player's client confirms the destination models, false if it timed out
- Remotes: `Streaming/PrepareTeleport` (fired), `Streaming/ClientReady` (listened), `Streaming/TeleportFailed` (fired), `Streaming/ExpectedModels` (fired), `Streaming/ReportMissing` (listened)
- Tags: listens `HallwayRoomFloor`, `Enemy`, `StreamingConfig.IgnoreTag`; applies `StreamingConfig.ModelTag`
- Requires: `StreamingConfig`, `ReplicatedStorage.Services.HallwaysService` (`StraightSpans`), `HallwayGraphService`, `MathService.Horizontal`, `CharacterService.GetAliveRoot`

### HearingService.luau
Registry of "ears" (enemies, props) that want to be told about noises. It subscribes to `NoiseService`, filters each noise by radius and the ear's own `Accepts` predicate, then delays the callback by a distance-based travel time and announces the travelling sound to clients.
- API: `HearingService:AddEar(key: any, ear: Ear) -> () -> ()` — returns a disconnect function; dead ears (`IsAlive() == false`) are pruned automatically
- Remotes: `Hearing/Travel` (fired) — only when the ear key is an Instance
- Requires: `HearingConfig` (travel speed and min/max travel time), `NoiseService`

### HideSpotService.luau
Searches nearby `MazeFloor` parts for a standing position that breaks line of sight from every enemy eye, scoring candidates on eye clearance, travel distance and optional heading alignment, then verifying the best few with floor/clearance raycasts and a visibility check. Returns nil when nothing hidden is reachable.
- API: `HideSpotService:Find(origin: Vector3, agentRadius: number, options: FindOptions?) -> Vector3?` — options are `Range`, `MinDistance`, `Heading`
- Tags: listens `MazeFloor`, `Enemy`
- Requires: `MathService.Horizontal`, `EnemyObservationService:GetEyes()`

### HoleService.luau
Creates linked entry/exit hole pairs (the Shovel's dig): the entry goes where the digger stands, the exit is a random point on a random `MazeFloor` part, and both clones share an `ID` attribute plus the creator's user id. Pairs expire after 30s, are capped at 5 alive at once, and are cleaned up when their creator leaves.
- API: `HoleService:CreateHolePair(entryPosition: Vector3, owner: Player?) -> boolean` — clones `ReplicatedStorage.Props.Other.Hole` twice
- API: `HoleService:RemoveForPlayer(player: Player)` — destroys that player's pairs and any stray tagged holes they created
- Remotes: `Hole/Create` (invoked) — validates dig distance and raycasts the ground before digging
- Tags: listens `MazeFloor`, `Hole`
- Requires: `ToolConfigs.Shovel` (`MaxDigDistance`, `DigDepth`), `TagService:GetTaggedOfAncestor`, `CharacterService.GetAliveRoot`

### InventoryService.luau
Authoritative backpack/hotbar model: it tracks a slot-ordered list of tool names per player, clones templates out of `ReplicatedStorage.Tools`, keeps quantities on a `quantity` attribute, mirrors the layout to the client, and persists slots/quantities/`uses` into the player's DataSave profile. It restores the saved inventory on join, reconciles it whenever the character respawns, clears everything on death, and always guarantees exactly one Walkie Talkie.
- API: `InventoryService:Get(player: Player, toolName: string) -> Tool?`
- API: `InventoryService:GetAll(player: Player) -> { [string]: Tool }` — backpack plus equipped
- API: `InventoryService:GetQuantity(player: Player) -> number` — summed `quantity` attributes
- API: `InventoryService:GetSlot(player: Player, toolName: string) -> number?`
- API: `InventoryService:GetOrder(player: Player) -> { [number]: string }` — cloned slot table
- API: `InventoryService:Wait(player: Player, timeout: number?) -> boolean` — blocks until the saved inventory is restored
- API: `InventoryService:Sync(player: Player)` — pushes the slot payload to the client
- API: `InventoryService:Add(player: Player, toolName: string, n: number) -> boolean` — false when full or the template is missing
- API: `InventoryService:EnsureSingle(player: Player, toolName: string) -> boolean` — collapses duplicates to one copy at quantity 1
- API: `InventoryService:Remove(player: Player, toolName: string, n: number)` — destroys the tool at zero
- API: `InventoryService:RemoveAll(player: Player, toolName: string) -> number` — returns the amount removed
- API: `InventoryService:Clear(player: Player)`
- API: `InventoryService:Move(player: Player, from: number, to: number) -> boolean` — swaps two slots
- Remotes: `Inventory/Update` (fired and listened), `Inventory/Move` (listened), `Backpack/Delete` (listened)
- Requires: `InventoryConfig` (`HotbarSlots` + `BackpackSlots` = capacity), `DataSaveService`

### InvincibleCommandService.luau
Admin toggle that marks a player's character with the `Vanished` tag, making them unkillable and ignored by every entity. State is per player, survives respawns, and is dropped when they leave.
- API: `InvincibleCommandService:Set(player: Player, enabled: boolean)`
- API: `InvincibleCommandService:Is(player: Player) -> boolean`
- Tags: applies `Vanished.Tag` to the character
- Requires: `ReplicatedStorage.Services.VanishedService`, `ChatCommandService` (registers admin-only `/invincible [on|off]` and `/mortal`)

### ItemShopService.luau
Coin-and-Robux item shop: it validates a purchase against `ItemShopConfig`, checks voice-chat eligibility for voice-gated items, spends coins from the DataSave profile and grants the tool through `InventoryService`. Robux products get a receipt handler with per-`PurchaseId` deduplication, and coin balances are mirrored to a `Coins` player attribute and to the client.
- API: `ItemShopService:Sync(player: Player, result: string?, itemId: string?)` — pushes coins plus a result code (`Purchased`, `InsufficientCoins`, `InventoryFull`, `VoiceUnavailable`)
- Remotes: `Items/Purchase` (listened), `Items/Sync` (fired and listened)
- Requires: `ItemShopConfig`, `MarketplaceService.Products.Items` / `:CreateReceipt`, `DataSaveService`, `InventoryService`

### LanternFallService.luau
Wires the `Prop/LanternFall` oddity class into a `FixturePool` labelled "lantern", which arms nearby lanterns, drops one when a player approaches, and repairs it afterwards. Returns an empty table if the oddity class was never registered.
- API: `LanternFallService:Drop(model: Model) -> boolean`, `:GetArmed()`, `:GetFallen()`, `:Nearest(position)`, `:PointFor(model)`, `:ArmDistance()`, `:Setting(name, fallback)`, `:Log(message)` — all inherited from `FixturePool`
- Requires: `ServerStorage.Classes.FixturePool`, `ServerStorage.Services.FixtureCommandService` (registers `/lantern` and `/lanterns`), `OddityService:Get("Prop", "LanternFall")`

### LanternSwingCommandService.luau
Handles the `/lantern swing [seconds]` chat command by finding the nearest swayable lantern model to the caller and asking `LightService` to flag it red for the given duration (default 15s). Non-"swing" arguments are ignored so `FixtureCommand` can handle them.
- API: (no public methods; the module table is empty and exists only for its chat-command registration)
- Requires: `LanternSwayConfig.SwayModelNames`, `LightService:GetModels` / `:WarnRed`, `ChatCommandService`

### LightService.luau
Central authority over every `Floor1Light` model: it captures each lamp's baseline Lights/Neon/ParticleEmitters, then offers reference-counted "disable" claims (by radius, along a hallway, along a straight span with branch and connected-room spill, or a single model) and a family of flicker effects. It also runs a permanent ambient flicker loop that randomly blinks one or two lamps, and can set a `ChaosRed` attribute on a lamp for a duration.
- API: `LightService:GetModels() -> { Model }` — cached, invalidated by tag add/remove
- API: `LightService:DisableNear(position: Vector3, radius: number) -> LightClaim`
- API: `LightService:DisableAlongHallway(position: Vector3, distance: number) -> LightClaim`
- API: `LightService:DisableHallway(position: Vector3, preferredDirection: Vector3?, connectedDistance: number?, spanDistance: number?) -> LightClaim` — includes branch hallways and rooms touching the span
- API: `LightService:DisableModel(model: Model) -> LightClaim`
- API: `LightService:Release(claim: LightClaim)` — idempotent
- API: `LightService:WarnRed(model: Model, duration: number)` — sets/extends the `ChaosRed` attribute
- API: `LightService:FlickerChaosAlongHallway(position: Vector3, duration: number, intervalMin: number, intervalMax: number) -> FlickerClaim`
- API: `LightService:FlickerHallwayContaining(position: Vector3, duration: number, intervalMin: number?, intervalMax: number?)`
- API: `LightService:FlickerNearest(position: Vector3, count: number, duration: number, intervalMin: number?, intervalMax: number?)`
- API: `LightService:FlickerAlongHallway(position: Vector3, duration: number)` — batched blackout of a whole hallway
- API: `LightService:ReleaseFlicker(claim: FlickerClaim)`
- Tags: listens `Floor1Light`, `Room`; applies/removes `NeonOff` on darkened neon parts
- Requires: `ReplicatedStorage.Services.HallwaysService`, `AudioService:Play3DSound("Flicker", ...)`, `TagService:GetTaggedOfPredicate`, `MathService.Horizontal`

### LoadoutService.luau
Snapshots and restores a player's tools across events that wipe the inventory (death, elevator trips), preserving quantities and the attributes listed in `PerkConfig.Loadout.Attributes`.
- API: `LoadoutService:Capture(player: Player) -> Snapshot`
- API: `LoadoutService:Restore(player: Player, snapshot: Snapshot) -> boolean` — tops up missing quantities and reapplies attributes
- API: `LoadoutService:IsEmpty(snapshot: Snapshot) -> boolean`
- API: `LoadoutService:GetLivingCharacter(player: Player) -> Model?`
- Requires: `PerkConfig.Loadout.Attributes`, `InventoryService`, `CharacterService.GetAliveRoot`

### LookService.luau
Receives each client's camera pitch/yaw, rate-limits and clamps it, and stores it as `LookPitch`/`LookYaw` attributes on the character so others can render head look. A Heartbeat loop also mirrors a target player's pitch onto any `Enemy` model carrying a `LookMirrorUserId` attribute (the mimic), zeroing it otherwise.
- API: (no public methods; the module table is empty and exists only for its remote and Heartbeat loops)
- Remotes: `Look/Update` (listened)
- Tags: listens `Enemy`
- Requires: `LookConfig` (`SendInterval`, `MaxPitch`, `MaxYaw`, `MimicUpdateInterval`), `CharacterService.CleanupOnLeave`

### MapDiscoveryService.luau
Server owner of per-player map discovery. On a fixed tick it projects each living player's position onto every hallway rectangle, computes the exact span of that hallway covered by the discovery radius (accounting for lateral distance, so a player in a crossing corridor reveals only what they could see of it), and unions that span into the intervals already stored for that hallway. Only the part of a span that is not already known is considered, and that remainder is sampled with line-of-sight raycasts so nothing is discovered through a wall; standing still therefore costs no raycasts at all. Growth below the configured threshold is discarded, so neither the profile nor the network sees churn. Discovery lives in the player's profile under `DiscoveredMap` and therefore persists across runs. Rooms and connectors are revealed whole rather than by interval, because a box seen from inside is seen entirely; only hallways accumulate partial spans. The full rectangle list is sent once on join so the client can render correctly even where streaming has removed the geometry.
- API: `MapDiscoveryService:GetLayout() -> { any }` — the hallway rectangle list, keyed by quantised world position
- API: `MapDiscoveryService:GetDiscovered(player: Player) -> { [string]: Interval }?`
- API: `MapDiscoveryService:Sync(player: Player)` — sends layout plus stored discovery
- API: `MapDiscoveryService:Update(player: Player)` — one discovery pass, replicating any hallway that grew
- API: `MapDiscoveryService:UpdateLandmarks(player: Player, position: Vector3)` — records tagged landmarks inside their radius, firing only the first time each is seen
- Remotes: `Map/Sync` (fired), `Map/Reveal` (fired), `Map/Landmark` (fired)
- Tags: reads `MazeFloor`, `HallwayRoomFloor` through `HallwaysService`, plus `RoomFloor` and `ComputerRoomFloor`; reads each `MapConfig.Landmarks` tag (`HackComputer`, `Spawn`, `Exit`)
- Requires: `ReplicatedStorage.Configs.MapConfig`, `CharacterService`, `CommunicationService`, `HallwaysService`, `DataSaveService`

### MapCommandService.luau
Admin `/map` command that teleports the caller straight into the maze via `ElevatorService:SendToMap`, warning on failure and logging how long the trip took.
- API: `MapCommandService:Execute(player: Player) -> boolean`
- Requires: `ElevatorService:SendToMap`, `ChatCommandService`

### MapOddityCommandService.luau
Chat command `/mapoddity` (alias `/mapodd`) that maps a friendly word to a map-oddity kind (`transparency`, `doors`, `chaos`, `blocker`, `void`, `crush`, `sisters`/`twins`/`ceilingsisters`, plus aliases) and triggers it on the hallway containing the caller; `clear`/`stop`/`off` stops all active map oddities.
- API: (no public methods; the module table is empty and exists only for its chat-command registration)
- Requires: `MapOddityService`, `ChatCommandService`

### MapOddityService.luau
Scope wrapper around `OddityService` for the `"Map"` scope: it resolves the hallway span containing a position through the chosen oddity class, starts it, and can warn, clear or list what is running. Defaults to the `Transparency` effect.
- API: `MapOddityService:Trigger(position: Vector3, kind: string?) -> (boolean, string?, string?)` — returns ok, the kind chosen, and a failure reason
- API: `MapOddityService:Warn(position: Vector3, duration: number) -> boolean` — starts the `ChaosWarning` oddity
- API: `MapOddityService:Clear(token: number?) -> boolean` — one token, or every map oddity
- API: `MapOddityService:GetActive() -> { [number]: any }`
- Requires: `OddityService`, `ServerStorage.Classes.Oddities` map classes (`Transparency`, `DoorsOpen`, `HallwayChaos`, `HallwayBlocker`, `HallwayVoid`, `HallwayCrush`, `ChaosWarning`)

### NoiseService.luau
The game's sound-propagation source of truth: it emits `Noise` records (position, radius, source player) with a rate limit per source, keeps a one-second ring of recent noises for polling, and notifies observers immediately. A Heartbeat loop auto-emits footstep noise for every moving grounded player, with the radius chosen by crouch/walk/sprint state.
- API: `NoiseService:Emit(position: Vector3, radius: number, source: Player?, ignoreSourceInterval: boolean?) -> Noise?` — nil when the source's 0.4s interval suppresses it
- API: `NoiseService:Observe(observer: (Noise) -> ()) -> () -> ()` — returns an unsubscribe function
- API: `NoiseService:GetLatest(origin: Vector3, sequence: number, predicate: ((Noise) -> boolean)?) -> Noise?` — newest in-radius noise past a sequence number
- Requires: `CrouchConfig.Stealth`, `CharacterService.GetAliveHumanoid`

### OddityService.luau
Registry and lifecycle manager for every oddity class in `ServerStorage.Classes.Oddities`: at require time it registers each class under its `Scope`/`Kind`, merges its config (plus per-`Kind` `Effects` overrides) into `class.Settings`, and starts an ambient spawn loop for any class exposing a `Pick` function. Running oddities are tracked by token so they can be stopped individually or by scope; everything is inert in Studio edit mode.
- API: `OddityService:Register(class: any)` — also computes `class.Settings`
- API: `OddityService:Get(scope: string, kind: string) -> any?`
- API: `OddityService:Classes(scope: string) -> { [string]: any }`
- API: `OddityService:Kinds(scope: string) -> { string }` — sorted
- API: `OddityService:IsEnabled(scope: string) -> boolean`
- API: `OddityService:IsAmbient(class: any) -> boolean`
- API: `OddityService:Start(class: any, context: any, duration: number?) -> (any?, string?)` — returns the oddity or a failure reason
- API: `OddityService:Stop(token: number) -> boolean`
- API: `OddityService:StopAll(scope: string?) -> number`
- API: `OddityService:GetActive(scope: string?) -> { [number]: any }`
- Requires: `ServerStorage.Classes.Oddities` (all children), `ReplicatedStorage.Configs.<class.ConfigName>`

### PaintingDwellerService.luau
Thin wrapper that builds a `FixturePool` around the `Prop/PaintingDweller` oddity class so painting dwellers arm near players and trigger on approach. Returns an empty table if the oddity class is not registered.
- API: `PaintingDwellerService:Drop(model: Model) -> boolean` — force the oddity to start on that painting
- API: `PaintingDwellerService:Nearest(position: Vector3) -> (Model?, number)` — closest non-fallen candidate
- API: `PaintingDwellerService:GetArmed() -> {Model}` — models currently armed
- API: `PaintingDwellerService:GetFallen() -> {[Model]: any}` — models with a running oddity
- API: `PaintingDwellerService:ArmDistance() -> number` — re-arm radius from settings
- API: `PaintingDwellerService:PointFor(model: Model) -> Vector3?` — cached hallway floor point
- Requires: `ServerStorage.Classes.FixturePool`, `ServerStorage.Services.FixtureCommandService`, `OddityService`; registers chat command `/dweller` (alias `/paintingdweller`)

### PaintingFallService.luau
Same pattern as PaintingDwellerService but for the `Prop/PaintingFall` oddity — arms nearby paintings and drops them when a player walks toward one. Returns an empty table if the oddity class is not registered.
- API: `PaintingFallService:Drop(model: Model) -> boolean` — force a painting to fall
- API: `PaintingFallService:Nearest(position: Vector3) -> (Model?, number)` — closest standing painting
- API: `PaintingFallService:GetArmed() -> {Model}` — paintings currently armed
- API: `PaintingFallService:GetFallen() -> {[Model]: any}` — paintings with a running oddity
- API: `PaintingFallService:ArmDistance() -> number` — re-arm radius from settings
- API: `PaintingFallService:PointFor(model: Model) -> Vector3?` — cached hallway floor point
- Requires: `ServerStorage.Classes.FixturePool`, `ServerStorage.Services.FixtureCommandService`, `OddityService`; registers chat command `/painting` (alias `/paintings`)

### PeekSpotService.luau
Geometry search that finds a corner a stalker enemy can stand behind hidden from the player, then lean out of into view. Raycasts a sampled body rig against standing room, floor continuity, lean-arc clearance and every enemy's view cone.
- API: `PeekSpotService:Find(player: Player, options: FindOptions) -> PeekSpot?` — nearest valid peek spot
- API: `PeekSpotService:IsStillValid(spot: PeekSpot, player: Player, options: FindOptions) -> boolean` — re-run the checks on an existing spot
- API: `PeekSpotService:DebugCorner(player: Player, options: FindOptions, position: Vector3) -> any` — per-check rejection trace for the corner near a position
- API: `PeekSpotService.LeanPoints(spot: PeekSpot, lean: number) -> {Vector3}` — sampled body points at a lean fraction
- API: `PeekSpotService.PoseAt(spot: PeekSpot, lean: number, lookAt: Vector3?) -> CFrame` — root CFrame for a lean fraction
- Tags: reads `Enemy` (raycast filter)
- Requires: `HallwayGridService` (corner list), `EnemyObservationService` (enemy eyes/view cones), `MathService`

### PerkService.luau
Resolves each player's gamepass ownership once on join, mirrors it to `Perk*` player attributes, and applies the perks on every spawn: double speed, the Visor tool, and restoring items kept through death.
- API: `PerkService:Owns(player: Player, passName: string) -> boolean` — cached gamepass ownership
- API: `PerkService:WaitForPasses(player: Player) -> boolean` — yields up to 20s until ownership is resolved
- Requires: `PerkConfig`, `MarketplaceService.Gamepasses`, `InventoryService`, `LoadoutService` (death snapshot/restore), `SpeedBoostService` (sets the DoubleSpeed multiplier)

### PlayerCharacterStreamingService.luau
Sets every player character's `ModelStreamingMode` to `Persistent` so characters are never streamed out on other clients.
- API: data table — empty; all behaviour is in the connections

### PlayerLocatorService.luau
Backs the Player Locator tool: teleports the holder behind a chosen player, on a cooldown, after asking `HallwayStreamingService` to stream in the destination. Replies to the client with the remaining cooldown on every request.
- API: `PlayerLocatorService:Teleport(player: Player, target: Player) -> boolean` — attempt the teleport
- API: `PlayerLocatorService:GetCooldown(player: Player) -> number` — seconds left
- Remotes: `PlayerLocator/Teleport` (listened; fired back to the requesting client)
- Requires: `PlayerLocatorConfig`, `HallwayStreamingService:PrepareTeleport`, `InventoryService` (equip check)

### PlayerOddityCommandService.luau
Registers the `/oddity` chat command, parsing an optional effect name (size / transparency / stare) and an optional player name — with exact, display-name and prefix matching — then asking `PlayerOddityService` to trigger it. Reports results and failures via `warn`.
- API: data table — empty; the module only registers the command
- Requires: `ChatCommandService`, `PlayerOddityService`

### PlayerOddityService.luau
Randomly afflicts a living player with a `Player`-scope oddity (size, transparency, head stare) on a repeating roll, allowing one at a time per player and clearing it on respawn. Weights come from `PlayerOddityConfig.EffectWeights` and unavailable classes are skipped.
- API: `PlayerOddityService:Trigger(player: Player, kind: string?) -> (boolean, string?, string?)` — returns ok, the chosen kind, and a failure reason
- Requires: `PlayerOddityConfig`, `OddityService` (scope `"Player"`), `CharacterService`

### ProfileService.luau
Vendored third-party datastore session-locking library (loleris' ProfileService); used by DataSaveService — not modified in this project.

### ProgrammaticVentService.luau
Spawns extra ceiling vents at runtime from the `Props.Other.Vent` template, placing them flush under a `CeilingSlab` at danger-map-chosen points that are unseen by enemies, away from players, clear of world geometry and hallway station beams. Sweeps expired or spent vents back out once nobody can see them.
- API: data table — returns an empty table; everything runs from its Heartbeat loop
- Tags: reads `CeilingVent` (spacing checks and `TagService:GetApplied` trigger/spent state); spawned models are named `ProgrammaticVent` with a `ProgrammaticVent` attribute
- Requires: `DangerConfig.ProgrammaticVents`, `DangerMapService:PickPoint`, `EnemyObservationService:GetEyes`, `PerfLog`

### RatService.luau
Thin wrapper that builds a `CrossingPool` around the `Prop/RatScurry` oddity class so two hallway crossings are armed near players at any time and a rat darts across one when a player walks toward it. Returns an empty table if the oddity class is not registered.
- API: `RatService:Trigger(site: CrossingPool.Site) -> boolean` — force a rat to run at that crossing
- API: `RatService:Nearest(position: Vector3) -> (Site?, number)` — closest idle crossing
- API: `RatService:GetArmed() -> { Site }` — crossings currently armed
- API: `RatService:GetRunning() -> { [string]: Site }` — crossings with a rat mid-run
- API: `RatService:ArmDistance() -> number` — re-arm radius from settings
- API: `RatService:PointFor(site: Site) -> Vector3?` — the crossing's hallway floor point
- Requires: `ServerStorage.Classes.CrossingPool`, `ServerStorage.Services.FixtureCommandService`, `OddityService`; registers chat command `/rat` (alias `/ratscurry`)

### RecordPlayerService.luau
Plays a looping 3D record sound on every tagged record player model, choosing the lobby track when the model has a `Lobby` attribute, and stops it when the model is untagged or removed.
- API: data table — empty; behaviour is entirely the tag listener
- Tags: listens `RecordPlayer`
- Requires: `AudioService:Play3DSound` (sounds `Record` / `RecordLobby` on the `SFX` bus)

### ReviveService.luau
Captures a player's death location and inventory, prompts the Revive developer product, and on purchase respawns them at that spot with full health, their items back and a temporary ForceField. Asserts at load that the Revive product id is configured.
- API: `ReviveService:Offer(player: Player, character: Model) -> number` — record a death and return its token
- API: `ReviveService:Prompt(player: Player, token: number)` — prompt the purchase if the token is still current
- API: `ReviveService:HasPendingDeath(player: Player) -> boolean` — whether a death snapshot is stored
- API: `ReviveService:Grant(player: Player)` — perform the revive (also called from the receipt handler)
- Requires: `DeathConfig.Revive`, `MarketplaceService:CreateReceipt`, `LoadoutService` (capture/restore)

### RoomService.luau
Auto-tags `Room_*` models under a `Rooms` folder, gives each an invisible pathfinding blocker part on the `RoomBlocker` collision group that only enemies collide with, and polls every 0.1s to track which room each player is inside. Also exposes doorway lookup and an outside-the-door approach point for enemy navigation.
- API: `RoomService:GetRooms() -> {Model}` — every tracked room model
- API: `RoomService:GetRoom(player: Player) -> Model?` — the room the player is currently in
- API: `RoomService:IsInRoom(player: Player) -> boolean` — occupancy check
- API: `RoomService:IsNearOccupiedRoom(position: Vector3, distance: number) -> boolean` — horizontal distance to any occupied room's bounds
- API: `RoomService:GetDoorway(room: Model) -> Model?` — matching `Doorway_*` model, else the nearest one on the same floor
- API: `RoomService:GetDoorApproach(room: Model, agentRadius: number) -> (Vector3?, Vector3?)` — standing point outside the door and the door point
- Tags: listens `Room`; applies `Room` to matching models; reads `Doorway` + `RoomDoor`
- Requires: registers the `RoomBlocker`, `Enemies`, `Players` and `Furniture` collision groups at load

### SistersService.luau
Spawns the Sisters enemy at one end of a straight hallway span so it walks the length of it, choosing the span by a danger-map-weighted roll among spans far enough from every player.
- API: `SistersService:Spawn() -> any?` — pick a weighted route and spawn
- API: `SistersService:SpawnInHallway(player: Player) -> any?` — spawn on the span the player is standing in, from the far end
- Requires: `EnemyConfigs.Sisters`, `Hallways` module (`StraightSpans`, `StraightSpanAt`), `DangerMapService`, `HallwayGraphService:IsFarFromPlayers`, `EnemyService:Spawn`

### SpawnZoneGuardService.luau
Server-side behaviour of the spawn safe zone: while a player's root is inside a `SpawnSafeZone` part their character carries the `Ignore` tag (so enemies cannot see, target, or kill them), removed again when they leave — an `Ignore` the character already had from elsewhere is left alone. Any NPC enemy whose body touches a zone part gives up its target and is forced back to its `Patrol` state (or `Idle` when it has no patrol), on a per-enemy cooldown; stunned enemies are left alone.
- API: no public methods — runs entirely from its own connections and poll loop.
- Tags: reads `SpawnSafeZone`; applies/removes `Ignore` on player characters
- Requires: `ReplicatedStorage.Services.SpawnZoneService`, `CharacterService`, `VanishedService`, `Configs.SpawnZoneConfig`, `ServerStorage.Classes.NPC`

### SpeedBoostService.luau
Central WalkSpeed arbiter: named boost sources per player, the highest wins, multiplied by any perk multiplier and never below the tracked base speed. Tracks the character's natural base speed separately, tolerates external writes (including stuns setting speed to 0), publishes `SpeedBoost*` attributes for the client FOV effect, and expires each source on a timer.
- API: `SpeedBoostService:Apply(player, name: string, speed: number, duration: number, fov: number, effectTemplate: Instance?) -> boolean` — add or replace a named boost
- API: `SpeedBoostService:SetMultiplier(player: Player, multiplier: number)` — global multiplier (used by the DoubleSpeed perk)
- API: `SpeedBoostService:GetMultiplier(player: Player) -> number` — current multiplier
- Requires: `SprintConfig`

### StalkerService.luau
Finds a peek spot behind the player and spawns a stalker-type enemy standing there facing them, optionally relaxing the rear-arc and minimum-distance constraints when no spot is found behind. Spots inside a `SpawnSafeZone` part are refused.
- API: `StalkerService:FindSpot(player: Player, enemyId: string?) -> PeekSpot?` — peek spot using that enemy's find options
- API: `StalkerService:SpawnPeeking(player: Player, enemyId: string?, anyDirection: boolean?) -> any?` — spawn the enemy at a found spot
- Requires: `PeekSpotService`, `EnemyConfigs`, `ServerStorage.Classes.Enemies.Behaviors.Peek` (find options), `EnemyService:Spawn`, `ReplicatedStorage.Services.SpawnZoneService`

### StunService.luau
Puts an enemy NPC or Eye into its `Stunned` state for a duration, and handles the client Ball hit report by re-verifying the thrower is within `ToolConfigs.Ball.ServerRange` of the target before stunning.
- API: `StunService:Stun(model: Instance?, duration: number) -> boolean` — stun the enemy behind that model
- Remotes: `Ball/Hit` (listened)
- Requires: `ServerStorage.Classes.NPC`, `ServerStorage.Classes.Enemies.Eye`, `ToolConfigs.Ball`

### ToolCommandService.luau
Registers the admin-only `/give` chat command, parsing `<tool> [amount]` or `<player> <tool> [amount]` against the `ReplicatedStorage.Tools` folder and handing the items over via InventoryService. Amounts clamp to 100 and every outcome is reported with `warn`.
- API: `ToolCommandService:Execute(sender: Player, argument: string?) -> boolean` — run the give command
- Requires: `ChatCommandService` (registration and `FindPlayer`), `InventoryService`

### ToolService.luau
Binds each entry in `ToolConfigs` to its matching class under `ServerStorage.Classes.Tools` through that config's tag, keeping a Tool-to-instance map, and routes client tool events to the right instance's `_Dispatch`. Also back-fills `OnEquipped` shortly after creation for tools that were already in a character.
- API: `ToolService:FromTool(tool: Instance?) -> any?` — class instance for a Tool
- API: `ToolService:GetAllOf(toolName: string) -> {any}` — every live instance of a named tool
- Remotes: `Tools/Signal` (listened)
- Requires: `ToolConfigs`, `ServerStorage.Classes.Tools.*`, `InventoryService`

### VoiceActivityService.luau
Tunes each player's voice input volume and character AudioEmitter attenuation (disabling acoustic simulation, occlusion, diffraction and reverb), tracks who is talking from a client remote, and emits noise at the speaker's position every 0.05s so enemies can hear voice chat. Speaking flags time out after `VoiceChatConfig.Activity.Timeout`.
- API: `VoiceActivityService:SetActive(player: Player, active: boolean)` — set the talking flag and emit noise
- API: `VoiceActivityService:GetState(player: Player) -> State?` — `{Active, LastActiveAt}`
- API: `VoiceActivityService:ApplyVolume()` — re-apply the configured input volume to everyone
- Remotes: `WalkieTalkie/VoiceActivity` (listened; created with `.Ensure`)
- Requires: `VoiceChatConfig`, `NoiseService:Emit`

### VoiceDebugService.luau
Studio-only debug hook, gated behind `FLAGS.VoiceDebug`: lets a client set any volume entry declared in `VoiceDebugConfig` live and re-applies it to the voice and walkie-talkie chains. Returns immediately without connecting anything when the flag is off or outside Studio.
- API: data table — empty; the module only wires the remote
- Remotes: `VoiceDebug/SetVolume` (listened)
- Requires: `VoiceDebugConfig`, `FLAGS`, `VoiceActivityService:ApplyVolume`, `WalkieTalkieService:ApplyVolumes`

### WalkieTalkieService.luau
Builds a full per-player radio audio graph on the equipped Walkie Talkie — compressor, bandpass, EQ, distortion and limiter into a mixer feeding one `AudioDeviceOutput` per eligible listener plus a physical emitter on the handle — and keeps the listener set in sync with the All/Friends privacy mode. Also picks up the nearest tagged ambient emitter into the radio, relays client-requested sounds with a rate limit, plays a static death burst when a transmitting holder dies, and emits noise so enemies hear radio traffic.
- API: `WalkieTalkieService:Equip(player: Player, tool: Tool)` — build the audio graph (no-op if voice chat is unavailable for that user)
- API: `WalkieTalkieService:Unequip(player: Player, tool: Tool)` — tear it down
- API: `WalkieTalkieService:SetMode(player: Player, mode: string)` — `"All"` or `"Friends"`; mirrored to the `WalkieTalkieMode` attribute
- API: `WalkieTalkieService:SetVoiceActivity(player: Player, active: boolean)` — drive the transmit-click loop
- API: `WalkieTalkieService:StartSound(player, relayId: string, name: string, looped: boolean, timePosition: number?, playbackSpeed: number?, volume: number?)` — relay a tagged sound over the radio
- API: `WalkieTalkieService:SyncSound(player, relayId: string, timePosition: number, playbackSpeed: number, volume: number)` — correct a running relay
- API: `WalkieTalkieService:StopSound(player: Player, relayId: string)` — stop a relay
- API: `WalkieTalkieService:SetLooping(player: Player, relayId: string, looped: boolean)` — toggle looping on a relay
- API: `WalkieTalkieService:RegisterAmbientEmitter(emitter: AudioEmitter)` — allow an emitter to be picked up by nearby radios
- API: `WalkieTalkieService:ApplyVolumes()` — re-read config volumes into every live graph
- Remotes: `WalkieTalkie/SetMode`, `WalkieTalkie/TransmitSound`, `WalkieTalkie/VoiceActivity` (all listened; created with `.Ensure`)
- Tags: reads `WalkieTalkieConfig.RadioAllowedTag` on AudioEmitters/AudioPlayers
- Requires: `WalkieTalkieConfig`, `VoiceActivityService` (speaking state), `NoiseService:Emit`, `VoiceChatService:IsVoiceEnabledForUserIdAsync`

### WallstickService.luau
Server bootstrap for the vendored Wallstick controller: registers the `WallstickCollision`/`WallstickNoCollision` collision groups (non-collidable with every other group; the fake-world group collides only with itself), builds the persistent `workspace.Wallstick` model with its far-away `Origin` part and `StreamingFoci` folder, creates a client-owned streaming-focus part (AlignPosition/AlignOrientation, added as a replication focus under StreamingEnabled) for every player, and starts the replication listener that rebroadcasts each client's stick part/offset to everyone.
- Remotes: `Wallstick/Replicator`, `Wallstick/Sync` (created and listened via `Classes.Wallstick.Replication`)
- Requires: `EnemyService:EnsureCollisionGroup`, `CharacterService.ForEachPlayer`, `Classes.Wallstick.Replication`
