# ReplicatedStorage / Frameworks

xenterface is a self-contained declarative UI framework living under `ReplicatedStorage\Frameworks\xenterface`, with its own Services/Classes/Config/Modules tree and its own `Tagger` module that wires the `Tab`, `Page` and `Hover` tags through the shared `TagService`. UI behaviour is authored entirely as attributes on GuiObjects (`PageGroup`, `PageId`, `Preset`, `Active`, `Inactive`, `ElementId`) written in a compact string animation language that `Sequence` parses into tweens. The framework is entered from `ReplicatedStorage\Services\InterfaceService.luau`, which requires the `xenterface` root module and takes a controller for the `"Main"` page group.

### xenterface\init.luau
Root module of the framework; requires the two internal services and boots `Tagger` against the local `PlayerGui`, then exposes a small facade. Requiring this module is what starts all tag listening.
- API: `xenterface:Controller(pageGroup: string) -> Controller` — get or create the controller for a page group
- API: `xenterface:Get(elementId: string) -> Instance?` — resolve an `ElementId`-tagged instance now
- API: `xenterface:Wait(elementId: string) -> Instance` — yield until an `ElementId` element exists
- Requires: internal `Services.ControllerService`, `Services.ElementService`, `Modules.Tagger`

### xenterface\Modules\Tagger.luau
Returns a single function that, given a `PlayerGui`, registers the framework's three `TagService:Listen` bindings. Each tag may be applied to the GuiObject itself or to a `Configuration` child of it, in which case the parent is the target and the child is the attribute source.
- API: `Tagger(playerGui: Folder)` — installs the Tab/Page/Hover tag listeners
- Tags: listens `Tab`, `Page`, `Hover`
- Requires: `ReplicatedStorage.Services.TagService`; internal `Classes.Tab`, `Classes.Page`, `Classes.Hover`

### xenterface\Services\ControllerService.luau
Registry of `Controller` objects keyed by page-group name, so every consumer of a group shares one controller. `Get` lazily creates on first request.
- API: `ControllerService:Create(pageGroup: string) -> Controller?` — warns and returns nil on duplicate
- API: `ControllerService:Get(pageGroup: string) -> Controller` — get or create
- API: `ControllerService:Fire(pageGroup: string, pageId: string, tab: GuiButton?)` — forward a fire to that group's controller
- Requires: internal `Classes.Controller`

### xenterface\Services\ElementService.luau
Maps instances tagged `Element` to their `ElementId` attribute so UI parts can be looked up by name instead of by path. Registration is limited to descendants of `PlayerGui`, tracks live `ElementId` attribute changes, and resumes any coroutines parked in `Wait`.
- API: `ElementService:Get(elementId: string) -> Instance?` — linear scan of the id map
- API: `ElementService:Wait(elementId: string) -> Instance` — yields the calling coroutine until the id registers
- Tags: listens `Element`

### xenterface\Classes\Controller.luau
Owns the active page id for one page group and drives the transition between pages. `Fire` collects every `Tab`/`Page`-tagged object in the group under `PlayerGui`, splits them into newly-active and newly-inactive sets by `PageId`, plays their toggle animations via `TagService:GetApplied`, and emits a detail table on `self.Fired`.
- API: `Controller.new(pageGroup: string) -> Controller` — fields `PageGroup`, `Fired` (Signal), `Active`, `Sequences`
- API: `Controller:Fire(pageId: string, tab: GuiButton?)` — no-op if `pageId` already active; fires `Fired` with `ActiveId`, `InactiveId`, `ActiveTab(s)`, `InactiveTab(s)`, `ActivePage(s)`, `InactivePage(s)`, `SelectedTab`
- Tags: reads `Tab`, `Page` (via `TagService:GetApplied`)
- Requires: `ReplicatedStorage.Services.TagService`; internal `Classes.Signal`, `Classes.Sequence`

### xenterface\Classes\Hover.luau
`Toggle` subclass bound to a GuiObject's `MouseEnter`/`MouseLeave`, playing the Active sequence on enter and the Inactive sequence on leave.
- API: `Hover.new(hover: GuiObject, source: Configuration?) -> Hover` — `source` defaults to the GuiObject
- API: `Hover:Entered()` — activates
- API: `Hover:Left()` — deactivates
- API: `Hover:Disconnect()` — drops `self.Connections`
- Requires: internal `Classes.Toggle`

