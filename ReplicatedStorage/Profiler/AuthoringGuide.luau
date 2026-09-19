--[[
ROBLOX PROFILER: EXTENDING THE SYSTEM
This file is documentation only. Do not require it.

BOUNDARIES
Portable code must not require game Services, Configs, Playtest helpers, UI
frameworks or tagged scene objects. Put those dependencies in Scenarios/<game>.
Keep server-only actions under ServerStorage. Ship both folders together.
Do not introduce global script wrappers, monkeypatches or per-frame tree scans.

SCENARIOS
Matching client/server packs return {Scenarios={definitions...}}. Other modules
in a pack may return helpers. Requiring a pack must have no scene side effects.
A definition has Id, Name, Version, Description, Focus, Controlled, Phases and
optional Prepare(ctx), PreparePhase(ctx,phase), Step(ctx,phase,elapsed,dt),
ValidatePhase(ctx,phase), Validate(ctx). All helpers may use ctx.State.
The server may send serializable Roblox values through ctx.ClientData in Prepare.
The client receives them at ctx.State.Data.

Prepare creates a known start state. Register ctx:Defer(undo) before each change.
PreparePhase waits for actual readiness before warmup. Step executes measured
actions, so its cost is part of the workload. Validate must observe effects:
route distance reached, enemies moved, visible UI, tasks completed. Checking a
property you just assigned is not sufficient. A failed check makes the run invalid.
Cleanup always runs in reverse order. Keep it bounded, idempotent and non-yielding
where possible. Use ctx:WaitFor(predicate,seconds,label) and ctx:Sleep(seconds)
so cancellation works. A scenario must not write player progress or purchases.

Use stable geometry/seeds/workloads, state assumptions in Description, and bump
Version whenever actions, validation or workload semantics change. Set a stable
ctx.State.Signature on the client for starting pose/route/configuration. It is
part of comparison compatibility. A seed field alone does not seed game RNGs.
If you cannot control the workload, set Controlled=false. DiagnosticOnly=true
can reject score mode. Game-specific visual changes need visual checks too.
Do not change scenario validity rules to make an optimization pass.

GAME LIFECYCLE
Server Config/Lifecycle selects an adapter in Scenarios/<game>/Lifecycle.
BeforeTrial(ctx,definition) runs before each controlled scenario's Prepare;
Validate(ctx,definition) checks the resulting workload. AfterTrial runs last
during cleanup, including failed setup/cancellation. Manual gameplay skips it.
Register ctx:Defer for each acquired pause before taking the next action.
Wait for despawn completion before measuring. Include harmless warning rigs,
pending spawn tasks and encounter animations, not just active enemy registries.
Give scenario fixtures a scoped spawn capability rather than opening ambient
spawning globally. Bump lifecycle Id/Version when isolation changes so old
baselines cannot claim a gain merely from removing workload.

FUNCTIONS AND METHODS
  local Scope = require(game.ReplicatedStorage.Profiler.Core.Scope)
  local solve = Scope.Wrap("Navigation.Solve", function(request) ... end)
  MyClass.Method = Scope.Wrap("Navigation.Method", function(self, arg) ... end)
Wrap a definition at authoring time. It preserves arguments, nil returns,
multiple returns and error propagation. When recording is inactive it calls
the original directly. Do not replace a shared service method during a run.
For part of a function: token=Scope.Begin("Navigation.Search"); Scope.End(token).
Always close a token on error paths, or prefer Wrap. Count(name,n) records work
volume. Call counts distinguish less work from faster work. Use low-cardinality
names, never one name per player, object or frame. scope prefixes in run options
filter recorded names. The recorder enables scopes only for all/functions focus.
These are wall timers, including yields and nested work. For CPU attribution use
Script Profiler or named debug.profilebegin/end scopes in non-yielding code.

COLLECTORS
Declare the source, unit, side, cadence and availability of every metric. Public
API access must be guarded where it varies by device/permissions. Do not treat
missing values as zero. Keep frame sampling cheap and bounded. Gather counters
less often. Take expensive scene snapshots and analyze traces after measurement.
Retain useful summaries and top contributors, plus an optional detailed export.
Do not mix CPU/GPU tick scales, add overlapping scope totals, or call CPU render
time total script CPU. A new field should answer a concrete question a user or
LLM could act on. Respect focus when adding output. Label inference separately
from measurements. Compare collector overhead with and without the collector.

TESTS
Test error/cancellation cleanup, nil/multiple returns, yielding callbacks,
missing permissions, no client response, invalid options, bounded storage and
bad comparison inputs. Integration tests must exercise real transport, actual
actions and exported reports. Add fixtures showing a true improvement and a
faster-but-broken workload. A failed workload must never pass comparison.

TRANSPORT
Use ClientTransport.Command for every UI command, including report chunks.
Never silently discard a valid command token: reply even when rejecting it.
Only pre-execution busy/throttle replies may be marked retryable. A missing
reply to start/import does not mean the command failed to execute. Do not
automatically replay mutations after a timeout. Keep UI errors recoverable.
]]
