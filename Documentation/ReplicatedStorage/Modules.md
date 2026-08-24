# ReplicatedStorage / Modules

Legacy placement. New shared helpers must be added as Services or Classes, never here.

### Aim.luau
Tiny math helper for pointing something at a target and easing a rotation toward a goal frame-rate-independently.
- API: `Aim.Toward(position: Vector3, target: Vector3) -> CFrame` — rotation-only look-at
- API: `Aim.Ease(rotation: CFrame, goal: CFrame, rate: number, deltaTime: number) -> CFrame` — exponential lerp toward goal

### Bob.luau
Sine-wave vertical bobbing helper: pick a random phase once, then sample a Y offset each frame.
- API: `Bob.NewPhase() -> number` — random phase in [0, 2pi)
- API: `Bob.Offset(clock: number, phase: number, height: number, period: number) -> Vector3` — Y-axis sine offset

### DangerField.luau
Procedural "danger" heat field over the maze: fractal Brownian noise per floor, gated by distance from the spawn so the area around start is always safe. Also bakes a grid of candidate spawn points with their danger values.
- API: `DangerField.GetFloorIndex(position: Vector3, settings: FieldSettings) -> number` — floor number from Y
- API: `DangerField.SampleField(position: Vector3, settings: FieldSettings) -> number` — raw fBm noise 0-1 with contrast
- API: `DangerField.SampleGate(position: Vector3, settings: FieldSettings) -> number` — smoothstep ramp out of the safe radius
- API: `DangerField.Sample(position: Vector3, settings: FieldSettings) -> number` — gate * field, the usable danger value
- API: `DangerField.MeasureExtent(floors: { BasePart }) -> (number, Vector3)` — largest horizontal span and center
- API: `DangerField.BakePoints(floors: { BasePart }, spacing: number, settings: FieldSettings) -> { SpawnPoint }` — grid of `{ Position, Danger }` on floor tops
- API: `DangerField.BuildSettings(startPosition: Vector3, extent: number, overrides: { [string]: any }?) -> FieldSettings` — config values scaled to the map extent
- Requires: `Configs.DangerConfig`

### extend.luau
Returns a single function that gives a table a metatable forwarding reads and writes to a list of fallback tables/Instances, rebinding functions so a table extension is called with the extended table as `self`.
- API: `extend(t: {}, ...: {} | Instance) -> {}` — mixin/delegation helper; first extension that has the key wins

### FriendAvatar.luau
Client-only cache that loads the local player's friend list and builds R15 character models from their HumanoidDescriptions, keyed by an arbitrary string so the same key always yields the same friend. Clones a pre-assembled prototype per user id and strips accessories that failed to weld.
- API: `FriendAvatar.GetUserIds() -> { number }` — yields until the friend list has loaded
- API: `FriendAvatar.PickUserId(key: string) -> number` — stable random friend per key, falls back to the local player
- API: `FriendAvatar.GetDescription(userId: number) -> HumanoidDescription?` — cached, pcall-guarded
- API: `FriendAvatar.Build(key: string) -> Model?` — clone of the cached avatar prototype for that key

### GhostMotion.luau
Shared math and attribute protocol for ghost drift: builds a travel "leg" (origin, target, duration) that the server publishes onto the model as attributes and clients read back, plus bobbing and fade timing.
- API: `GhostMotion.NewLeg(origin: CFrame, goal: Vector3, speed: number, startedAt: number) -> Leg` — leg facing the direction of travel
- API: `GhostMotion.NewHold(cframe: CFrame, startedAt: number) -> Leg` — zero-duration stationary leg
- API: `GhostMotion.Evaluate(leg: Leg, now: number) -> CFrame` — position lerp plus separate turn lerp
- API: `GhostMotion.Bob(clock: number, phase: number) -> Vector3` — GhostConfig-sized bob offset
- API: `GhostMotion.Publish(model: Model, leg: Leg)` — writes `DriftOrigin`/`DriftTarget`/`DriftDuration`/`DriftStartedAt`
- API: `GhostMotion.Read(model: Model) -> Leg?` — reads those attributes back
- API: `GhostMotion.PublishFade(model: Model, startedAt: number)` / `GhostMotion.ReadFade(model: Model) -> number?` — `FadeStartedAt`
- API: `GhostMotion.PublishAppear(model: Model, startedAt: number)` / `GhostMotion.ReadAppear(model: Model) -> number?` — `AppearStartedAt`
- API: `GhostMotion.FadeAlpha(startedAt: number, now: number) -> number` — sine in-out 0-1 over `GhostConfig.FadeTime`
- Requires: `Modules.Bob`, `Configs.GhostConfig`

