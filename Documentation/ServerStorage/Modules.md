# ServerStorage / Modules

Legacy placement. New shared helpers must be added as Services or Classes, never here.

### Tagger.luau
Server-side tag bootstrap: returns a function that `ServerScriptService\Init.legacy.luau` calls once, deferring three `TagService:Listen` registrations scoped to `workspace`, each constructing a class instance on tag add and destroying it on removal.
- API: `Tagger()` — call the returned function once at startup
- Tags: listens `TrapObject` -> `ServerStorage.Classes.TrapObject`; `Sound` -> `ServerStorage.Classes.Sound`; `Animation` -> `ReplicatedStorage.Classes.Animation`
- Requires: `ReplicatedStorage.Services.TagService`
