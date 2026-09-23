# ReplicatedStorage / Configs

Pure data tables. Each is named `TopicConfig` and returns only the table.

### AmbienceConfig.luau
Distance-based volume falloff and fade timing for ambient sound emitters, plus the POI cross-fade and unsettling pitch, distortion and tremolo tuning used while inside a POI.
- API: data table — `SilentDistance`, `FullVolumeDistance`, `FadeTime`, `UpdateInterval`, `POI` (`Volume`, `FadeTime`, `Pitch`, `DistortionLevel`, `TremoloDepth`, `TremoloFrequency`)

### AnimationConfig.luau
Animation asset ids plus per-enemy animation sets (walk/run/idle/attack/room-reaction/listen/lurk/sleep/wake) used by enemy rigs and tools.
- API: data table — `Animations` (id lookup), `Sets` (per-enemy `AnimationSet`); exports type `AnimationSet`. A set's optional `RoomReaction` id replaces the cheer emote at safe-room doors (Chaser knocks with `DoorKnock`); a set's optional `Listen` id is a looping override played while standing at a search point (Blind uses `BlindListen`); a set's optional `Lurk` id is the standing idle GhostRenderService plays while the ghost holds a lurk spot (`GhostIdle`). A set's optional `Sleep` and `Wake` ids are the sit-against-the-wall doze and the startled get-up the Chaser's `Rest` state plays (`ChaserSleep`, `ChaserWake`). The `Sisters` set makes the sisters walk with `GhostIdle`. The `Stalker` set's `PeekLeft`/`PeekRight` are the corner-peek clips (135000980950954 / 116106210940082): each starts already leaning out, holds for half a second, then pulls the body back behind the corner and 2.47 studs to the side; `PeekRight` leans to the rig's left and retreats right, `PeekLeft` mirrors it.

### BadgeConfig.luau
Every Roblox badge the game awards, by role, as Creator Dashboard badge ids: `Joined` (first join), `Escaped` (any escape), `Escapes` (`Count` 3 and its `Badge`), `Rooms` (one id per point of interest, keyed by the `POI` part name, which is also the `RoomsIndexConfig` entry id), `Computers` (keyed by `ComputerChipConfig` colour key: Blue, Red, Green, Yellow, Purple) and `Deaths` (keyed by death cause id: Stalker, CeilingDweller, Mimic, Chaser). An id of 0 means the badge has not been created yet and is skipped everywhere. Shared rather than server-only because the client's rooms index reads `Rooms` to fetch each room's badge icon, the one source of the room photos. `Icon` tunes `BadgeIconService`: `Retries`, `RetryDelay` and `PrefetchGap` seconds. Exports type `Ids`.
- API: data table — `Joined`, `Escaped`, `Escapes`, `Rooms`, `Computers`, `Deaths`, `Icon`
- Requires: nothing

### BreatheConfig.luau
Idle breathing motion applied to character joints.
- API: data table — `Period`, `InhaleFraction`, `Waist`, `Neck`, `Shoulder`, `Root`, `Smoothing`, `MaxDistance`

### CameraBobConfig.luau
Walk-cycle camera bob amplitude, cadence, speed scaling and smoothed strafing tilt.
- API: data table — `VerticalDistance`, `HorizontalDistance`, `RollAngle`, `StrafeTiltAngle`, `StrafeTiltSpeed`, `StepsPerSecond`, `ReferenceWalkSpeed`, `FadeSpeed`, `AmplitudeSpeedInfluence`, `MinAmplitudeScale`, `MaxAmplitudeScale`

### ChaosLightConfig.luau
Red hallway-light warning that precedes the Chaos enemy, and how the client decides Chaos has passed a lamp.
- API: data table — `RedColor`, `PassCheckInterval`, `PassEngageRange`

### ChaosWarningConfig.luau
Client gating and placement for the Chaos warning ambience: how often to re-evaluate, which bus/folder/sting to play, and how near a red lamp has to be for the cue to be audible. There are deliberately **no volume-over-distance values here** — how loud the bed is at a given range belongs to the emitters' own `DistanceAttenuationBounds` in `ReplicatedStorage.Sounds`, not to this config. `RedHearingRange` doubles as the distance beyond which the anchor stops using a region's centre line and falls back to the red lamp itself, and `RedFadeBand` is how much of that range is spent ramping the bed down to nothing so leaving the red is not a step. `RedReleaseRate` is how fast the tracked red distance is allowed to grow in studs per second: a nearer lamp is followed instantly, a receding one only at that rate, because lamps behind you all clear at once as Chaos passes and the raw distance would otherwise leap from a few studs to hundreds between ticks. `StingLifetime` is the backstop that cleans up the one-shot's own source part.
- API: data table — `CheckInterval`, `AmbienceBus`, `AmbienceFolder`, `IncomingSound`, `RedHearingRange`, `RedFadeBand`, `RedReleaseRate`, `StingLifetime`, `FadeInSpeed`, `FadeOutSpeed`, `AnchorLerpSpeed`, `AnchorSnapDistance`, `ReleaseDelay`, `GainSnap`

### ChaseMusicConfig.luau
Per-enemy chase music templates with range, volume and fade rates. A template can name one sound or a folder of `AudioEmitter` instances, all of which play together.
- API: data table — `FadeInSpeed`, `FadeOutSpeed`, `Enemies` (Chaser, CeilingDweller, Mimic)

### ChaserCameraConfig.luau
Chase-driven camera FOV changes and per-enemy camera shake profiles.
- API: data table — `FadeInSpeed`, `FadeOutSpeed`, `FovReleaseSpeed`, `CeilingDweller`, `MimicFovDelay`, `ChaseShakes` (Chaos, Chaser, CeilingDweller, Mimic)

### CaptureConfig.luau
Behavior settings for the camcorder, the photo keep-or-burn prompt and the Gallery page: `RequireGamepass`, the gallery permission enum, video duration and the 30s engine cap, the REC/STOP GUI name and stop key, screenshot timeout, gallery page/GUI names and the universe filter, keep/burn and access text, capture date/time formats, and player-facing capture strings. Visual layout and style live in `StarterGui.CamcorderRecording`, `StarterGui.CaptureTemplates`, `StarterGui.GalleryGui`, `StarterGui.PhotoDevelop`, and `StarterGui.PhotoFlash`.

### ComputerAssets.luau
Image asset ids for the hackable-computer UI.
- API: data table — `ComputerIcon`, `LockIcon`, `CheckIcon`, `MonitorIcon` (the white hand-drawn CRT the computer notepad tints per chip colour)

### ComputerConfig.luau
Everything for the hackable computer objective: tagging, interaction, camera framing, prompt UI, screen SurfaceGui and the computer notepad (`HUD`: the `ComputersGui` name, title, locked/unlocked footer strings, pending icon transparency, the complete colour and flash speed).
- API: data table — `Tag`, `IdAttribute`, `ModelName`, `ScreenPath`, `Remotes`, `Colors`, `Targeting`, `Input`, `Camera`, `Highlight`, `UI`, `IdleScreen`, `HUD`

