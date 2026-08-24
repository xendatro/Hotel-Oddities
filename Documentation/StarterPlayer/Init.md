# StarterPlayer

### StarterPlayerScripts\Init.local.luau
The client bootstrap. It `task.defer`s a `require` of every child of `ReplicatedStorage.Services`, which is what makes every shared/client Service self-initialize, then calls `ReplicatedStorage.Modules.Tagger` to wire the client-side CollectionService tags to their classes.
- API: no return value — this is a LocalScript, not a module.
- Requires: every module under `ReplicatedStorage\Services\`, plus `ReplicatedStorage\Modules\Tagger.luau`.

Adding a module to `ReplicatedStorage\Services\` is all that is needed to have it start on the client; there is deliberately no `:Init()` method anywhere. Every service in the folder is loaded unconditionally, so a service that should only run on one side must guard itself with `RunService:IsClient()` / `:IsServer()`. Ordering between services is not guaranteed because every require is deferred.

### StarterCharacterScripts\Animate\ (init.local.luau, Controller.luau, CharacterAnimate\)
Replacement for Roblox's default character Animate script, from the Wallstick integration. Runs EgoMoose's vendored `CharacterAnimate` package (R6 and R15 reimplementations of the default animations) and exposes a `Controller` module whose `matchAnimate(director: Humanoid)` re-targets the animations to follow another humanoid — Wallstick uses this to make the real character perform the hidden fake character's animations while stuck to a surface. Creates its `PlayEmote` BindableFunction at runtime.

### StarterPlayerScripts\RbxCharacterSounds\ (init.local.luau, Controller.luau, CharacterSounds\)
Replacement for Roblox's default character sounds script, from the Wallstick integration. Runs EgoMoose's vendored `CharacterSounds` package for every player and exposes a `Controller` module whose `setPerformer(player, performer)` makes a player's sounds follow a different rig — Wallstick points this at its fake character so footsteps and landing sounds track the simulated movement.

### StarterPlayerScripts\PlayerModule\ (patched copy)
Statically vendored patched PlayerModule (upliftgames/playermodule 700.0.7000935) replacing Roblox's default camera/control scripts. Identical to stock except for a `Modifiers` system that runs every module under `PlayerModule\Modifiers` at startup; the single installed modifier, `GravityCameraModifier`, adds `SetTargetUpVector`/`GetUpVector`/`SetSpinPart`/`GetRotationType` to the camera module so the Wallstick camera can tilt and spin with arbitrary gravity. `Classes.Wallstick.GravityCamera` is the typed client interface to these additions.
