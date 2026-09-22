# Playtesting

Helpers for driving and measuring a Studio playtest, plus what this project has
already learned the hard way. **Read this before every playtest.**

`ReplicatedStorage\Playtest` and `ServerStorage\Playtest` are deliberately
outside the architecture rules in `CLAUDE.md`. They are not Services or Classes,
they take no particular shape, and they are not listed in `README.md` or
`Documentation\`. They only have to be useful and callable from a playtest.

**Keep this file current.** When you add a module, document it here. When
something here turns out to be wrong, fix it in place.

**Gotchas are for playtest technique, not bug findings.** Add one only when all
of these hold:

- it is about *running* a playtest: driving Studio, measuring, the MCP, the test
  harness, or a trap that makes a correct result look wrong (or the reverse);
- it will bite a future playtest that has nothing to do with the bug you were
  chasing;
- it cost you real time to figure out, and you could not have found it by
  reading the code.

What a playtest revealed about the game itself, such as a bug's cause, how a
system behaves, or an engine quirk behind one fix, belongs in the fix, its commit
and the docs, not here. A finding that only matters inside one room, one POI or
one enemy is too narrow to earn a line. If you are unsure, leave it out.

**Tag every Gotcha with how it was established**, and keep the observation and
the explanation in separate sentences so the explanation cannot borrow the
observation's confidence:

- **`Measured`** for an experiment that isolated it. State the number or the
  method, so it can be re-run and falsified.
- **`Observed`** for something that happened with evidence, where the cause is a
  guess or it has not reproduced. Say what was seen, and mark any mechanism as
  unconfirmed.
- **`Inferred`** for something read out of the source or carried in from
  elsewhere, never tested here.

If you lean on an `Observed` or `Inferred` entry and it costs you time, that is
the moment to measure it, then promote or delete it. Correct wrong entries in
place. Only keep a record of the wrong belief when it is the intuitive one that
someone would otherwise re-derive.

**A negative result is not a refutation until you have reproduced the original
setup.** Two of the entries below were reported as "did not reproduce" by a run
that had changed the route or the goal. Before you delete an entry, get the
stated conditions back and fail there.

---

## The one rule

**Never assert on a value the code just wrote. Measure the effect, and measure
it again with the effect absent.**

Reading back `player.Volume == 2`, `fader.Volume == 1` or `IsPlaying == true`
proves the write landed. It does not prove anything is audible. The same applies
to a tween's goal versus the rendered position, a `Highlight` existing versus
being visible, or an attribute being set versus the client having acted on it.
`Recorder.compare` and `Probe.compare` exist to make the two-sided measurement
the easy path.

---

## Modules

### ReplicatedStorage\Playtest\Recorder.luau
Named sample streams that run until you stop them. Samples live in a module
upvalue, so they survive a character respawn (they do not survive stopping the
play session).

- `Recorder.start(name, sampler, interval?)`. `sampler` returns a table of
  fields per tick; `t` is filled in with `workspace:GetServerTimeNow()` if you
  omit it. The sampler is wrapped in `pcall`, and failures are counted rather
  than killing the run.
- `Recorder.stop(name)` / `Recorder.stopAll()` / `Recorder.discard(name)`
- `Recorder.list()` for running state, sample counts and the last sampler error
- `Recorder.dump(name, filter?)` for per-field `n / mean / min / max / sd`
- `Recorder.compare(name, field, predicate)` for that field's stats for rows
  matching the predicate versus the rest. This is the assertion you usually want
- `Recorder.rows(name, format, filter?, limit?)` for formatted lines, evenly
  strided down to `limit` (default 40) so a long run stays readable. `format` is
  a **function** taking one row and returning a string, not a format string. Pass
  a string and every line comes back as `format error: attempt to call a string
  value`
- `Recorder.samples(name)` for raw rows

Give the sampler a long life and stop it explicitly. Fixed deadlines expire
while you are still reading the previous batch.

### ReplicatedStorage\Playtest\Probe.luau
Client-side measurement of what the player actually perceives. Every entry point
calls `Probe.assertClient()`, so a Server snippet gets a clear error rather than
a silent zero.

- `Probe.attachToCharacter(player?)` pins the listener to the character and
  returns a restore function. See Gotchas
- `Probe.listenerDistance(player?)` for listener-to-character distance. Check
  this before believing a level reading
- `Probe.listener()` / `Probe.audio()` for the `AudioListener` and an
  `AudioAnalyzer` wired to it (created once, reused)
- `Probe.level()` for current RMS
- `Probe.window(seconds, interval?)` for `n / mean / max` RMS over a window
- `Probe.compare(seconds, action)` to window, run `action`, then window again.
  `action` may return an undo function
- `Probe.emitters(root?)` for every `AudioEmitter` under `root` with volume,
  playing state, attenuation bounds and mode

### ReplicatedStorage\Playtest\Wait.luau
- `Wait.For(predicate, timeout?, interval?)` returns `ok, elapsed`
- `Wait.Value(getter, timeout?, interval?)` returns `value, elapsed` (waits
  non-nil)
- `Wait.Child(parent, name, timeout?)` returns the instance only, with no second
  return value
- `Wait.Gone(instance, timeout?)` returns `ok, elapsed`

Timeout defaults to 30 seconds. Use these instead of fixed sleeps.

### ServerStorage\Playtest\Quiet.luau
Silences the map so a long test is not interrupted. Call it once at the top of
any playtest that scripts the camera or takes screenshots. **This is the only
enemy clear that works from an MCP snippet.**

- `Quiet.on()` clears every live enemy, cancels pending Chaos warnings, takes an
  `EnemyService` spawn block and starts a 0.5 s sweep that keeps clearing.
  Idempotent; call it again mid-test to read the running totals
- `Quiet.off()` stops the sweep and releases the spawn block
- `Quiet.state()` returns `active`, `sweeping`, `tagged` (live enemies by tag),
  `serviceActive` (what `EnemyService` thinks is alive), `clearedTotal`

It sweeps on the `Enemy` **tag**, not `EnemyService:GetActive()`, which is why it
works from a snippet at all. The spawn block it takes does not work from a
snippet, so the director keeps spawning and the sweep keeps deleting: expect
`clearedTotal` to climb for as long as the test runs. `state().tagged` counts
only tagged models still parented under `workspace`, so it reads lower than a
raw `CollectionService:GetTagged("Enemy")` count.

### ServerStorage\Playtest\Subject.luau
Turns a player into a stable test subject.

- `Subject.setup(player, position?)` returns `cleanup, clearedInfo` after
  applying invincibility, optional pinning, and an enemy clear
- `Subject.invincible(player)` / `Subject.mortal(player)`, which survive respawn
  and re-arm on `CharacterAdded`
- `Subject.hold(player, position, interval?)` / `Subject.release(player)`
- `Subject.clearEnemies()` despawns everything alive and cancels pending Chaos
  warnings. It does **not** stop the director spawning more, and it clears
  **nothing at all** when called from an MCP snippet. Use `Quiet.on()` instead
- `Subject.first()` for the first player, which in a solo playtest is the subject

---

## Gotchas

**`Measured`** — **an MCP snippet gets its own copy of every module it
requires.** `require` works in Edit, Server and Client, and the copy is shared
between MCP snippets: the same module returned the same table address across
separate calls. It is not the copy the game scripts hold, and nothing warns you.
Measured on 2026-09-22: `EnemyService:GetActive()` returned 0 while 22 models
carried the `Enemy` tag, and `Subject.clearEnemies()` returned `despawned = 0`
and left all 16 live enemies walking. The symptom is silence, not an error, so it
is easy to miss. Consequences:

- `CollectionService` tags and instance properties are on the instances
  themselves and are shared, so they are the reliable handle from a snippet.
- `Quiet.on()` is the only working enemy clear from a snippet, and only because
  it sweeps by tag. Its `AcquireSpawnBlock()` lands on the snippet's copy and
  does nothing to real spawning.
- Do not monkeypatch a product module to observe it. The patch runs inside your
  copy, so it never sees the real call. Worse, a throwing patch once aborted
  `ensureAnchor` partway and left half-built state that looked like a genuine
  bug. Observe instances and properties instead.
- A self-starting module required from both a game script and a snippet runs
  twice: client folders duplicated, and the two copies reported different state.
  Reach the live runtime through a BindableFunction if you need it.

**`Measured`** — **Client and Server are separate datamodels, but `_G` persists
across snippets within one.** `typeof(_G)` is `table` in Edit, Server and Client.
A marker set from a Server snippet does not exist on the Client. Within one
datamodel it carries: on 2026-09-22 a marker, a live connection and its results
table all came back in the next snippet. Nothing survives restarting the play
session. Module upvalues behave the same way, which is usually what you want.

**`Measured`** — **MCP-driven play sessions do render.** `RenderStepped` and
`BindToRenderStep` both fire, and the camera follows a server-side
`Character:PivotTo`, including after a death and respawn, settling 1.70 studs
from the character. Both fired at 61 fps on 2026-09-22 with the Studio window
focused; Roblox throttles an unfocused window to about 15 fps, so a frame rate
measured without the window in front is not the session's real rate. The listener
sat 1.699 studs out at the same moment. It has been seen wrong once
(`AudioListener` ~296 studs from the character, cause unknown, never reproduced),
so if a level reading looks impossible, check `Probe.listenerDistance()` before
believing it. If a pivot stops moving the camera, re-read `player.Character`
rather than trusting the reference you cached, because the character may have
been replaced under you; this mechanism is unconfirmed.

**`Measured`** — **the workspace streams, so a distant instance reads as empty
on the client.** `workspace.StreamingEnabled` is true. On 2026-09-22 three models
parented 500 studs above the player arrived at the client's `ChildAdded` with 0
descendants and still had 0 a minute later, while the same models built at the
character's feet arrived complete, 10 of 10 descendants, three out of three
times. Build any client-side control near the player, and do not read an empty
model as a replication bug. The same measurement means Studio playtests do not
reproduce split replication inside the streamed region, so to test code against a
subtree that arrives in pieces, detach a child on the client, reparent the root,
then restore the child.

**`Measured`** — **an instance the client destroyed locally does not come back.**
On 2026-09-22 the client destroyed its copy of a replicated model, then the
server reparented that same instance out of `workspace` and back; it stayed
absent on the client while an untouched sibling remained. A control built that
way reads as "hidden" whatever the code does. Build the control from a fresh
instance.

**`Measured`** — **never call `WaitForChild` without a timeout in an MCP
snippet.** A call for a nonexistent child was still pending after 8 seconds,
while the one-second timeout form returned `nil` on schedule. An infinite yield
hangs the snippet for its full tool timeout.

**`Measured`** — **chat commands can be run from a Client snippet.**
`TextChatService.TextChannels.RBXGeneral:SendAsync("/enemies")` returned in 4 ms
on 2026-09-22 and the server printed its `[enemies]` reply, so the call reached
`ChatCommandService` through `Player.Chatted`. Use this to undo persistent
progress a playtest wrote, since Studio profiles save between runs. One earlier
`SendAsync` call did not return after several minutes and its cause is
unconfirmed, so keep the call in a bounded spawned thread and inspect the effect
rather than the return.

**`Observed`** — **script sync can stop pulling disk edits into Studio.** On
2026-09-12, edits to `NPC.luau` and `Peek.luau` on disk never reached the Studio
copies after 20+ seconds, so a playtest would have run the old code. The cause is
unconfirmed. Before a playtest, `find` a string from your edit in the script's
`Source` from the Edit datamodel. If it is missing, apply the same replacements
to `Source` there. The byte-count check is exact (`Measured` 2026-09-22): an
LF-ending file matched `#Source` to `wc -c` exactly, and a CRLF file matched
after subtracting one per line, 52072 bytes minus 1652 lines equals the 50420
Studio reported.