### CreepConfig.luau
The Creep enemy: light-killing radius, floating backdrop geometry, glowing eye pairs and spawn variants.
- API: data table — `LightRange`, `ConnectedHallwayLightRange`, `DarkDistance`, `TurnRate`, `Backdrop*` group, `DistortionSpeed`, `EyeColors`, `PairSpacing`, `PairPlacementTries`, `Variants`

### CrouchConfig.luau
Crouch movement, camera drop, crouch animations, stealth/noise effects and the crouch touch button, including its minimum and maximum scaled text size.
- API: data table — `SpeedMultiplier`, `BlocksSprint`, `Camera`, `Body`, `Stealth`, `Input`, `Touch`

### DangerConfig.luau
Danger-field noise generation over the map plus the Director's enemy population, spawn placement weights and tick intervals.
- API: data table — noise/field keys (`Seed`, `FeatureScaleFraction`, `Octaves`, `Persistence`, `NoiseGain`, `Contrast`, `FloorHeight`, `FloorSeparation`, `SafeRadiusFraction`, `RampLengthFraction`, `PointSpacing`), `PathDangerWeight`, `ProgrammaticVents`, patrol/route keys, `Director`; exports type `FieldSettings`

### DeathConfig.luau
Death-cause names and player-facing hints per enemy (including the `PaintingDweller` cause shown as "Painting Lurker"), plus the full styling and timing of the glitchy "killed by" death screen.
- API: data table — `CauseMemory`, `HitCooldown` (seconds one enemy must wait before it can hurt the same player again, shared by server attacks and client contact reports), `Revive` (`ForceFieldDuration`, and `SelfSource`, the `Revived` analytics `Source` for a self-bought revive), `UnknownId` (the cause id analytics report when nothing was chasing the player), `Unknown`, `Causes`, `Screen`; exports type `Cause`

### DoorConfig.luau
Swinging door physics, replicated player-proximity state, proximity open/close distances and enemy forced-open behaviour.
- API: data table — `DoorwayTags`, `AnchorName` (the purely-translating part a door leaf follows when the doorway is moved; `Threshold`, not `DoorHeader`, which `HallwayCrush` rescales), `OpenAttribute`, `OpenFromAttribute`, `OpenAngle`, NPC door-reaction spacing (`KnockDistance` — how far off the door an NPC stands to knock, `ApproachPadding` and `MinApproachDistance` — the wider stand-off its pathfinding walk targets first, which has to clear the flanking lantern columns), `OpenDistance`, `CloseDistance`, `MaxHeightDifference`, `SwingSpeed`, `EnemyTag`, `EnemyForceDistance`, `EnemyReleaseDistance`, `PollInterval`, spring keys (`Stiffness`, `DampingRatio`, `MaxStep`), settle keys

### DrawerConfig.luau
Openable drawers: tag/attribute names, spring motion, auto-close, interaction targeting, highlight, sounds and the prompt UI. `UI.HoldFillTransparency` is the transparency of the bar that sweeps across the prompt pill while a hold-to-activate target is being held.
- API: data table — `Tag`, `Attribute`, open/auto-close keys, `OutwardAxis`, handle-detection keys, `InteriorWallNames`, spring/settle keys, `Targeting`, `Input`, `Highlight`, `Sound`, `UI`
- `InteriorWallNames` is the lowercase set of part names that line the drawer cavity (`left side`, `right side`). The drawer body is a single mesh whose bounding box reaches the outer face of the front panel, so item placement measures these parts instead and gets the cavity the panel encloses.

### DrawerItemConfig.luau
Items spawned inside drawers and the loose hallway pickups: drawer spawn rates, currency target and refill settings, hallway placement limits and supported surface names, rarity weights, currency weights and reward amounts, pickup feedback labels and sound names, display rotations, plus the item-to-rarity table. Currency sits in 35% of all drawers (`Spawn.CurrencyTargetPercentage`) with a 20-second `Spawn.RefillDelay`, 20 loose hallway pickups stay alive on a 15-second `Hallway.RefillDelay`, coins are weighted 60 to gems 40, and every pickup grants exactly 1 coin or 1 gem. At load time it clones `DrawerConfig.Input` and `DrawerConfig.UI` and overrides a few fields, and reuses `DrawerConfig.Targeting`/`Highlight` by reference.
- API: data table — `Tag`, `Attribute`, `Remotes`, `Feedback`, `DisplayRotations`, `Spawn`, `Hallway`, `Targeting`, `Input`, `Highlight`, `UI`, `Rarities`, `Items`, `Currencies`
- `Hallway.Items` is the non-currency half of the hallway pool, built at load time from `ComputerChipConfig.Colors`: one entry per chip tool weighted at its LootWeight times `Hallway.ItemWeightScale` (0.3), rounded up to at least 1. Coins and gems keep their own weights, so chips are roughly a quarter of hallway spawns.
- Each chip color also gets its own `Rarities.ComputerChip<Key>` entry and points at it in `Items`, replacing the single shared ComputerChip weight.
- Requires: `Configs/ComputerChipConfig`, `Configs/DrawerConfig`

### EffectsHUDConfig.luau
Layout, colours and icon ids for the active-item/effect tiles on the HUD. `VerticalPosition` sets the stack's bottom edge just above the computer notepad.
- API: data table — `TileSize`, `TilePadding`, `CornerRadius`, `IconInset`, `EdgeMargin`, `VerticalPosition`, `Colors`, `Transparency`, `FlashDuration`, `HoleLifetime`, `FlashItems`, `Icons`

### ElevatorConfig.luau
Elevator instance names, Lobby/Start/Exit types, door motion, proximity thresholds, AccessCheckInterval (0.2 seconds), and the teleport fade/loading sequence.
- API: data table — `Tag`, `TypeAttribute`, `LobbyType`, `DoorsName`, `HitboxName`, `SpawnTag`, `DoorOffset`, `DoorTime`, `OpenDistance`, `CloseDistance`, `MaxHeightDifference`, `PollInterval`, `MinimumLoadingTime`, fade keys, `TeleportCooldown`

### EyeConfig.luau
The Eye enemy: tracking range, the hit flash/blink/blur reaction, gaze-buildup screen effects and idle bobbing.
- API: data table — `TrackRange`, `TurnRate`, `StunTurnRate`, `Hit*` group, `Gaze*` group, `BobHeight`, `BobPeriod`

### EscapeMusicConfig.luau
The exit elevator's escape theme: which sound template and bus it plays on, the distance band its volume ramps across, and how fast it fades.
- API: data table — `Template`, `Bus`, `Range`, `FullVolumeDistance`, `Volume`, `FadeInSpeed`, `FadeOutSpeed`, `SilenceEpsilon`, `SyncRetryInterval`
- Requires: nothing

