# ServerStorage / Modules

Legacy placement. New shared helpers must be added as Services or Classes, never here.

### EnemyDebug.luau
Developer helpers for testing enemies: spawn a peeking Stalker, find or visualize a peek spot, or spawn any configured enemy in front of (or behind) a player at its command-spawn distance.
- API: `EnemyDebug.SpawnPeekingStalker(player: Player, enemyId: string?) -> any?` — delegates to `StalkerService:SpawnPeeking`
- API: `EnemyDebug.FindPeekSpot(player: Player, enemyId: string?) -> any?` — delegates to `StalkerService:FindSpot`
- API: `EnemyDebug.DebugPeekCorner(player: Player, position: Vector3) -> any?` — visualizes corner scoring using Stalker peek options
- API: `EnemyDebug.SpawnAt(player: Player, enemyId: string) -> any?` — spawns facing the player, using `CommandSpawnDistance`/`CommandSpawnBehind`
- Requires: `ServerStorage.Configs.EnemyConfigs`, `EnemyService`, `StalkerService`, `PeekSpotService`, `Classes.Enemies.Behaviors.Peek`

### FixtureCommand.luau
Registers a chat command for a FixturePool so a developer can teleport to the nearest armed fixture or force the nearest one to drop. Warns feedback to the server output; ignores arguments starting with `swing`.
- API: `FixtureCommand.Bind(pool: any, label: string, names: { string })` — first name is the command, the rest become aliases
- Requires: `ServerStorage.Services.ChatCommandService`; expects a `FixturePool`-shaped object (`GetArmed`, `PointFor`, `Nearest`, `Drop`, `ArmDistance`)

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
- Requires: `ServerStorage.Services.OddityService`, `ReplicatedStorage.Modules.Hallways`, `ReplicatedStorage.Modules.Vanished`

### Gaze.luau
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
- Requires: `ServerStorage.Services.EnemyObservationService`, `ReplicatedStorage.Services.CharacterService`, `ReplicatedStorage.Modules.Vanished`

### HallwayRegion.luau
Helpers for treating a straight hallway span as a region: comparing spans (in either direction), finding the span at a position, building a padded bounding box for it, checking for players inside, and picking random spans that are distant, occupied, or danger-weighted.
- API: `HallwayRegion.Same(first: Span, second: Span) -> boolean` — direction-agnostic within `SpatialPadding`
- API: `HallwayRegion.At(position: Vector3, includeRoomFloors: boolean?) -> Span?`
- API: `HallwayRegion.Box(span: Span) -> (CFrame, Vector3)` — padded volume using the config height windows
- API: `HallwayRegion.HasPlayer(span: Span) -> boolean`
- API: `HallwayRegion.RandomDistant() -> Span?`
- API: `HallwayRegion.RandomDistantWeighted(dangerWeight: number, accept: ((Span) -> boolean)?) -> Span?`
- API: `HallwayRegion.RandomBiased(occupiedChance: number) -> Span?`
- API: `HallwayRegion.RandomOccupied() -> Span?`
- Requires: `ReplicatedStorage.Configs.MapOddityConfig`, `ReplicatedStorage.Modules.Hallways`, `ServerStorage.Services.DangerMapService`, `ReplicatedStorage.Services.CharacterService`

### OddityRemotes.luau
One-line wrapper that creates or fetches a RemoteEvent inside the `Oddities` communication folder, so oddity classes do not each repeat the `CommunicationService.Ensure` call. Names are supplied by callers, not listed here.
- API: `OddityRemotes.Event(name: string) -> RemoteEvent` — `CommunicationService.Ensure("Oddities", name)`, defaulting to RemoteEvent
- Remotes: `Oddities/MapDoors`, `Oddities/HeadStare`, `Oddities/PaintingDwellerPop` (ensured by the callers `HallwayOddity.luau`, `Oddities/PlayerHeadStare.luau`, `Oddities/PaintingDweller.luau`)
- Requires: `ReplicatedStorage.Services.CommunicationService`

### Tagger.luau
Server-side tag bootstrap: returns a function that `ServerScriptService\Init.legacy.luau` calls once, deferring three `TagService:Listen` registrations scoped to `workspace`, each constructing a class instance on tag add and destroying it on removal.
- API: `Tagger()` — call the returned function once at startup
- Tags: listens `TrapObject` -> `ServerStorage.Classes.TrapObject`; `Sound` -> `ServerStorage.Classes.Sound`; `Animation` -> `ReplicatedStorage.Classes.Animation`
- Requires: `ReplicatedStorage.Services.TagService`