**`Measured`** — **a minimized Studio window makes `screen_capture` return a
black 3D scene with the ScreenGui layer still drawn.** Reproduced in both
directions on 2026-09-22: `ShowWindow(h, 6)` then a capture gave a fully drawn
HUD over pure black, and `ShowWindow(h, 9)` plus `SetForegroundWindow(h)` gave
the same camera rendering normally. `IsIconic` on the main window handle is the
check; `ffmpeg -f gdigrab -i title="Hotel Oddities - Roblox Studio"` refusing the
window with "Invalid properties" is the cheaper tell. A black capture is not
evidence the scene is unlit.

**`Observed`** — **stopping and starting play is not instant.** Starting
immediately after stopping can fail with "Stop play hasn't finished yet"; retry.
Reparenting instances the client is mid-way through using has also dropped the
client bridge, losing recorder state with it.

**`Inferred`** — **`FLAGS.Director` is read once at require time.**
`EnemyDirectorService` returns early at module scope if the flag is off, so
flipping it mid-session does nothing; edit `ReplicatedStorage\Configs\FLAGS.luau`
before starting the session. An ambient enemy wandering through the area under
test can look exactly like a product bug.

**`Inferred`** — **enemy spawning already has commands.**
`ServerStorage\Services\EnemyCommandService` registers chat commands and wraps
the spawn paths, including `ChaosService:SpawnThrough` and `Commands.despawn()`.
Check it before hand-rolling a spawn call.