### EndingConfig.luau
Everything the win screen and its server half share: the `Ending` remote folder and names, the `EndGui` name, the `/resetprogress` command name, the exit-cabin poll interval and the lift above the lobby SpawnLocation, the on-screen strings (`Text`: title, typewriter subtitle, post-it chapter line and note, button label, the waiting label and the caret), the beat timings (`Timing`: backdrop, card, logo, chip, typing interval and caret blink, post-it, button, fade out) and the motion numbers (`Motion`: card start/end/exit Y and rotations, logo start scale, post-it rotations, button rise), plus the backdrop and ink colours.
- API: data table - `Remotes`, `Gui`, `Command`, `CheckInterval`, `SpawnLift`, `Text`, `Timing`, `Motion`, `Colors`
- Requires: nothing

### EscapeConfig.luau
The escape (win) stat and its lobby leaderboard: `StatName` (the `leaderstats` IntValue name, `Escapes`), the canonical `OrderedStore` name and its Studio prefix for environment-scoped award writes, and everything under `Leaderboard`: where the board lives (`Folder`, `Part`, `Face`), the Studio GUI it is built from (`Gui`, `Root`), the `Title` text, the `NameFormat` (`"%s (%s)"`, display name then username), `UnknownName`, the `rbxthumb` `Headshot` URL pattern, `TopCount` rows, `RefreshInterval` and `AwardRefreshDelay` seconds, SurfaceGui `PixelsPerStud`, `LightInfluence` and `Brightness`, the `Templates` (instance names inside the design the board clones: title plate, title text, plank row, headshot, text) and the `Layout` numbers (margins, title width and gap, title text box, row width and vertical stretch, headshot inset and height, name gap, text height, score column edges), all as fractions of the part face or of a row. `EscapeService:GetTop` always reads the canonical unprefixed store.
- API: data table - `StatName`, `OrderedStore`, `Leaderboard`
- Requires: nothing

### FLAGS.luau
Global on/off switches for major systems and debug output.
- API: data table — `Enemies`, `EnemyCommands`, `Director`, `DangerDebug`, `VoiceDebug`, `ViewmodelDebug`, `ItemPreviewDebug`, `FlashlightDebug`, `PerfLog`

### FlashlightConfig.luau
The flashlight beam: the stacked spotlight cones, their shared colour, and where the local player's beam origin sits relative to the camera.
- API: data table — `Attribute`, `Color`, `Master`, `CameraOffset`, `Cones` (each `Name`, `Angle`, `Range`, `Brightness`, `Shadows`)

### FlashlightDebugConfig.luau
Toggle key and slider steps for the flashlight beam panel.
- API: data table — `ToggleKey`, `Step`, `AngleStep`, `WarmColor`

### GhostConfig.luau
The Ghost enemy's turn, bob and fade timing.
- API: data table — `TurnTime`, `BobHeight`, `BobPeriod`, `FadeTime`

### GraphicsFogConfig.luau
Distance-fog quality levels, the fog cage part, and the automatic FPS-driven level adjustment per device class.
- API: data table — `Enabled`, `ForceLowestLevel`, `FogEndByLevel`, `FogStartRatio`, `FogColor`, `Cage`, `HighestFoggedLevel`, `FogEndBlendSpeed`, `ReleaseDistance`, `Automatic`

### HearingConfig.luau
Visualisation of sounds travelling to the Blind enemy's ears: travel speed and the particle marker.
- API: data table — `TravelSpeed`, `MinTravelTime`, `MaxTravelTime`, `Particle`

### HeartbeatConfig.luau
Proximity heartbeat sound for the Blind enemy, with volume and rate ramps between resting and pursuit.
- API: data table — `EnemyId`, `Template`, `Range`, `FullDistance`, `Volume`, `PursuitAttribute`, `Rate`, fade/rate speeds, `SilenceEpsilon`

### IndexConfig.luau
The enemy Index (bestiary) UI: pagination, locked/undiscovered styling, the discovery reveal animation, card/button/page tweens, headshot camera framing and every enemy entry, including the "Painting Lurker" (`PaintingDweller`) entry rendered with the Painting Dweller rig. The `Stalker` entry draws `ReplicatedStorage.Enemies.Stalker`, which is now the black red-eyed rig the enemy itself spawns.
- API: data table — `EntriesPerPage`, `TemplateFolder`, `StartProgress`, `Locked`, `Discovery`, `Empty`, `HideUndiscovered`, `Pagination`, `Animation`, `Headshot`, `Entries`; exports types `StandinPart`, `Headshot`, `Entry`

### IntroCutsceneConfig.luau
Everything the intro cutscene reads, shared by the client orchestrator and the server services. The first block is a contract the server depends on: `Version` (1; a profile has seen the intro when its `IntroVersion` is at least this, so raising it replays the intro for everyone once), `SeenAttribute` (`IntroSeen`), `PlayingAttribute` (`IntroCutscenePlaying`, the local-only Player attribute the client sets while the intro plays and `PhotoCaptureService` reads), `Command` (`intro`) and `CommandAliases` (`cutscene`), `Remotes` (folder `IntroCutscene` with `Prepare`, `Started`, `Finished`, `Queue`), `Triggers` (`First`, `Replay`, `Command`), `Outcomes` (`Watched`, `Skipped`, `Interrupted`, `Left`), `Length` (23.5 s) and `Streaming` (`Timeout` and the four staging `Points` the server streams around on `Prepare`). The rest is the client's design: `Key` (the hook key, `IntroCutscene`), `StageName`, `Watchdog`, the `Gui` names it binds (including `ElevatorLoadingGui` as `Loading`), `Lighting` effect names, `Input` (action names, sunk gameplay keys, skip keys Space and ButtonA, replay keys T and ButtonX), `Pills` (key labels, `DimAfter`, `ReplayDelay`), `Skip` (hold, drain, fade-out, `ReturnAt` 22.3 and `ReturnRate` 1.5), `Trigger` (map, threshold part, crossing box, `RetryWindow`, `SeenWait`), `Text` (every string shown, `Welcome`/`WelcomeBack` formatted with the display name), `Captions` (typing and erase speed, caret, `MinHold` — the shortest time a fully typed line stays up before its erase starts, so a long display name still gets read — and each typed line's label, text, start and erase), `Sounds` (folder and each cue's template name, bus and gain; `Flicker` and `LightOut` carry only a name because `LightSweep` plays them 3D on the SFX bus itself), `Effects` and `Motes`, `Shakes`, `Stalker` and `StalkerSkip` (the peek spot, clip id, dip, geometry probes and the no-Stalker jump), `Creep`, `Lights` (sweep region, tags, junction lamp, kill steps, ambient target), `Points` (camera anchors), `Camera` (entry blend, return pose, motion blur, handheld noise and the camera `Keys`), `Grade` (fade, letterbox, vignette, colour, depth, blur, darkness, audio levels and card keyframes) and `Events` (the timeline; `Stalker = true` events are skipped with the Stalker beats and `Always = true` events still run after a skip). The events, in seconds: `Motes` 0.2, `SkipIn` 1, `StageStalker` 2, `StalkerGate` 3.4, `Heartbeat` 3.9, `Notice` 6.1 (sting and shake), `Flare` 6.42 (the Stalker's eye flare, when the push-in lands), `Dip` 8.5, `Whip` 9.6 (the whip sound only; the pan itself is in `Camera.Keys`), `StageCreep` 10.2, `Lights` 10.7 (schedules the lamp kills), `EyesSwell` 12.1 (the `EyesOpen` sound, started early so it crests on the opening), `EyesOpen` 13, `JunctionOut` 15.75, `MotesOut` 16.2, `Blink` 16.85, `Rush` 17 (distortion launch and `Rush` sound together), `Impact` 17.93 (shake), `SmashCut` 18 (`Blackout` sound, heartbeat cut), `Cleanup` 18.25, `Return` 22.3 and `End` 23.45. Which sound plays at which of these moments is tabled in `Documentation\ReplicatedStorage\Sounds.md`.
- API: data table — the keys above
- Requires: nothing

