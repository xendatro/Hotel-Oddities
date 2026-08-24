# ServerScriptService

### Init.legacy.luau
The server bootstrap. It `task.defer`s a `require` of every child of `ServerStorage.Services`, which is what makes every server Service self-initialize, then calls `ServerStorage.Modules.Tagger` to wire the server-side CollectionService tags to their classes.
- API: no return value — this is a Script, not a module.
- Requires: every module under `ServerStorage\Services\`, plus `ServerStorage\Modules\Tagger.luau`.

The `.legacy` suffix marks the file's RunContext as Legacy Script. Adding a module to `ServerStorage\Services\` is all that is needed to have it start on the server; there is deliberately no `:Init()` method anywhere. Ordering between services is not guaranteed because every require is deferred, so services must not depend on another service having already run its bottom-of-file connections.

This script never touches `ReplicatedStorage.Services`; shared services reach the server only when a server module requires them directly.