### HallwayGraph.luau
Builds a navigable node graph from the tagged maze floor parts by intersecting hallway rectangles (perpendicular crossings and end-to-end parallel joins), then offers nearest-node lookup, Dijkstra pathfinding, and walking-distance queries. The graph is cached and invalidated automatically whenever a tagged floor is added or removed.
- API: `HallwayGraph:Build() -> { RouteNode }` — forces a fresh build, bypassing the cache
- API: `HallwayGraph:Get() -> { RouteNode }` — cached node list
- API: `HallwayGraph:Invalidate()` — drops the cache
- API: `HallwayGraph:FindNearestNode(position: Vector3) -> RouteNode?` — linear scan
- API: `HallwayGraph:CountExits(node: RouteNode) -> number` — neighbor count
- API: `HallwayGraph:FindPath(from: RouteNode, to: RouteNode, edgeCost: ((RouteNode, RouteNode) -> number)?) -> { RouteNode }?` — Dijkstra with optional custom cost
- API: `HallwayGraph:GetWalkingDistance(firstPosition: Vector3, secondPosition: Vector3) -> number` — off-graph positions snapped to the nearest hallway span
- API: `HallwayGraph:IsFarFromPlayers(position: Vector3, distance: number) -> boolean` — true if no alive player root is within `distance`
- Tags: listens `MazeFloor`, `HallwayRoomFloor` (added/removed only, to invalidate the cache); `HallwayRoomFloor` nodes are marked not usable as destinations
- Requires: `Services.CharacterService`

### Hallways.luau
Geometric view of the same tagged floor parts as oriented rectangles: which hallway contains a point, the closest point on one, and the longest unobstructed straight span through a position by merging collinear hallway intervals. Cached per `includeRoomFloors` and auto-invalidated on tag changes.
- API: `Hallways.All(includeRoomFloors: boolean?) -> { Hallway }` — cached hallway rectangles
- API: `Hallways.Invalidate()` — clears both cache variants
- API: `Hallways.At(position: Vector3, includeRoomFloors: boolean?) -> Hallway?` — containing hallway, with a height window
- API: `Hallways.ClosestPoint(hallway: Hallway, position: Vector3) -> Vector3` — clamped point on the floor surface
- API: `Hallways.Nearest(position: Vector3) -> Hallway?` — nearest by closest-point distance
- API: `Hallways.Along(hallway: Hallway, position: Vector3) -> number` — signed distance along the axis
- API: `Hallways.PointAt(hallway: Hallway, along: number) -> Vector3` — point on the axis at floor height
- API: `Hallways.StraightSpanAt(position: Vector3, preferredDirection: Vector3?) -> StraightSpan?` — best straight run through a point
- API: `Hallways.StraightSpans() -> { StraightSpan }` — one span per hallway, deduplicated
- Tags: listens `MazeFloor`, `HallwayRoomFloor` (added/removed only, to invalidate the cache)

### MimicMotion.luau
Turns a recorded movement sample into discrete WASD-style key values so a mimic can replay a player's inputs, with mirroring, reaction-delay latching, and idle aim drift.
- API: `MimicMotion.Keys(sample: MotionTrail.Sample, walkSpeed: number) -> (number, number)` — forward/right key from move vs look
- API: `MimicMotion.MirrorKeys(forwardKey: number, rightKey: number) -> (number, number)` — flips strafe only
- API: `MimicMotion.Direction(forward: Vector3, forwardKey: number, rightKey: number) -> Vector3` — unit move direction
- API: `MimicMotion.NewKey() -> Key` — latch state `{ Held, Pending, At }`
- API: `MimicMotion.HoldKey(key: Key, desired: number, clock: number) -> number` — applies the change after a random reaction delay
- API: `MimicMotion.Drift(look: Vector3, clock: number, seed: number) -> Vector3` — two-frequency yaw wander
- API: `MimicMotion.Turn(cframe: CFrame, look: Vector3, deltaTime: number, turnRate: number?) -> CFrame` — exponential turn toward a flattened look
- Requires: `Configs.MimicConfig`, `Classes.MotionTrail`

