# ReplicatedStorage / Profiler

Portable client/shared half. Copy this folder together with `ServerStorage.Profiler`,
then call each Bootstrap from the matching init. Remove both HotelOddities packs
for other games. No Core, UI or collector depends on Hotel services.

### Bootstrap.luau
`Start()` returns `Open()`, `Command(table)` and `Export(id, format)` on the client.
Reuses the existing PlayerGui bridge across MCP/game require contexts.
Remotes: owns `Profiler.Transport`, created by the server. Tags: none.

### Config/Settings.luau
Version, defaults, timeouts, bounded sample counts, report retention and chunk size.

### Core/Statistics.luau
Finite streaming moments, bounded exact samples, nearest-rank percentiles and slope.

### Core/Scope.luau
`Begin/End`, `Wrap(name, function)` and `Count`; preserves methods, nil returns,
yields and errors. Records elapsed wall time, not sampled CPU. Inactive scopes
skip collection. Call from game code in the same context as the collector.

### Core/Context.luau
Scenario state, checks, events, bounded waits and reverse-order cleanup.

### Core/Registry.luau
Discovers packs returning `Scenarios`, lists metadata, detects duplicate IDs.

### Core/Options.luau
Validates duration, warmup, repeat count, focus, mode, labels and scope filters.

### Core/Environment.luau
Place, engine, viewport, quality, device/build labels and declared run conditions.

### Core/Phase.luau
Shared synchronized warm measurement loop; stops and disconnects collectors.

### Core/ClientSession.luau
Client scenario lifecycle, checks, diagnostics and cancellation cleanup.

### Core/ClientTransport.luau
Correlated commands and chunked exports share a bounded FIFO queue and a minimum
send interval. Only explicit `busy`/`throttled` replies retry; a timeout never
replays a command that may already have changed state. Errors release pending
entries and the queue so later commands can recover.

### Core/Report.luau
Focused text report for an LLM; JSON preserves full retained samples.
Compact baseline JSON omits raw samples and diagnostics for cross-session imports.
`Format` uses the compact summary; `Detailed` preserves per-trial detail.

### Core/Summary.luau
Groups repeated phases by side, retains trial FPS/p95/duration and worst p99,
sample-weighted metric means and peaks, memory trends, scope costs, failures,
availability and warnings. Passing checks become a count; routine events remain
in details/JSON. Diagnostic snapshots retain their trial identity.

### Core/MetricDeltas.luau
Computes before/after absolute and percentage changes for every matching phase
metric, using equal-weight trial means. Summary shows the 16 largest percentage
changes; details/JSON retain all. Zero baselines have no percentage. Deltas explain
tradeoffs and do not replace workload validity or confidence checks.

### Core/Compare.luau
Pass/fail/inconclusive/invalid decisions. Requires matching controlled score runs,
five trials, workload validity and frame-tail/memory/server-work guardrails.
Uses an approximate trial-level confidence interval; adaptive optimization still
needs a fresh confirmation batch under fixed conditions.

### Collectors/Runtime.luau
Frame cadence, CPU/GPU engine counters, physics, memory categories and trend,
network/ping, instance churn, scopes, collection cost and availability flags.

### Collectors/MicroProfiler.luau
LibMP recent-frame capture with bounded traversal and focused inclusive CPU/GPU
scope summaries. Diagnostic only; inclusive times overlap.

### Collectors/Scene.luau
Capability-probed Scene Analysis snapshots with top leaf paths and original units.

### Collectors/Scripts.luau
Capability-probed Script Profiler capture; normal scripts may lack permission.

### Studio/Driver.luau
`Run(scenario, options, player?)` uses the MCP/plugin context for automatic Script
Profiler capture and attaches results to the shared diagnostic run.
Captures one trial, stopping before LibMP decoding and scene snapshots.

### UI/Panel.luau
`/profile` panel, scenario/focus controls, run/cancel, text selection, JSON import,
baseline and comparison. Hides once at run start and reopens after a UI run.
Reopening during a run stays open across phases/trials for stop/cancel. An open
panel during measurement invalidates scoring because its UI adds work.
No launcher button or F6 shortcut. Programmatic Open remains available.
Repeated opens share one scenario lookup and cache the result. Lookup and report
errors stay in the panel; a failed first lookup can retry on the next open.

### Scenarios/Shared/Basic.luau
Manual observation and fixed-camera stationary scenarios without game services.

### Scenarios/HotelOddities/Config.luau
Versioned world coordinates for hallway, route, enemy and lobby fixtures.

### Scenarios/HotelOddities/Pack.luau
Client views, streamed-floor checks, survival checks and visible inventory/index
pages. Depends on Hotel InterfaceService only inside the UI scenario.

### Tests/Core.luau
`Run()` checks statistics, scope semantics, cleanup, inputs and comparison decisions.

### Tests/Transport.luau
`Run()` checks concurrent commands, reply correlation, safe busy retries, lost
mutation replies, send failures, access denial, retry deadlines and recovery.

### Tests/Reports.luau
`Run()` checks report size, failure/outlier preservation, warnings, immutability
and signed metric deltas including a zero baseline.

### UsageGuide.luau
Comment-only installation, human/MCP workflow, export, testing and interpretation.
Do not require it.

### AuthoringGuide.luau
Comment-only scenario, collector and instrumentation contracts for future authors.
Do not require it.

### Vendor/LibMP.luau
Pinned upstream Roblox LibMP distribution. See adjacent README for provenance.