### xenterface\Classes\Page.luau
Thin `Toggle` subclass representing a page; it adds only a `Page` field and inherits `Activate`/`Deactivate`, which `Controller` calls during transitions.
- API: `Page.new(page: GuiObject, source: Configuration?) -> Page` — `source` defaults to the GuiObject
- Requires: internal `Classes.Toggle`

### xenterface\Classes\Sequence.luau
The animation language compiler and player. It parses a sequence string (space/comma/semicolon separated phrases such as `pos-c`, `t-0.2`, `back out`, `scale-a-0.01`, `i`) into an ordered list of items holding tween properties, static properties, `TweenInfo` parts and delays, then plays them with `TweenService`, re-targeting the `Scale` property onto a child `UIScale`. Phrases support initial/present modifiers and `add`/`sub`/`mult`/`div` operations relative to the current property value; `i`/`initial` snapshots every property the paired sequence touches.
- API: `Sequence.new(guiObject: GuiObject, sequence: string, otherSequences: {string}, state: string) -> Sequence` — compiles at construction, errors with the offending phrase
- API: `Sequence:Play()` — stops itself, then runs the itemized steps on a deferred thread
- API: `Sequence:Stop()` — cancels the thread and every in-flight tween
- Requires: internal `Config.ParameterConfig`

### xenterface\Classes\Signal.luau
Wraps a `BindableEvent` in a table so the event and the signal both appear as members of one object, using the shared `extend` module.
- API: `Signal.new() -> Signal` — exposes `Fire`, `Connect`, `Wait` etc. plus the raw `Event`
- Requires: `ReplicatedStorage.Modules.extend`

### xenterface\Classes\Tab.luau
`Toggle` subclass for clickable tabs; reads `PageGroup` and `PageId` from the source (erroring if either is missing) and fires its controller on `MouseButton1Click`. With a `Toggle` attribute set to true, clicking the already-active tab fires an empty page id instead, closing the group.
- API: `Tab.new(tab: GuiButton, source: Configuration?) -> Tab` — `source` defaults to the button
- API: `Tab:Disconnect()` — drops `self.Connections`
- Requires: internal `Services.ControllerService`, `Classes.Toggle`

### xenterface\Classes\Toggle.luau
Shared base for `Tab`, `Page` and `Hover`: resolves the Active/Inactive sequence strings from a `Preset` attribute (looked up in `PresetConfig`) with per-object `Active`/`Inactive` attributes overriding them, builds a `Sequence` for each, and exposes the two playback methods. When one instance carries several system tags, the lower-priority system's sequences are suppressed so Hover beats Page and Page beats Tab.
- API: `Toggle.new(guiObject: GuiObject, source: Configuration | GuiObject, systemType: string) -> Toggle` — `systemType` is `"Tab"`, `"Page"` or `"Hover"`
- API: `Toggle:Activate()` — stops the Inactive sequence and plays Active
- API: `Toggle:Deactivate()` — stops the Active sequence and plays Inactive
- Requires: internal `Config.PresetConfig`, `Classes.Sequence`

### xenterface\Config\ParameterConfig.luau
Lookup tables for the sequence language, plus a property type table built at load time by unioning `ReflectionService:GetPropertiesOfClass` over `TextButton`, `ImageLabel` and `UIScale`.
- API: data table — `EasingDirections`, `EasingStyles`, `DynamicProperties` (tweenable abbreviations such as `pos`, `size`, `bgc`, `scale`), `DynamicPropertiesCache`, `StaticProperties` (`lo`, `v`, `z`), `StaticPropertiesCache`, `Types` (property name to script type), `Operations` (`add`/`sub`/`mult`/`div` and one-letter aliases)

### xenterface\Config\PresetConfig.luau
Named animation presets referenced by the `Preset` attribute. Most entries are `Active`/`Inactive` sequence-string pairs; the later `Hotel*` entries are plain numeric/Enum tables consumed directly by `InterfaceService` rather than by `Toggle`.
- API: data table — `Example`, `Menu`, `Hover`, `Hover2`, `RectangleHover`, `RectangleSelect`, `ButtonHover`, `FrameHover`, `FrameHoverScale`, `HotelPage` (sequence pair plus `CloseTime`), `HotelSideButton`, `HotelCloseButton`, `HotelEffects` (tween tuning values)
