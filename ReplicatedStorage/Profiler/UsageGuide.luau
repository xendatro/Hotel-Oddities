--[[
ROBLOX PROFILER: USE AND PLAYTEST GUIDE
This file is documentation only. Do not require it.

INSTALL
Copy ReplicatedStorage.Profiler and ServerStorage.Profiler together. Start each
half from the corresponding init script:
  server: require(game.ServerStorage.Profiler.Bootstrap).Start()
  client: require(game.ReplicatedStorage.Profiler.Bootstrap).Start()
Remove both Scenarios/HotelOddities packs when moving to another game. Core,
Collectors, UI, Studio, Tests and Vendor have no Hotel dependencies. Server
Config/Lifecycle selects the game adapter and falls back to no-op without it.
LibMP is vendored so published clients do not depend on Studio's @rbx shortcut.
ServerStorage.Profiler.Config.Access controls authorized users and group roles.
Controlled scenarios are restricted to Studio/private servers by default.

HUMAN WORKFLOW
Type /profile. Choose a scenario, focus and score/diagnostic mode. The four
top controls are drop-downs; the selected choice is marked. History lists
saved reports newest first with scenario, build, timestamp and status. Select
a report to load it. Click outside a menu or press Escape to dismiss it. The four
fields are seconds per phase, repeat count, build label, device label. Run hides
the panel once at start. It reopens with the report. Reopening with /profile
during a run keeps it visible so Stop/Cancel remain usable. An open panel adds
rendering work and invalidates that measurement. Select text then copy using
the device's text controls. Format cycles summary/details/JSON/baseline.
Baseline is compact JSON with the same comparison metrics and checks, without
raw samples or diagnostic snapshots. Use it to carry baselines between sessions;
large full-detail reports may exceed the 2 MB import limit. The text box
also accepts pasted JSON: Import pasted JSON stores it as the baseline.
Set baseline remembers the selected run; run another build and use Compare.
Reports are session-local and limited to the last 12. Export before stopping
Studio or leaving the server. Imports are trusted developer data, not proof of
where a run was made. Do not paste a summary into the JSON import.

LLM / MCP WORKFLOW
Use the correct connected Studio and datamodel. Start play, then in Server:
  local api = require(game.ServerStorage.Profiler.Bootstrap).Start()
  return api:Command({action="list"})
Start is asynchronous and returns a run ID immediately:
  return api:Start("hotel.hallway", {
    duration=20, warmup=5, repeats=5, focus="all", mode="score",
    build="commit-or-worktree-label", device="test-device", frameCap="60"
  })
Run yields until completion by default:
  local report = api:Run("hotel.streaming", {duration=5,repeats=5})
For tools with a call time limit, start once and wait in bounded slices:
  local report, pending = api:Await(id, 20)
If pending is returned, repeat Await on the same id until report is non-nil.
Do not edit the measured code or begin another run while pending. Await timeout
does not cancel. Start refuses concurrent runs. Both methods wait for cleanup
and automatic Script Profiler attachment. Use the BindableFunction/proxy for
Await; the JSON Request/Response bridge only carries its first return value.
Alternatively poll Status. When idle, api:Command({action="getReport",id=id}) returns
the structured report on the server. Do not reach into module internals: MCP
and game scripts can have separate require caches. Bootstrap routes through
the existing runtime's BindableFunction so they control the same run.
Get compact output with api:Command({action="result",id=id}). It returns text,
nextOffset and totalBytes. Fetch subsequent chunks using offset=nextOffset.
Use format="json" for raw frame samples, slow metrics, checks and diagnostics.
Use format="baseline" for a compact, importable comparison record.
Use format="details" for all per-trial text. Default summary combines repeated
metrics, keeps per-trial cadence and failures, and leaves raw data in JSON.
Compare includes per-metric before/after deltas. Summary lists the 16 largest
percentage changes; detailed exports retain all. These deltas alone do not
establish a significant gain. Export a baseline before stopping Studio, change
code, restart, import that JSON, run the same scenario/settings/device, compare.
api:Cancel() cancels; api:Cancel(true) stops early. An early controlled run is
invalid. A failed run still stores its error and cleanup checks.

NO-REQUIRE BRIDGE
ServerStorage.Profiler.Runtime.Command is a BindableFunction accepting the
same command table. Alternatively write JSON with a unique requestId into
Runtime.Request, then read Runtime.Response in a later call. Results/<id>
contains Summary and numbered Json0001... chunks. ServerStorage never
replicates the control interface to players.
On Client, PlayerGui.ProfilerBridge.Request/Response offer the same commands;
{action="open"} opens the panel. Every network request is authorized server-side.

AUTOMATIC SCRIPT PROFILER
In a running Studio Server datamodel, invoke:
  return require(game.ReplicatedStorage.Profiler.Studio.Driver).Run(
    "hotel.hallway", {duration=10,warmup=2,focus="functions"})
This starts ScriptProfilerService from the MCP/plugin permission context and
starts one diagnostic trial. Capture stops before diagnostic processing so
LibMP decoding and Scene Analysis do not dominate the script profile.
After the run, wait for scriptProfiler
to appear on its stored report. Ordinary runtime permission failures are
reported as unavailable. Script profiles include setup/warmup; do not compare
their costs directly to only the scored measurement interval.

VERIFICATION
Run Tests.Core.Run() in Studio for statistics, function wrappers, cleanup,
option validation and comparison decisions.
Tests.Transport.Run() checks concurrent requests, bounded retries and recovery.
Tests.Reports.Run() checks compact output, retained failures and metric deltas.
UI commands queue automatically. A genuine timeout appears in the panel; reopen
it to retry a failed scenario lookup. Check status before retrying a start whose
reply was lost, because the server may already have started that run.
Test the full client/server path:
1. A short stationary run must finish with nonempty samples on both sides.
2. Run each game scenario and inspect every workload check, not just status.
3. Start a long run, cancel during measurement, and check that the original
   camera, character anchoring and game controls are restored.
4. Retrieve every JSON chunk, decode it, and check run IDs and sample counts.
5. Exercise a deliberately slow instrumented function and compare its measured
   wall time against the same function without the delay. Never accept a test
   that merely reads back a value it just set.
6. Open the UI, run through the actual buttons, select/copy text, and check its
   layout in a narrow viewport. Test on physical target devices before making
   claims about their speed. Studio emulation is not hardware performance.

INTERPRETATION
A valid run must complete, have client/server data, pass scenario and cleanup
checks, and have at least 10 frame samples per measured phase without dropped
or truncated samples, known focus loss, or the profiler panel visible. Controlled
phases must last at least 95% of the requested duration. Unknown initial focus
remains unknown, not proof of foreground execution. Optional unavailable
collectors do not alone invalidate a run. Valid manual recordings remain
observational and cannot support controlled improvement claims.
FPS is frames / summed RenderStepped intervals. Heartbeat Hz is not client FPS.
Scope durations include yielding; Script Profiler measures sampled CPU.
MicroProfiler scope sums are inclusive and overlap across threads/nesting.
Snapshots cover only recent frames. Scene memory attribution is a snapshot;
unparented instances or a positive memory slope do not alone prove leaks.
Studio MicroProfiler data is process-wide: client and server exports can share
the same capture, including editor work. Never add those copies together.
The diagnostic adapter takes control of MicroProfiler capture and disables it
when finished; do not run a separate capture at the same time.
Diagnostic mode adds overhead and is excluded from scored comparisons.
Focus=all supplies regression guardrails; narrower focus reduces report noise.
Unsupported measurements remain unavailable instead of becoming zeroes.
Comparisons require matching scenarios/settings/environments and five valid
trials per build. They use an approximate interval over trial summaries.
Keep a fresh confirmation batch after adaptive optimization. Do not keep
sampling until one lucky result passes. Fix graphics quality, frame cap,
foreground state, power state and workload before claiming an FPS improvement.
]]
