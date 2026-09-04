# StarterPlayer

### StarterPlayerScripts\Init.local.luau
The client bootstrap. It `task.defer`s a `require` of every child of `ReplicatedStorage.Services`, which is what makes every shared/client Service self-initialize, then calls `ReplicatedStorage.Modules.Tagger` to wire the client-side CollectionService tags to their classes.
- API: no return value — this is a LocalScript, not a module.
- Requires: every module under `ReplicatedStorage\Services\`, plus `ReplicatedStorage\Modules\Tagger.luau`.

Adding a module to `ReplicatedStorage\Services\` is all that is needed to have it start on the client; there is deliberately no `:Init()` method anywhere. Every service in the folder is loaded unconditionally, so a service that should only run on one side must guard itself with `RunService:IsClient()` / `:IsServer()`. Ordering between services is not guaranteed because every require is deferred.

### StarterPlayerScriptsPerfGraph.local.luau
Self-contained F8 performance panel with no `require`s at all, so it keeps working when every other script is stripped out. Two time-aligned scrolling graphs sharing one X axis (one column per frame, newest at the right edge, bars slide left): FPS from every RenderStepped delta on a fixed 0-120 scale coloured by warn/bad thresholds, and a stacked graph of Workspace descendants added plus removed that frame on a fixed 0-500 scale, each instance bucketed into the first category whose classes it `IsA` (parts, models/folders, scripts, lights, effects, textures/meshes, audio, joints/attachments, gui, values, characters/anim, other) with a colour key. Labelled reference lines, no auto-scaling, one-pixel ticks for single instances, white caps on clipped bars, pause and clear buttons. Everything is a constant at the top of the script.
- API: no return value — this is a LocalScript.
- Requires: nothing.

Nothing else lives in StarterPlayer, and nothing installs into it at runtime either. Wallstick works entirely from `ReplicatedStorage\Classes\Wallstick\`, patching the live stock PlayerModule and temporarily disabling the stock Animate/RbxCharacterSounds scripts client-side only while a player has wallstick enabled.