### PerfLog.luau
Flag-gated startup timing log. The server stamps a start time on ReplicatedStorage, and `Log` broadcasts topic/action/timestamp to every client, which prints it; timestamps are formatted as elapsed mm:ss.mmm since that stamp.
- API: `PerfLog.Now() -> number` — seconds since the server start attribute
- API: `PerfLog.Format(timestamp: number) -> string` — `MM:SS.mmm`
- API: `PerfLog.Print(topic: string, action: string, timestamp: number?)` — local print
- API: `PerfLog.Alert(topic: string, action: string, timestamp: number?)` — local warn
- API: `PerfLog.Log(topic: string, action: string)` — no-op unless `FLAGS.PerfLog`; server broadcasts, client prints
- API: `PerfLog.GetRemote() -> RemoteEvent` — creates it on the server, waits for it on the client
- Remotes: `Communication/PerfLog` (fired to all clients; created by this module rather than via CommunicationService, and it sits directly in Communication with no topic subfolder)
- Requires: `Configs.FLAGS`

### Redaction.luau
Progressively reveals a string word by word in a stable pseudo-random order derived from a seed, replacing hidden words with block glyphs. Longer words cost more of the reveal budget; word lists, weights, and orders are all memoized.
- API: `Redaction.Words(text: string) -> { string }` — cached whitespace split
- API: `Redaction.WordCount(text: string) -> number`
- API: `Redaction.Weights(text: string) -> ({ number }, number)` — per-word cost and total
- API: `Redaction.Order(text: string, seed: string) -> { number }` — deterministic shuffle from an FNV-1a hash of seed+text
- API: `Redaction.VisibleSet(text: string, seed: string, progress: number) -> { [number]: boolean }` — which word indices are revealed at 0-1 progress
- API: `Redaction.Render(text: string, seed: string, progress: number, options: RenderOptions?) -> string` — plain or RichText output with per-word colors, forced suppression, and block ratio
- API: `Redaction.NewlyVisible(text: string, seed: string, before: number, after: number) -> { number }` — indices gained between two progress values

### Sightline.luau
Camera visibility tests: builds a frustum from a Camera, does cone/sphere intersection, and raycasts to each part of a model to decide whether it is actually seen. Keeps a self-maintaining per-model BasePart cache that disconnects itself when the model is destroyed or unparented.
- API: `Sightline.Frustum(camera: Camera) -> Frustum?` — tangents and side factors; nil if the viewport has no height
- API: `Sightline.Intersects(camera: Camera, frustum: Frustum, center: Vector3, radius: number) -> boolean` — sphere vs frustum
- API: `Sightline.OnScreen(camera: Camera, frustum: Frustum, model: Model) -> boolean` — bounding-box test only, no raycast
- API: `Sightline.CanSee(camera: Camera, frustum: Frustum, ignore: Instance?, model: Model) -> boolean` — frustum test plus line-of-sight raycast per part

### Tagger.luau
Client-side tag bootstrap: returns a function that the StarterPlayerScripts Init script calls, which defers and then registers four CollectionService tags with `TagService:Listen` under `workspace`, constructing a class instance on add and destroying it on removal.
- API: `Tagger()` — module returns a single function; call it once from the client Init
- Tags: listens `Hole` (-> `Classes.Hole`), `Spin` (-> `Classes.Spin`), `Watch` (-> `Classes.Watch`), `Breathe` (-> `Classes.Breathe`)
- Requires: `Services.TagService`; `Classes.Hole`, `Classes.Spin`, `Classes.Watch`, `Classes.Breathe`

### Vanished.luau
One-question helper for whether a character should be treated as absent: it carries the `Ignore` tag or has a ForceField anywhere inside it.
- API: `Vanished.Is(character: Instance?) -> boolean` — tagged `Ignore` or contains a ForceField
- API: `Vanished.Tag` — the string `"Ignore"`
- Tags: reads `Ignore`
