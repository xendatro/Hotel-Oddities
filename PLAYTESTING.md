# Playtesting

Helpers for driving and measuring a Studio playtest, plus what this project has
already learned the hard way. **Read this before every playtest.**

`ReplicatedStorage\Playtest` and `ServerStorage\Playtest` are deliberately
outside the architecture rules in `CLAUDE.md` — they are not Services or
Classes, they take no particular shape, and they are not listed in `README.md`
or `Documentation\`. They only have to be useful and callable from a playtest.

**Keep this file current.** When you add a module, document it here. When a
playtest teaches you something that would have saved you an hour, write it into
Gotchas. When something here turns out to be wrong, fix it. Do not record
one-off details of a particular bug — only what the next agent will need.

**Tag every Gotcha with how it was established**, and keep the observation and
the explanation in separate sentences so the explanation cannot borrow the
observation's confidence:

- **`Measured`** — an experiment isolated it. State the number or the method, so
  it can be re-run and falsified.
- **`Observed`** — it happened and there is evidence, but the cause is a guess or
  it has not reproduced. Say what was seen; mark any mechanism as unconfirmed.
- **`Inferred`** — read out of the source or carried in from elsewhere, never
  tested here.

If you lean on an `Observed` or `Inferred` entry and it costs you time, that is
the moment to measure it, then promote or delete it. Correct wrong entries in
place; only keep a record of the wrong belief when it is the intuitive one that
someone would otherwise re-derive.

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

- `Recorder.start(name, sampler, interval?)` — `sampler` returns a table of
  fields per tick; `t` is filled in with `workspace:GetServerTimeNow()` if you
  omit it. The sampler is wrapped in `pcall`, and failures are counted rather
  than killing the run.
- `Recorder.stop(name)` / `Recorder.stopAll()` / `Recorder.discard(name)`
- `Recorder.list()` — running state, sample counts and the last sampler error
- `Recorder.dump(name, filter?)` — per-field `n / mean / min / max / sd`
- `Recorder.compare(name, field, predicate)` — that field's stats for rows
  matching the predicate versus the rest. This is the assertion you usually want
- `Recorder.rows(name, format, filter?, limit?)` — formatted lines, evenly
  strided down to `limit` so a long run stays readable
- `Recorder.samples(name)` — raw rows

Give the sampler a long life and stop it explicitly. Fixed deadlines expire
while you are still reading the previous batch.

### ReplicatedStorage\Playtest\Probe.luau
Client-side measurement of what the player actually perceives.

- `Probe.attachToCharacter(player?)` — pins the listener to the character;
  returns a restore function. See Gotchas
- `Probe.listenerDistance(player?)` — listener-to-character distance; check this
  before believing a level reading
- `Probe.listener()` / `Probe.audio()` — the `AudioListener` and an
  `AudioAnalyzer` wired to it (created once, reused)
- `Probe.level()` — current RMS
- `Probe.window(seconds, interval?)` — `n / mean / max` RMS over a window
- `Probe.compare(seconds, action)` — window, run `action`, window again;
  `action` may return an undo function
- `Probe.emitters(root?)` — every `AudioEmitter` under `root` with volume,
  playing state, attenuation bounds and mode

### ReplicatedStorage\Playtest\Wait.luau
- `Wait.For(predicate, timeout?, interval?)` → `ok, elapsed`
- `Wait.Value(getter, timeout?, interval?)` → `value, elapsed` (waits non-nil)
- `Wait.Child(parent, name, timeout?)`
- `Wait.Gone(instance, timeout?)`

Use these instead of fixed sleeps.

### ServerStorage\Playtest\Subject.luau
Turns a player into a stable test subject.

- `Subject.setup(player, position?)` → `cleanup, clearedInfo` — invincibility,
  optional pinning, and clears live enemies
- `Subject.invincible(player)` / `Subject.mortal(player)` — survives respawn,
  and re-arms on `CharacterAdded`
- `Subject.hold(player, position, interval?)` / `Subject.release(player)`
- `Subject.clearEnemies()` — despawns everything alive and cancels pending Chaos
  warnings; does **not** stop the director spawning more
- `Subject.first()` — the first player, which in a solo playtest is the subject

---

## Gotchas

**`Measured`** — **MCP-driven play sessions do render.** `RenderStepped` and
`BindToRenderStep` both fire at ~33 fps, and the camera follows a server-side
`Character:PivotTo` — including after a death and respawn — settling ~1.7 studs
from the character. It has been seen wrong once (`AudioListener` ~296 studs from
the character, cause unknown, never reproduced), so if a level reading looks
impossible, check `Probe.listenerDistance()` before believing it.

**`Inferred`** — **`FLAGS.Director` is read once at require time.**
`EnemyDirectorService` returns early if the flag is off, so flipping it
mid-session does nothing; edit `ReplicatedStorage\Configs\FLAGS.luau` before
starting the session. `Subject.clearEnemies()` only clears what is already
alive. An ambient enemy wandering through the area under test can look exactly
like a product bug.

**`Observed`** — **do not monkeypatch product modules to observe them.**
Required module tables are shared, so a patch runs inside the real call. A
throwing patch aborted `ensureAnchor` partway and left half-built state that
looked like a genuine bug. Observe instances and properties instead.

**`Inferred`** — **enemy spawning already has commands.**
`ServerStorage\Services\EnemyCommandService` registers chat commands and wraps
the spawn paths, including `ChaosService:SpawnThrough` and `Commands.despawn()`.
Check it before hand-rolling a spawn call.

**`Observed`** — **Client and Server are separate datamodels.** Run each snippet
in the right one; `_G` is not shared between them and neither survives
restarting the play session. Module upvalues last as long as the datamodel,
which is usually what you want.

**`Inferred`** — **never call `WaitForChild` without a timeout in an
MCP-executed snippet.** An infinite yield hangs the call for its full timeout.

**`Observed`** — **stopping and starting play is not instant.** Starting
immediately after stopping can fail with "Stop play hasn't finished yet"; retry.
Reparenting instances the client is mid-way through using has also dropped the
client bridge, losing recorder state with it.

---

## Adding a module

Put shared or client-side helpers in `ReplicatedStorage\Playtest`, server-only
ones in `ServerStorage\Playtest`. Return a plain table of functions. No
particular style is required, but keep each module to one job so a snippet can
require just what it needs.

Add it to Modules above with its signatures, and note anything surprising about
it in Gotchas.

**`Measured`** — **a `math.huge` entry in `AgentParams.Costs` inverts the cost.**
With `Costs = { Room = math.huge }` a path from the corridor into a safe room
returned `Success`; the same path with `Room = 1e6`, `Room = 1000` or no `Costs`
at all returned `NoPath`. Use a large finite number. The mechanism inside
`PathfindingService` is unconfirmed, but the four-way comparison reproduces.

**`Measured`** — **the navmesh puts waypoints closer to a `RoomBlocker` than the
agent can stand.** Walking to the `Room_727` door approach from the north, the
path's waypoints 2 and 3 sit 1.90 studs from the blocker surface while
`AgentRadius` is 2.50, so the body cannot occupy them. This is independent of
`Costs` — all four cost settings above produced the same 1.90. `NPC:_walkPath`
therefore skips waypoints that fail `HasMovementClearance`; before that it
walked at them and ate a full eight-second `MoveToFinished` timeout each time.

**`Measured`** — **an enemy standing on a stranded patch of the hallway graph
used to be stuck there permanently.** `Patrol` picks its home with
`FindNearestNode`, which is a nearest-position scan and happily returns a node
in a pocket that connects to nothing. Spawning a Chaser on the pocket at
(508, -23, 134) and running `Patrol` now walks it off within a second and 387
studs across the map in 40 s. Nodes carry `WellConnected` and `Patrol` passes
`wellConnectedOnly`; if patrol ever freezes again, print that flag for the
enemy's nearest node first.
