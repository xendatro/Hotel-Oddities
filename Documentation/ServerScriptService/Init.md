# ServerScriptService

### Init.legacy.luau
The server bootstrap. It requires `POIDiscoveryService` before deferring the remaining child `require`s so the POI remotes and occupancy detector are registered before clients can request their initial state, then calls `ServerStorage.Modules.Tagger` to wire the server-side CollectionService tags to their classes.
- API: no return value — this is a Script, not a module.
- Requires: `ServerStorage\Services\POIDiscoveryService.luau`, every other module under `ServerStorage\Services\`, plus `ServerStorage\Modules\Tagger.luau`.

The `.legacy` suffix marks the file's RunContext as Legacy Script. Adding a module to `ServerStorage\Services\` is all that is needed to have it start on the server; there is deliberately no `:Init()` method anywhere. `POIDiscoveryService` is the one ordered exception because its remotes and occupancy state must exist before the client bootstrap sends its initial synchronization request. Ordering between all remaining services is not guaranteed because every other require is deferred, so those services must not depend on another service having already run its bottom-of-file connections.

This script never touches `ReplicatedStorage.Services`; shared services reach the server only when a server module requires them directly.
