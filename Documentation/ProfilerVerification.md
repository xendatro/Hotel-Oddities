# Profiler verification — 2026-09-19

Tested in the connected Hotel Oddities Studio place, using the real server/client
transport. These are functional checks, not a claim about production FPS or
performance on phones. No optimization percentage is claimed.

- All 36 Luau modules parse, including the pinned LibMP distribution.
- Eight core test groups passed in Studio: statistics, bounded samples, method
  and return-value preservation, errors, timed scopes, cleanup, options and
  comparison pass/fail/invalid/inconclusive cases. A yielding function measured
  at least 20 ms and exceeded its undelayed control by more than 15 ms.
  Compact baseline export retained a passing comparison and left raw data intact.
- Stationary, hallway, streaming, enemy, UI and reentry scenarios all completed
  with valid workloads. The first client phase retained 397–505 frame samples
  in each four-second run. See `ProfilerVerification.json` for checks and IDs.
- The route reached its endpoint and recorded 1,394 `Hotel.Route.Pivot` calls,
  with a measured mean of 0.111 ms. The Chaser moved 53.27 studs and pursued
  the subject. These establish that work happened; the timings are not baselines.
- Scene Analysis returned triangle/draw-call composition and script, instance,
  animation, audio and unparented-object attribution.
- Paused LibMP snapshots parsed on client and server. In this Studio process,
  both sides returned the same capture; reports label the process-wide scope.
- Automatic Script Profiler returned client and server function names, source
  paths and times. Raw JSON durations are microseconds; DeserializeJSON changes
  them to seconds. The adapter converts those seconds to milliseconds.
  The final capture stopped before diagnostic processing; game functions such
  as RigMotion, EyeRenderService and NpcAnimator replaced decoder work in the top
  results. Studio plugin work may also appear, identified by its source path.
  See `ProfilerDiagnosticVerification.json` for the final captured results.
- The real UI Run button completed a manual recording and reopened its report.
  Format switched to valid JSON; Select selected all 64,884 characters. Six
  server chunks reconstructed the same report. JSON import worked; malformed
  import left report history unchanged. Manual data could not pass comparison.
- The authorized Profile launcher opened the panel through simulated mouse
  input. A 350×600 panel used two columns with all controls and a scrollable report.
- Cancelling a route restored character anchoring to false and camera mode to
  Custom; the report said cancelled/invalid with a successful cleanup check.
- Stopping a 20-second, three-repeat stationary test after about one second
  stored one trial, failed its full-duration check and marked the report invalid.
- Both server and client Request/Response JSON bridges returned matching
  request IDs. MCP and native game scripts reported the same active run after
  the shared BindableFunction bridge fix.

The initial chat attempt did not complete. A later fresh-session test sent
`/profile` through RBXGeneral and observed the panel open. The Profile launcher
and F6 shortcut were subsequently removed at the user's request; programmatic
Open remains. Physical mobile/controller input and a published server were
not tested. Portability was checked through dependency separation and shared
scenarios here, not by publishing the package into a second game.

Testing found stale PLAYTESTING.md claims about require and globals; those were
corrected there. Usage and authoring instructions live in comment-only scripts
inside Profiler. Existing game console errors from TagService permissions and
Chaos route selection were observed separately from these checks.

## Command timeout regression

The old server silently discarded requests within its 40 ms rate limit or
while another command was in flight. A 20-command burst received only one
reply. Ten concurrent panel opens reproduced nine `Profiler server did not
reply` failures at ClientTransport:23, matching the reported stack.

With explicit server rejection replies, a paced client queue, and one shared
scenario lookup per panel, the same raw burst received all 20 replies: one
accepted command and 19 explicit pre-execution throttle rejections. Ten opens
mixed with ten regular commands all completed without error in 0.689 seconds.

Five new transport regression groups passed, alongside the eight core groups.
They cover serialization/correlation, safe busy/throttle retries, an executed
mutation whose reply is lost, late replies, send failures, access denial,
retry deadlines and subsequent recovery. No timeout automatically replays a
mutation. Injected panel lookup and export errors stayed in the status label;
retry restored the scenario list and report without rebuilding the panel.
A real UI run then completed with 394 client frame samples, reopened its report,
and exported 65,994 bytes of valid JSON while ten status requests ran concurrently.

## Lifecycle, compact reports and yielding calls

Further checks on 2026-09-19 passed 8 core groups, 5 transport groups and 7 report
checks. All 44 non-vendor package/service files compiled with luau-compile.

- A native service test found 8 ceiling walk-in rigs, acquired nested vent
  pauses, and observed 0 rigs. Forced spawns stayed blocked after one lease was
  released, and resumed after the last release. Enemy spawn blocks rejected
  ordinary spawns, permitted their fixture capability, rejected nested/expired
  capabilities and allowed normal spawning after release.
- An early temporary test Script destroyed itself immediately after calling
  despawn. Deferred removal did not finish in that session, so it was discarded.
  The final benchmark checks below ran in a fresh session without that probe.
- Run returned a completed, valid Chaser report after 12.09 seconds. It confirmed
  pursuit, 76.98 studs of movement, the expected enemy count, no ceiling walk-ins,
  and successful cleanup. A short Await timeout returned pending without
  cancelling; another Start was rejected while its run was active.
- Five 5-second streaming trials completed with valid=true and no failed checks.
  Formatting the same valid report produced 22,684 bytes / 7,982 tokens in the
  old detailed format and 4,540 bytes / 1,715 tokens in the summary. Tokens use
  tiktoken o200k_base; other model tokenizers vary. The saved texts are in
  ProfilerSummaryMeasurement.json. The reduction is 78.5% by that tokenizer.
- A reopened panel stayed visible across phases. Scored reports recorded an
  explicit panel-open invalidity reason. In a fresh session `/profile` through
  RBXGeneral opened the panel and no ProfilerLauncher existed. The actual Run
  button hid the panel and completion reopened it. On a controlled hallway run,
  `/profile` reopened it and the actual Cancel button produced cancelled/invalid
  with cleanup passed, character unanchored and camera restored to Custom.
- A 107,489-byte baseline export imported successfully. Comparing it against
  the same measurements reported 0% change and correctly failed the +15% target.
  Synthetic tests verified GPU 4 to 3 ms is -25%, zero-baseline percentages stay
  undefined, and lifecycle changes reject comparisons.
- Await on an automatic Script Profiler diagnostic returned only after the
  completed report included scriptProfiler and its capture hook was removed.

These are functional checks, not evidence of an FPS gain. Studio was stopped
and the queue lease released after testing. Physical-device testing is still
required for performance conclusions about those devices.
