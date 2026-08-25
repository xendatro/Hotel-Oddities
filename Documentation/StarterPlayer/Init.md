# StarterPlayer

### StarterPlayerScripts\Init.local.luau
The client bootstrap. It `task.defer`s a `require` of every child of `ReplicatedStorage.Services`, which is what makes every shared/client Service self-initialize, then calls `ReplicatedStorage.Modules.Tagger` to wire the client-side CollectionService tags to their classes.
- API: no return value — this is a LocalScript, not a module.
- Requires: every module under `ReplicatedStorage\Services\`, plus `ReplicatedStorage\Modules\Tagger.luau`.

Adding a module to `ReplicatedStorage\Services\` is all that is needed to have it start on the client; there is deliberately no `:Init()` method anywhere. Every service in the folder is loaded unconditionally, so a service that should only run on one side must guard itself with `RunService:IsClient()` / `:IsServer()`. Ordering between services is not guaranteed because every require is deferred.

Nothing else lives in StarterPlayer, and nothing installs into it at runtime either. Wallstick works entirely from `ReplicatedStorage\Classes\Wallstick\`, patching the live stock PlayerModule and temporarily disabling the stock Animate/RbxCharacterSounds scripts client-side only while a player has wallstick enabled.