### InventoryConfig.luau
The inventory's shape on every device: a 5-slot hotbar (`HotbarSlots`, keys 1-5 in `HotbarKeys`) that scales down against `HUD.ReferenceSize` on small viewports, plus a 25-slot bag (`BackpackSlots`), the `ToggleKeys` that open the Inventory page (Y on gamepad; the keyboard key moved to `SideButtonConfig`, which owns E), drag thresholds and the code-built hotbar slot styling. `Page` carries everything the Inventory page needs that is not authored in the GUI: its page id and ScreenGui name, the name and display order of the ScreenGui the drag ghost rides in, the drag ghost ZIndex, the drop-target and selection strokes, the notice hold time, ink/bad colours for the quantity badge and refusals, and the `Text` table (`ToHotbar`, `ToBag`, `HotbarFull`, `BagFull`, `Empty`, `EmptyDescription`). Item quantities stack by name; the InventoryService separately maintains one required Walkie Talkie.
- API: data table — `HotbarSlots`, `BackpackSlots`, `ToggleKeys`, `HotbarKeys`, `DragThreshold`, `TouchDragThreshold`, `SlotSize`, `SlotPadding`, `CornerRadius`, `HUD`, `Colors`, `Transparency`, `PlaceholderIcon`, `Page`

### ItemPreviewConfig.luau
How every item ViewportFrame in the game frames its tool - the shop cards, the shop info panel, the inventory hotbar and all three kit pages read this one table through `ItemPreviewService`, so an item looks the same wherever it appears. `Default` is the framing every item starts from; `Items` holds only the per-item fields that differ from it. `FieldOfView` is global because it changes the perspective of every preview at once. The lighting trio is not decoration - without an explicit `Ambient`/`LightColor`/`LightDirection` tool models render as near-black silhouettes. Entries are written by hand or generated by the F2 item preview debug panel.
- API: data table - `FieldOfView`, `Default`, `Ambient`, `LightColor`, `LightDirection`, `Items`
- API: exports the `Framing` type (`Yaw`, `Pitch`, `Zoom`, `Padding`, `OffsetX`, `OffsetY`)

### ItemPreviewDebugConfig.luau
F2 developer-panel settings for framing item viewports live.
- API: data table - `ToggleKey`, `Step`, `AngleStep`

### ItemShopConfig.luau
Catalogue and presentation settings for the in-game item shop: every purchasable entry's id, name, blurb, coin and Robux prices, its developer-product key and whether it needs voice chat. The id must match a `ReplicatedStorage.Tools` tool name, because that is what the shop grants and what the preview renders. Every item with a `ToolConfigs` entry is listed here; the ones that were never meant to be sold carry placeholder prices of 1 until they are priced or removed. Coin prices run 2 (Ball), 3 (Bandage), 4 (Soda), 5 (Flashlight), 6 (Energy Drink), 8 (Shovel), 9 (Medkit), 10 (Trap), 12 (Pathfinder), 15 (Visor) and 18 (Spell Book), tuned so a mid-paced player earning roughly 8 to 10 coins per 10 minutes buys the cheapest item in a few minutes and the priciest in about two runs; `StartingCoins` is 5. Viewport framing lives in `ItemPreviewConfig`, not here. At load time it builds an `EntriesById` lookup by iterating `Entries`, and exports an `Entry` type.
- API: data table — `StartingCoins`, `RobuxIcon`, `Entries`, `EntriesById`, `Animation`

### KitCatalogConfig.luau
The 47 kits themselves, bottom-heavy by rarity: 13 Common, 10 Uncommon, 8 Rare, 7 Epic, 5 Legendary and 4 Mythic, each tuned to spend at least 95% of its rarity's point budget so no tier carries a dud. Each entry carries an `Id`, a short `Name`, its `Rarity`, a one-line `Description`, an absolute `Stats` map (`MaxHealth`, `WalkSpeed`, `Stamina`, `SprintMultiplier`, `DetectionRadius` - omitted keys stay at base), an `Items` map of `ReplicatedStorage.Tools` name to count, an optional `Showcase` naming which item's model represents the kit in a ViewportFrame when it has no picture, and an `Image` headshot asset id that every kit page and the roll reel draw instead of the item viewport. Every headshot is one of the 47 kit portraits from Flee From Monkeys (same group, so the assets load here), each used by exactly one kit, which is what caps the catalogue at 47. `Guest` is the free default every player owns. Split out from `KitConfig` so the catalogue can grow without the system settings moving.
- API: data table - `Entries`, `EntriesById`, `DefaultKit`
- Requires: nothing

