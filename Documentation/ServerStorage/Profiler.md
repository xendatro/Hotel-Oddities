# ServerStorage / Profiler

Portable server half. Runtime state and reports stay in ServerStorage. The only
replicated control endpoint is the authorized `ReplicatedStorage.Profiler.Transport`.
Tags: none. Access defaults allow Studio and configured developers; controlled
scenarios require Studio/private servers unless explicitly enabled for public use.

### Bootstrap.luau
`Start()` returns the runner or a proxy to the existing runtime across require
contexts. Public methods: `Start`, `Run`, `Await`, `Status`, `Cancel`, `Compare`, `Command`.
Commands: list, start, status, stop, cancel, history, result, import, compare.
`history` keeps its ID-list response by default; `details=true` returns bounded
report metadata for the UI menu without loading or exporting each full report.
Server-only commands: getReport, attachDiagnostics, await. Owns `/profile` chat command,
Runtime.Command BindableFunction and Request/Response StringValues.
Valid remote commands rejected before execution receive a correlated `busy` or
`throttled` reply. The client can retry these without duplicating a mutation.

### Config/Access.luau
User IDs, group roles, enabled flag and controlled-public-server policy.

### Config/Lifecycle.luau
Selects the optional game adapter. Falls back to a no-op when the Hotel pack is
removed. Replace this selector when installing another game's hooks.

### Core/Access.luau
Server-side developer checks and controlled-scenario permission checks.

### Core/Rpc.luau
Client readiness, correlated requests, player checks and timeouts; no InvokeClient.

### Core/Store.luau
Last 12 reports in memory and Runtime.Results; compact Summary plus numbered JSON
chunks. Validates imports and serializes before changing the store.

### Core/Runner.luau
One active run, bounded setup, synchronized phases, repeat trials, cleanup,
validity checks, diagnostic collection and comparisons. Start returns immediately.
Run starts and yields for the report; Await waits for an existing run and any
automatic Script Profiler attachment. A timeout returns nil plus pending state,
without cancelling. Use short Await slices for tools with call time limits.
Controlled trials call the configured BeforeTrial/Validate/AfterTrial adapter;
manual recording does not. Cleanup runs on success, cancellation and errors.

### Scenarios/Shared/Basic.luau
Manual observation and anchored stationary subject with state restoration.

### Scenarios/HotelOddities/Support.luau
Streaming handshake, character position/anchor restoration, route scope and
workload checks. Depends on Hotel HallwayStreamingService.

### Scenarios/HotelOddities/Lifecycle.luau
Pauses the director, vent encounters and programmatic vent churn for every
controlled trial, including stationary/UI. Blocks ambient EnemyService spawns,
cancels Chaos warnings and clears live enemies plus ceiling walk-in rigs.
Waits for deferred enemy removal before measurement. Grants only the encounter
fixture a scoped spawn function. Checks enemy count and no walk-ins, and releases
all pauses on cleanup. Encounter state is cleared, not restored; normal spawning
resumes. Lifecycle id/version must match for baseline comparison.

### Scenarios/HotelOddities/Pack.luau
Five fixtures: two hallway views, streaming route, harmless Chaser pursuit,
inventory/index/closed pages, and repeated maze/lobby transfers. Despawning
ambient enemies resets encounter state; use an isolated test server.

### ServerGuide.luau
Comment-only access and installation notes. The shared folder contains the full
usage and authoring guides; no profiling instructions are added to PLAYTESTING.md.