**`Measured`** — **`MapCommandService:Execute` lands the player inside a spawn
safe zone.** On 2026-09-22 the command left the character at
(589.6, -19.6, -622.2) with `SpawnZoneService:Contains` true, the
`SafeZoneImmunity` and `Ignore` tags set and `Vanished.Is` true, which makes
every enemy treat the player as an invalid target: a Stalker spawned 14 studs
behind sat in `Patrol`, and a peek sequence ended straight in `Despawn`. Pivot
the character onto a `HallwayGraphService:Get()` node outside
`SpawnZoneService:Contains`, which cleared both tags within a second, and check
`Vanished.Is` before spawning anything.

**`Measured`** — **`Humanoid.MoveDirection` reads 0 for NPCs on the server.** A
patrolling Chaser sampled 40 times over 6 s covered 62.3 studs with
`AssemblyLinearVelocity` peaking at 10.7, and `MoveDirection.Magnitude` was
exactly 0 on every sample. Sample `RootPart` displacement or
`AssemblyLinearVelocity`, and `Humanoid.WalkToPoint` for what it was told to walk
to. Give the enemy a real distance to cover before you sample: half a stud of
drift proves nothing either way.

**`Measured`** — **a `math.huge` entry in `AgentParams.Costs` inverts the cost.**
With `Costs = { Room = math.huge }` a path from the corridor into a safe room
returned `Success`; the same path with `Room = 1e6`, `Room = 1e5`, `Room = 1000`
or no `Costs` at all returned `NoPath`. Use a large finite number, as
`EnemyConfigs` does. The mechanism inside `PathfindingService` is unconfirmed,
but the comparison reproduces. **It only reproduces when the goal is inside the
labelled volume, at floor height.** Aiming at the door approach instead of the
room interior, or taking Y from a door pivot rather than the floor, returns
`NoPath` under all four settings and proves nothing.

