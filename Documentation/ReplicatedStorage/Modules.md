# ReplicatedStorage / Modules

Legacy placement. New shared helpers must be added as Services or Classes, never here.

### extend.luau
Returns a single function that gives a table a metatable forwarding reads and writes to a list of fallback tables/Instances, rebinding functions so a table extension is called with the extended table as `self`.
- API: `extend(t: {}, ...: {} | Instance) -> {}` — mixin/delegation helper; first extension that has the key wins

### Tagger.luau
Client-side tag bootstrap: returns a function that the StarterPlayerScripts Init script calls, which defers and then registers four CollectionService tags with `TagService:Listen` under `workspace`, constructing a class instance on add and destroying it on removal.
- API: `Tagger()` — module returns a single function; call it once from the client Init
- Tags: listens `Hole` (-> `Classes.Hole`), `Spin` (-> `Classes.Spin`), `Watch` (-> `Classes.Watch`), `Breathe` (-> `Classes.Breathe`)
- Requires: `Services.TagService`; `Classes.Hole`, `Classes.Spin`, `Classes.Watch`, `Classes.Breathe`