### KitConfig.luau
Everything about kits that is not a kit: the six rarities (outright gem price 2, 4, 10, 20, 40 and 75 from Common to Mythic, roll weight, point budget - 12, 22, 34, 48, 64 and 80 - colour and accent), the five stat definitions (base value, allowed range, whether higher is better, its point cost, and whether it is applied as a Humanoid property or a character attribute - `Stamina` and `SprintMultiplier` take their bases straight from `SprintConfig` so there is one source of truth), rolling settings (`Roll.GemCost` is 5 gems, duplicates refund 40% of the rarity's gem price), card/button/info/row animation numbers, and the button strings (`Text.BalancePrefix` is what every gem balance label reads before its number, `Text.ChancesTitle` heads the roll odds panel). It re-exports `KitCatalogConfig`'s entries so callers only require one module. `Roll` also carries the reel's feel - `CardWidth`/`CardHeight` (kept under 1 so the winner's flash can grow without the CanvasGroup cutting it), `CardTilt`, `MinScale`/`MaxScale` for the carousel, `ShakeTime`/`ShakeStrength`, `BackdropTime`/`BackdropTransparency` and `ResultPop`. The point economy is the balancing spine: an item costs its `ItemShopConfig` coin price divided by `ItemPointDivisor` (1.5, chosen so no item costs more points under the 2-to-18 coin prices than it did under the old 15-to-120 prices over 10), a stat costs its distance from base times the stat's `Cost`, stats set in the bad direction refund points up to `MaxRefundFraction` of the budget, and `Validate` reports every kit that overspends its rarity's budget or names an unknown stat, item or rarity.
- API: data table - `Rarities`, `RaritiesById`, `Stats`, `StatsById`, `Entries`, `EntriesById`, `DefaultKit`, `Roll` (`Roll.Sku` is the name a roll's gem spend carries in the economy events), `Animation`, `Text`
- API: `KitConfig.GetRarity(kit) -> Rarity`
- API: `KitConfig.ItemPoints(itemId: string) -> number`
- API: `KitConfig.StatPoints(statId: string, value: number) -> number`
- API: `KitConfig.Spend(kit) -> number` - the kit's total point cost after refunds
- API: `KitConfig.Validate() -> { string }` - human-readable problems, empty when the catalogue is sound
- Requires: `KitCatalogConfig`, `ItemShopConfig`, `SprintConfig`

### KitsIndexConfig.luau
The kits index page: its page id, ScreenGui and page-root names, whether the rarity sections run rarest first, the rarity header's width, height, max text size and underline rule, and the lock badge stamped on kits the player does not own (`Image` is the game's shared lock icon, plus its size, vertical position, tint and transparency).
- API: data table — `PageId`, `Gui`, `Root`, `RarestFirst`, `Header`, `Lock`
- Requires: nothing

### LanternSwayConfig.luau
Tuning for the client-side pendulum simulation that makes hanging hallway lanterns swing.
- API: data table — `SwayModelNames`, `CameraCullRadius`, `MaxSimulated`, `SwingLimit`, `GravityScale`, `LimitBounce`, `WindStrength`, `WindSpeed`, `ImpulseChance`, `ImpulseStrength`, `Damping`, `SettleDamping`, `SettleAngle`, `WallMargin`, `ClearanceProbe`, `RecullInterval`, `StreamSettleTime` (seconds a lantern must go without a part streaming in before it is measured and simulated)

### LookConfig.luau
Settings for the look-direction system that replicates each player's aim to neck and waist joints on other clients.
- API: data table — `SendInterval`, `SendThreshold`, `MaxPitch`, `MaxYaw`, `Neck`, `Waist`, `Smoothing`, `MimicUpdateInterval`, `Debug`

### MapConfig.luau
Everything tuning the discoverable map: remote names, the `Map` ScreenGui paths, discovery radius and tick rate, canvas resolution and margin, hand-drawn ink style (colour, opacity, width and its variance, wobble amplitude and frequency, overshoot, bleed), the room floor tags, the landmark tags and their discovery radii, line-of-sight sampling, pan and zoom limits, room and computer-room stroke weights and hatch settings, danger layer colours, and marker sizing and effect timings.