**`Measured`** — **the navmesh puts waypoints closer to a `RoomBlocker` than the
agent can stand.** How close depends on the route: two approaches to the
`Room_727` door put their nearest waypoint 0.87 and 3.08 studs from the blocker
surface against an `AgentRadius` of 2.50, so on the first the body cannot occupy
the waypoint at all. It is independent of `Costs`, since all four cost settings
produced an identical distance on the same route. `NPC:_walkPath` therefore skips
waypoints that fail `HasMovementClearance`; before that it walked at them and ate
a full eight-second `MoveToFinished` timeout each time.

**`Measured`** — **an enemy standing on a stranded patch of the hallway graph
used to be stuck there permanently.** `Patrol` picks its home with
`FindNearestNode`, which is a nearest-position scan and happily returns a node in
a pocket that connects to nothing: at (508, -23, 134) it returns a node 0.6 studs
away with `WellConnected = false`, while the same call with `wellConnectedOnly`
returns one 23.1 studs away. 20 of the graph's 361 nodes are not well connected.
`Patrol` passes `wellConnectedOnly`, and spawning a Chaser on that pocket now
walks it off within a second and 387 studs across the map in 40 s. If patrol ever
freezes again, print that flag for the enemy's nearest node first.

---

## Adding a module

Put shared or client-side helpers in `ReplicatedStorage\Playtest`, server-only
ones in `ServerStorage\Playtest`. Return a plain table of functions. No
particular style is required, but keep each module to one job so a snippet can
require just what it needs.

Add it to Modules above with its signatures, and note anything surprising about
it in Gotchas.