### MapOddityConfig.luau
Spawn intervals, durations and per-effect tuning for the hallway/map oddity system (transparent hallways, world-space light blackouts, doors opening, hallway chaos, gaze-gated blockers and the Void's widened crossing plank). Every ambient effect supplies `SpawnIntervalMin` and `SpawnIntervalMax`; the scheduler samples `math.random(min, max)` directly before each map-wide spawn attempt. `Transparency` and `HallwayVoid` carry `Enabled = false`, which stops both their ambient spawning and manual starts; they now exist only as the baked Invisible Hallway and The Hole points of interest.
- API: data table — `Enabled`, `MinDuration`, `MaxDuration`, `MinimumPlayerDistance`, `Effects` (`Transparency`, `MapLightsOut` including `SpawnIntervalMin`, `SpawnIntervalMax`, `ChunkSize`, `ChunkHeight`, `ChunkBelow`, `MinimumLights` and `PickAttempts`, `DoorsOpen`, `HallwayChaos`, `HallwayBlocker` including `SpawnIntervalMin` and `SpawnIntervalMax` (120-180s, two thirds of the old 180-270 so roughly 1.5x as many gates stand at once), `DangerWeight`, `SplitClearance`, `MouthClearance`, `MinimumStretch` and `PickAttempts`, `HallwayVoid` including `PlankWidth`, `HallwayCrush` including `SpawnIntervalMin`, `SpawnIntervalMax`, `OccupiedChance`, `OccupiedChanceReferencePlayers`, `SafeMargin`, `KillTolerance`, `BackstopDelay`, `TrimOvershoot` (the per-layer stagger only; each piece is pushed out by its own reveal on top of it), `DoorwayMargin` and `MinimumHRPOverlap`, `ChaosWarning`), plus hallway detection keys `HallwayTransparency`, `HallwayHeightWindow`, `HallwayBelowWindow`, `SpatialPadding`, `MinimumPartHallwayFraction`

### MimicConfig.luau
Behaviour tuning for the Mimic enemy — reaction delays, idle emotes, its reveal sequence, floating, turning and approach distances.
- API: data table — reaction keys (`ReactionDelayMin/Max`, `KeyDeadzone`, `ReactionJitterMin/Max`), emote/spin keys, reveal keys (`HeadSnapDuration`, `RevealHoldTime`, `RevealSound*`, `RevealReverb*`, `RevealSub*`), float keys (`FloatHipRise`, `FloatRiseTime`, `FloatSettleTime`, `FloatBob*`), turning keys (`TurnRate`, `InteractionTurnRate`, `AimDrift*`, `FacingTorque`, `FacingResponsiveness`), and positioning keys (`WallProbeDistance`, `ApproachStopDistance`, `WithdrawGap`, `ShadowGap`, `Behind*`, `ImmediateBehindTurnChance`)

### MirrorRoomConfig.luau
Tuning for the mirrored connector room's reflections.
- API: data table — `Tag`, `OpaqueTag` (subjects whose real body is invisible but whose reflection must still render solid, e.g. `MirrorStalker`), `TransparencyAttribute` (per-instance record of what a blanked part's transparency was, so the reflection restores it instead of forcing everything to zero and revealing the HumanoidRootPart), `ViewerAttribute` (a `UserId` on an enemy model limiting its reflection to that one player), `Padding`, `FloorTolerance`, `RetryDelay`, `CastShadow`, `BendLocalLook`, `ReflectEnemies`, `StripClasses`

### NotificationConfig.luau
Visual settings for the top-center notification banner used for short player-facing feedback, styled as the game's torn paper strip.
- API: data table — `DisplayOrder`, `Width`, `Height`, `TopMargin`, `Gap`, `Duration`, `InTime`, `OutTime`, `Paper` (the torn strip image the leaderboard rows also use), `PaperTint`, `ShadowTint`, `ShadowTransparency`, `ShadowOffset`, `ShadowGrow`, `Tilt`, `EnterTilt`, `EnterDrop`, `EnterScale`, `ExitRise`, `Font`, `TextColor`, `StrokeColor`, `StrokeThickness`, `TextSize`, `MinTextSize`, `SidePadding`, `TopPadding`

### ObservedFreezeConfig.luau
Tag name, attribute name and reconciliation tolerances for the "freeze while observed" enemy movement system. Assembled field-by-field on a named local table rather than as a literal, but returns only that table.
- API: data table — `Tag`, `FrozenAttribute`, `MaxOffset`, `ConfirmationTimeout`, `ReleaseSpeed`, `MinReportGap`

### OverheadNameConfig.luau
Layout and styling for player overhead names and verified badge glyphs. `StudSize` sets the BillboardGui scale dimensions to 5.4 by 0.54, down 10% from 6 by 0.6. `MaxTextSize` remains 28.
- API: data table — `Tag`, `UserIdAttribute`, `VerifiedGlyph`, `StudSize`, `ExtentsOffset`, `StudsOffsetWorldSpace`, `TowardCamera`, `MaxDistance`, `AlwaysOnTop`, `Font`, `MaxTextSize`, `TextColor`, `StrokeColor`, `StrokeTransparency`

### POIConfig.luau
Point-of-interest tag, discovery, entry and occupancy remote names, the trigger-box padding and sweep interval used by the server, the entry sting's template/bus/cooldown, and every timing and string the discovery popup animates with.

### PerkConfig.luau
Per-perk settings for the gamepass/perk system, keyed by perk name under a shared attribute prefix. `PlayerLocator.GrantAttribute` names the player flag `/give` sets to unlock the locator without the pass.
- API: data table — `AttributePrefix`, `Loadout`, `Visor`, `PlayerLocator`, `Camcorder`, `UnlimitedStamina`, `FriendRevive` (`Source` is the `Revived` analytics `Source` a friend-bought revive is attributed to)

### PhotoConfig.luau
Every behavior value the tripod Camera photo system uses: the placed-model tag and attribute names, placement raycast limits, body height, the 180-degree model yaw and the ghost placement preview, countdown length, lens offset/FOV and the subject cone, ShadowFigure placement rules, capture flash timings including the figure render warmup, the unseen-despawn rule, countdown pulse rules, and film animation timings. The countdown, shutter flash, and film layout live in `StarterGui.CaptureTemplates.PhotoTimer`, `StarterGui.PhotoFlash`, and `StarterGui.PhotoDevelop`.
`Lens.Offset` is relative to the model's own pivot, which `Place.ModelYaw` has already turned around, so the tripod faces away from whoever placed it while still shooting forward.
- API: data table — `Tag`, `ModelName`, `Attributes`, `Place`, `Countdown`, `Lens`, `Figure`, `Capture`, `Despawn`, `Timer`, `Develop`

### PlayerLocatorConfig.luau
Cooldown, marker layout, focus animation and colour/font palette for the Player Locator tool's on-screen teammate markers.
- API: data table — `Modes`, `Cooldown`, `CooldownFormat`, `MarkerCooldownFormat`, `ArriveDistance`, `Highlight`, `Marker`, `Focus`, `Press`, `Colors`, `Fonts`

### PlayerOddityConfig.luau
Roll timings and effect weights for the player oddity system that randomly resizes a whole character, enlarges a player's head and head accessories, fades or head-stares a player's own character.
- API: data table — `Enabled`, `RollInterval`, `InitialDelay`, `TriggerChance`, `MinDuration`, `MaxDuration`, `MinimumPlayersForHeadStare`, `EffectWeights`, `SizeOptions`, `HeadSizeMultiplier`, `OddTransparency`, `HeadTurnRate`, `HeadReturnRate`

### PropOddityConfig.luau
Per-effect tuning for prop-based oddities — falling lanterns, falling paintings, the painting dweller (whose `Damage` is what each lunge takes off the player), and the scurrying rat — covering arming, approach detection, candidate selection, and either repair rules (the fixture effects) or crossing-site sampling and rat motion (`RatScurry`). `LanternFall` and `PaintingFall` use `ObjectFalling` as their `ImpactSound` on floor contact. `PaintingDweller` carries `StartAnimation` (one-shot burst-out), `ThrashAnimation` (loop that follows it), `AttackAnimation`, `HoleImage`, `RootDrop`, the studs the rig hangs below the canvas centre, and the `ReplicatedStorage.Sounds` template names `PopSound` (played once on the pop), `ScreamSound` and `RustleSound` (both looped until it retreats); its fixture debug highlight is disabled.
- API: data table — `Enabled`, `Effects` (`LanternFall`, `PaintingFall`, `PaintingDweller`, `RatScurry`)

### ResetComputersConfig.luau
The lobby reset-computers terminal: the `ResetComputers` tag on its model, the `Computer/Reset` remote, the confirm page's id/ScreenGui/root names, the interaction prompt text, width, reach and the seconds the key must be held, the server-side reach and cooldown the reset is validated against, and the notice text with how long it shows and how long after it the page closes.
- API: data table — `Tag`, `Remotes`, `Page`, `Prompt`, `TextWidth`, `HoldDuration`, `Reach`, `ServerReach`, `Cooldown`, `Notice`, `NoticeTime`, `CloseDelay`
- Requires: nothing

### RoomsIndexConfig.luau
The rooms index page: its page id and ScreenGui name, the 3-by-2 grid shape, the locked-card strings (`???`, `UNDISCOVERED` and the not-yet-found blurb), the empty-panel strings, the `n / N FOUND` counter format, pagination colours, the card/button/info animation numbers, and `Entries`: one entry per point of interest whose `Id` is the `POI` part's name (which is also what the discovery remotes send and the key of that room's badge in `BadgeConfig.Rooms`), with a display `Name` and a `Description` shown once found. Entries carry no image: each room's photo is its badge icon, resolved through `BadgeIconService`, so the badge on the Creator Dashboard is the single source of that picture. `EntriesById` is built at load. Exports type `Entry`.
- API: data table — `PageId`, `Gui`, `Columns`, `Rows`, `Locked`, `Empty`, `CounterText`, `Pagination`, `Animation`, `Entries`, `EntriesById`
- Requires: nothing

### ShopkeeperConfig.luau
Tag, interaction reach, input bindings, highlight styling and prompt-pill UI settings for the shopkeeper NPC.
- API: data table — `Tag`, `PageAttribute`, `Targeting`, `Input`, `Highlight`, `UI`, `SmileAnimationId`

### SideButtonConfig.luau
The four side-bar buttons' labels and keybinds, read by `InterfaceService`. Keyed by the `PageId` attribute the button already carries, so a button with no entry is labelled and bound by nothing. The label uses `TextScaled` between `MinTextSize` and `MaxTextSize` so long names stay inside the paper button.
- API: data table — `Pages` (`Items` = Items/I, `Kits` = Kits/K, `Shop` = Shop/G, `Inventory` = Inventory/E, each `{ Label, Key }`), `Format` (`"%s [%s]"`, the label with its key appended), `Label` (the runtime TextLabel's `Name`, `AnchorPoint`, `Position`, `Size`, `FontFace` Merriweather Bold, `Color`, `MinTextSize`, `MaxTextSize`, stroke colour/thickness/transparency and `ZIndexOffset`)

### SistersConfig.luau
Everything the Sisters eye-contact catch shares between client and server: the `Sisters` tag, the `Sisters` remote folder and its `Gaze`/`Gazed` names, the gaze test (`Gaze`: camera range and cone angle, dwell time, the server's extra range slack, the post-warp cooldown, the client's retry delay after a refusal and its reply timeout), the vertigo screen effect numbers (`Vertigo`: lead time before the warp, sting name, shake preset, flash, blur, FOV pull, colour drain, release and stop timings, ring count/stagger/scale/stroke) and the ceiling warp length (`Warp.Duration`, 30 seconds like the Gravity Warper).
- API: data table — `Tag`, `Remotes`, `Gaze`, `Vertigo`, `Warp`
- Requires: nothing

### SpawnZoneConfig.luau
Tag name, timing and geometry for the spawn safe zone system: which tag marks zone parts, how often the server polls player positions against the zones, the per-enemy cooldown between touch repels, the vertical padding applied to all zone containment tests, and the styling of the runtime border walls.
- API: data table — `Tag`, `PlayerPollInterval`, `RepelCooldown`, `VerticalPad`, `Border` (`Thickness`, `Transparency`, `Color`)

### SprintBoostConfig.luau
Visual definitions for speed-boost aura overlays drawn around the sprint bar, one styled entry per boost item. Exports a `BoostVisual` type.
- API: data table — `TimerGap`, `AuraInset`, `AuraCorner`, `Boosts` (`Soda`, `Energy Drink`)

### SprintConfig.luau
Speed multiplier, stamina economy, camera FOV blend, input bindings, bounded touch-button text and viewport-based stamina-bar scaling for the sprint system.
- API: data table — `SpeedMultiplier`, `Stamina`, `Camera`, `Input`, `UI`

### StalkerCameraConfig.luau
Client tuning for the Stalker's camera seize: `KillFieldOfViewOffset` (the FOV push while the kill turn runs), `FieldOfViewRestoreTime`, and `KillSting` (`Sound`, the `ReplicatedStorage.Sounds` template name played the instant the kill turn starts, and its `SoundGroup`).
- API: data table - `KillFieldOfViewOffset`, `FieldOfViewRestoreTime`, `KillSting`
- Requires: nothing

### StatsHUDConfig.luau
Layout, colour thresholds and sampling intervals for the debug stats HUD panel (FPS, ping, danger level, enemy state rows).
- API: data table — `EdgeMargin`, `RowHeight`, `CaptionWidth`, `PanelWidth`, `TextSize`, `BackgroundTransparency`, `Colors`, `Enemies`, `Fps`, `Ping`, `Danger` (`Interval`, `RetryInterval`, `Good`, `Fair`)

### StoreConfig.luau
Shared settings for the two Robux store pages, the gamepass `ShopUI` and the gem-pack `GemsUI`, plus the result code the server attaches to a granted gem purchase.
- API: data table — `Text` (`Owned`, `Unavailable`, `GemsSuffix`), `OwnedPrice` (`Position`, `Size` of the price label once a pass is owned), `GemPurchaseResult`, `GemPacks` (ordered `{ Frame, Amount }` entries; `Amount` keys into `MarketplaceService.Products.Gems`), `Flash` (`Time`, `Success`, `Failure`)

### StreamingConfig.luau
Corridor-streaming settings — prediction, replication lead times, reconciliation intervals, teleport timeouts and the tags/attributes used to mark streamed models. Currently disabled via `Enabled = false`.
- API: data table — `Enabled`, `ApproachLength`, `CapLength`, prediction/update keys (`BranchWarmDistance`, `ReplicationLeadTime`, `MaxPingLeadTime`, `PredictionSpeedCap`, `CorridorSelectionSlack`, `UpdateInterval`, `HysteresisTime`, `PersistenceRetryInterval`, `ReconcileInterval`, `ReconcileGraceTime`, `MissingReportCooldown`, `MaxMissingReport`), `GlobalAssetSize`, `TeleportTimeout`, `ClientReadyTimeout`, `FailureMessage`, `IgnoreTag`, `ModelTag`, `ModelIdAttribute`

### ToolConfigs.luau
Per-tool settings keyed by tool name, giving each tool its CollectionService tag plus its own behaviour values (heal amounts, cooldowns, sounds, movement settings and player-oddity effect selections). Exports a `ToolConfig` type.
- `Ball.Range` sets eye targeting to 20 studs; `Ball.ServerRange` is the server hit-report limit.
- API: data table — one entry per tool: `Flashlight`, `Bandage`, `Medkit`, `SpellBook`, `Trap`, `Ball`, `Shovel`, `Pathfinder`, `Soda`, `Energy Drink`, `Visor`, `Gravity Warper`, `Player Locator`, `Walkie Talkie`, `Big Head`, `Big Character`, `Small Character`, `Transparency`, `Random Oddity`
- Player oddity entries use `OddityKind`, optional `OddityOverrides`, or `OddityChoices` for the random four-effect item. `Shovel.HoleImmunityDuration` sets the six-second immunity granted when entering a hole.

### TopbarConfig.luau
Which interface pages get a TopbarPlus icon (Index, Rooms, Gems, Gallery in that order; the Rooms icon currently reuses the Index image), how those icons look and the viewport width below which their text labels hide.
- API: data table -- `PageGroup`, `Alignment`, `ImageScale`, `CompactWidth`, `Icons` (ordered `{ PageId, Name, Label, Image, Order }` entries; `PageId` keys into `InterfaceService`'s pages)

### TopHUDConfig.luau
Currency roll timing, coin and gem flash colours, danger meter tiers and the width-and-height reference size used to scale the top-centre HUD on small screens.
- API: data table -- `Gui`, `ReferenceWidth`, `ReferenceHeight`, `MinScale`, `MaxScale`, `Currencies`, `Roll`, `Danger`; exports type `Tier`

### ViewmodelConfig.luau
Placement, scale, sway/bob and per-tool orientation overrides for the first-person viewmodel and its fake arm. `Overrides.Camera` anchors the tripod by its handle, while `Overrides["Walkie Talkie"]` separately positions the radio and fake hand with `Anchor` and `ArmAnchor`, then scales and rolls the radio so its screen stays visible. An override may also carry `Poses` — variants selected by `ViewmodelService:SetPose` and blended in at `PoseSpeed`. A pose offsets the base (`AnchorOffset`/`ArmAnchorOffset`/`RotateOffset`), replaces it (`Anchor`/`ArmAnchor`/`Rotate`), or declares `Framing` (`Part`, `Element`, `Coverage`) and is solved from the rig's geometry instead. The walkie defines `Talk`, which offsets the base so hand tuning carries into it, and `Raised`, which is framed on the screen's `Main` element so it stays centred and square whatever the base pose and scale are.
Every `Rotate`/`RotateOffset` is a `CFrame.Angles(x, y, z)` triple in XYZ order, which is the order the F3 panel reads and writes.
- API: data table — `HandOffset`, `Scale`, `Fit`, `SwayAmount`, `SwaySpeed`, `BobAmount`, `BobSpeed`, `Arm`, `Overrides`

### ViewmodelDebugConfig.luau
F3 developer-panel settings for tuning the walkie-talkie first-person viewmodel live. `PoseOrder` lists which poses the panel offers as tunable states, after Live and Base.
- API: data table — `ToggleKey`, `Step`, `AngleStep`

### VoiceChatConfig.luau
Volume, attenuation distance and voice-activity detection settings for proximity voice chat.
- API: data table — `Volume`, `Distance`, `NoiseRadius`, `Activity`

### VoiceDebugConfig.luau
Definition of the F6 voice-volume debug panel's adjustable sliders. Each entry holds a live reference to the actual `VoiceChatConfig` / `WalkieTalkieConfig` table it edits, so the panel mutates those configs in place; exports an `Entry` type.
- API: data table — `ToggleKey`, `Step`, `Entries`
- Requires: `Configs/VoiceChatConfig`, `Configs/WalkieTalkieConfig` (held as live table references)

### WalkSoundConfig.luau
Small overrides for footstep sound playback rate and per-enemy step volume.
- API: data table — `PlayerStepFrequencyMultiplier`, `EnemyStepVolume`

### WalkieTalkieConfig.luau
Radio ranges, volumes, keybinds, friend/all modes, the on-model screen UI palette and the full DSP effect chain (compressor, bandpass, EQ, distortion, limiter, static) for walkie-talkie voice transmission. Transmission toggles from left mouse or the touch TALK button. `Categories` defines the four player-facing volume sliders (`Global`, `Voices`, `Monster`, `Noise`) by id, and both the client and server key their settings tables off those ids; an optional `Maximum` expands a category's gain range. The former Global maximum sits at 20% of its new 5x slider, the former Voices maximum sits at 40% of its new 6.25x slider, and `PlayerVolumeMaximum` puts the existing per-player gain at 40% of its 2.5x slider. `PowerAttribute`, `VoiceAttribute`, `TransmitAttribute` and `DeathAttribute` name the Player attributes the server replicates so every client can colour the roster and mark a powered radio's owner after death. `Ui.Meter` contains the level gain, smoothing and quiet/loud thresholds used to colour volume bars yellow, green or red. Layout and styling are not here — the walkie screen and the `WalkieHud` ScreenGui are authored in Studio, and `Ui.Colors` holds the state colours the roster swaps at runtime.
- API: data table — `PhysicalDistance`, `TaggedSoundDistance`, `TaggedSoundPickupFalloff`, `RadioAllowedTag`, `DeathActiveGrace`, `TransmissionGrace`, `VoiceVolume`, `ProximityRadioBlend`, `TaggedSoundVolume`, `RadioPhysicalVolume`, `RadioNoiseRadius`, `RelaySyncInterval`, `PlayerVolumeMaximum`, `ToolName`, `PowerAttribute`, `VoiceAttribute`, `TransmitAttribute`, `DeathAttribute`, `Keys`, `Modes`, `Categories`, `Ui`, `Prompt`, `Touch`, `Effects`

### WatchConfig.luau
Range, angle limits and joint weighting for the Watch class, which makes an NPC's head and torso track the local player.
- API: data table — `TrackRange`, `MaxPitchUp`, `MaxPitchDown`, `MaxYaw`, `Smoothing`, `Neck`, `Waist`

### ComputerChipConfig.luau
Shared configuration for the five navigation chips: color-to-room mapping, 60-second duration, cubic fade exponent, per-color loot weight (Blue 34, Green 27, Red 21, Purple 16, Yellow 12, with `LootWeight = 12` as the fallback for a color that omits its own), server route checks (0.5 seconds), reroute throttle (3 seconds / 8 studs), connector cache lifetimes, a two-job ComputeAsync concurrency cap, player clearance, and local neon-dot spacing, visibility range and pooling limits. Change Duration here to update tool configuration, the effect HUD countdown and trail lifetime together.
- Colors: Blue -> Room_357, Red -> Room_419, Green -> Room_466, Yellow -> Room_599, Purple -> Room_998, all under Maze15.Rooms.
- Each color entry carries a `LootWeight` ordered by how hard its computer's minigame is: Blue (Memory) 34, Green (Frogger) 27, Red (AimTrainer) 21, Purple (Simon) 16, Yellow (Snake) 12.
- Attributes: ComputerChipColor on the real computers and chip templates.
- Remotes: ComputerChip/Route (server-to-owner route, duration, expiry and revision), ComputerChip/Sync (owner requests an active route snapshot).
- DrawerItemConfig gives each name its own `ComputerChip<Key>` rarity carrying that color's LootWeight, and adds a scaled copy of it to `Hallway.Items` so chips also drop loose in hallways alongside coins and gems; existing stocking targets and refill timers are unchanged. The no-immediate-repeat rule still applies.
- ToolConfigs adds the five tagged tools with Class = ComputerChip and their ColorKey; EffectsHUDConfig gives each the computer icon, tinted by the active trail's color.

Kits do not modify jumping. All 24 kits inherit the StarterPlayer jump settings; the current Studio default uses jump height mode at 3 studs. JumpPower is no longer a supported kit stat.

### EnemyDespawnConfig.luau
ScaleMultiplier 1.5 enlarges the complete puff. FadeDuration is 0.15 seconds; DespawnDelay retains retiring models for 0.25 seconds for the visual transition.
SoundId 127089163163176 plays at volume 0.7 through SFX, with full volume through eight studs and attenuation to silence at 80 studs.
Six white smoke particles, 0.4–0.65-second lifetime, nominal size 70% of enemy bounds capped at six studs, and 180-stud distance culling. Texture 11627083142 comes from vfxresource, Tengen Explosives / Explosive (Blue) / Attachment / Smoke (BLACK); it is an 8-by-8 one-shot flipbook.

Enemy despawn layering: two fast dust-burst particles use the VFX place First / Strike 3 Dust flipbook (12441202218), six outer smoke particles retain the smoke flipbook, and five tiny drifting powder flecks use Tengen Explosives Dots (8030760338). Core fades in 0.22–0.35 seconds, flecks in 0.25–0.45, outer smoke in 0.4–0.65.
