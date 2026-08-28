# ReplicatedStorage / Configs

Pure data tables. Each is named `TopicConfig` and returns only the table.

### AmbienceConfig.luau
Distance-based volume falloff and fade timing for ambient sound emitters.
- API: data table — `SilentDistance`, `FullVolumeDistance`, `FadeTime`, `UpdateInterval`

### AnimationConfig.luau
Animation asset ids plus per-enemy animation sets (walk/run/idle/attack) used by enemy rigs and tools.
- API: data table — `Animations` (id lookup), `Sets` (per-enemy `AnimationSet`); exports type `AnimationSet`

### BreatheConfig.luau
Idle breathing motion applied to character joints.
- API: data table — `Period`, `InhaleFraction`, `Waist`, `Neck`, `Shoulder`, `Root`, `Smoothing`, `MaxDistance`

### CameraBobConfig.luau
Walk-cycle camera bob amplitude, cadence and speed scaling.
- API: data table — `VerticalDistance`, `HorizontalDistance`, `RollAngle`, `StepsPerSecond`, `ReferenceWalkSpeed`, `FadeSpeed`, `AmplitudeSpeedInfluence`, `MinAmplitudeScale`, `MaxAmplitudeScale`

### ChaosLightConfig.luau
Red hallway-light warning that precedes the Chaos enemy.
- API: data table — `RedColor`

### ChaseMusicConfig.luau
Per-enemy chase music tracks with range, volume and fade rates.
- API: data table — `FadeInSpeed`, `FadeOutSpeed`, `Enemies` (Chaser, CeilingDweller, Mimic)

### ChaserCameraConfig.luau
Chase-driven camera FOV changes and per-enemy camera shake profiles.
- API: data table — `FadeInSpeed`, `FadeOutSpeed`, `FovReleaseSpeed`, `CeilingDweller`, `MimicFovDelay`, `ChaseShakes` (Chaos, Chaser, CeilingDweller, Mimic)

### ComputerAssets.luau
Image asset ids for the hackable-computer UI.
- API: data table — `ComputerIcon`, `LockIcon`, `CheckIcon`

### ComputerConfig.luau
Everything for the hackable computer objective: tagging, interaction, camera framing, prompt UI, screen SurfaceGui and the HUD counter.
- API: data table — `Tag`, `IdAttribute`, `ModelName`, `ScreenPath`, `Remotes`, `Colors`, `Targeting`, `Input`, `Camera`, `Highlight`, `UI`, `IdleScreen`, `HUD`

### CreepConfig.luau
The Creep enemy: light-killing radius, floating backdrop geometry, glowing eye pairs and spawn variants.
- API: data table — `LightRange`, `ConnectedHallwayLightRange`, `DarkDistance`, `TurnRate`, `Backdrop*` group, `DistortionSpeed`, `EyeColors`, `PairSpacing`, `PairPlacementTries`, `Variants`

### CrouchConfig.luau
Crouch movement, camera drop, crouch animations, stealth/noise effects and the crouch touch button.
- API: data table — `SpeedMultiplier`, `BlocksSprint`, `Camera`, `Body`, `Stealth`, `Input`, `Touch`

### DangerConfig.luau
Danger-field noise generation over the map plus the Director's enemy population, spawn placement weights and tick intervals.
- API: data table — noise/field keys (`Seed`, `FeatureScaleFraction`, `Octaves`, `Persistence`, `NoiseGain`, `Contrast`, `FloorHeight`, `FloorSeparation`, `SafeRadiusFraction`, `RampLengthFraction`, `PointSpacing`), `PathDangerWeight`, `ProgrammaticVents`, patrol/route keys, `Director`; exports type `FieldSettings`

### DeathConfig.luau
Death-cause names and player-facing hints per enemy, plus the full styling and timing of the glitchy "killed by" death screen.
- API: data table — `CauseMemory`, `Revive`, `Unknown`, `Causes`, `Screen`; exports type `Cause`

### DoorConfig.luau
Swinging door physics, proximity open/close distances and enemy forced-open behaviour.
- API: data table — `DoorwayTags`, `AnchorName` (the purely-translating part a door leaf follows when the doorway is moved; `Threshold`, not `DoorHeader`, which `HallwayCrush` rescales), `OpenAngle`, `OpenDistance`, `CloseDistance`, `MaxHeightDifference`, `SwingSpeed`, `EnemyTag`, `EnemyForceDistance`, `EnemyReleaseDistance`, `PollInterval`, spring keys (`Stiffness`, `DampingRatio`, `MaxStep`), settle keys

### DrawerConfig.luau
Openable drawers: tag/attribute names, spring motion, auto-close, interaction targeting, highlight, sounds and the prompt UI.
- API: data table — `Tag`, `Attribute`, open/auto-close keys, `OutwardAxis`, handle-detection keys, spring/settle keys, `Targeting`, `Input`, `Highlight`, `Sound`, `UI`

### DrawerItemConfig.luau
Items spawned inside drawers: spawn rates, rarity weights and the item-to-rarity table. At load time it clones `DrawerConfig.Input` and `DrawerConfig.UI` and overrides a few fields, and reuses `DrawerConfig.Targeting`/`Highlight` by reference.
- API: data table — `Tag`, `Attribute`, `Remotes`, `Spawn`, `Targeting`, `Input`, `Highlight`, `UI`, `Rarities`, `Items`
- Requires: `Configs/DrawerConfig`

### EffectsHUDConfig.luau
Layout, colours and icon ids for the active-item/effect tiles on the HUD.
- API: data table — `TileSize`, `TilePadding`, `CornerRadius`, `IconInset`, `EdgeMargin`, `Colors`, `Transparency`, `FlashDuration`, `HoleLifetime`, `FlashItems`, `Icons`

### ElevatorConfig.luau
Elevator instance names, door motion, proximity thresholds and the teleport fade/loading sequence.
- API: data table — `Tag`, `TypeAttribute`, `LobbyType`, `DoorsName`, `HitboxName`, `SpawnTag`, `DoorOffset`, `DoorTime`, `OpenDistance`, `CloseDistance`, `MaxHeightDifference`, `PollInterval`, `MinimumLoadingTime`, fade keys, `TeleportCooldown`

### EyeConfig.luau
The Eye enemy: tracking range, the hit flash/blink/blur reaction, gaze-buildup screen effects and idle bobbing.
- API: data table — `TrackRange`, `TurnRate`, `StunTurnRate`, `Hit*` group, `Gaze*` group, `BobHeight`, `BobPeriod`

### FLAGS.luau
Global on/off switches for major systems and debug output.
- API: data table — `Enemies`, `EnemyCommands`, `Director`, `DangerDebug`, `VoiceDebug`, `PerfLog`

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
The enemy Index (bestiary) UI: pagination, locked/undiscovered styling, the discovery reveal animation, card/button/page tweens, headshot camera framing and every enemy entry.
- API: data table — `EntriesPerPage`, `TemplateFolder`, `StartProgress`, `Locked`, `Discovery`, `Empty`, `HideUndiscovered`, `Pagination`, `Animation`, `Headshot`, `Entries`; exports types `StandinPart`, `Headshot`, `Entry`

### InventoryConfig.luau
Hotbar/backpack sizes, keybinds, drag thresholds and slot styling for the inventory UI.
- API: data table — `HotbarSlots`, `BackpackSlots`, `ToggleKey`, `HotbarKeys`, `DragThreshold`, `TouchDragThreshold`, `SlotSize`, `SlotPadding`, `CornerRadius`, `Colors`, `Transparency`, `PlaceholderIcon`

### KitCatalogConfig.luau
The 24 kits themselves: four per rarity across Common, Uncommon, Rare, Epic, Legendary and Mythic. Each entry carries an `Id`, a short `Name`, its `Rarity`, a one-line `Description`, an absolute `Stats` map (`MaxHealth`, `WalkSpeed`, `JumpPower`, `Stamina`, `SprintMultiplier`, `DetectionRadius` - omitted keys stay at base), an `Items` map of `ReplicatedStorage.Tools` name to count, and an optional `Showcase` naming which item's model represents the kit in a ViewportFrame. `Guest` is the free default every player owns. Split out from `KitConfig` so the catalogue can grow without the system settings moving.
- API: data table - `Entries`, `EntriesById`, `DefaultKit`
- Requires: nothing

### KitConfig.luau
Everything about kits that is not a kit: the six rarities (gem price, roll weight, point budget, colour and accent), the six stat definitions (base value, allowed range, whether higher is better, its point cost, and whether it is applied as a Humanoid property or a character attribute - `Stamina` and `SprintMultiplier` take their bases straight from `SprintConfig` so there is one source of truth), rolling settings, ViewportFrame framing, card/button/info/row animation numbers, and the button strings (`Text.BalancePrefix` is what every gem balance label reads before its number). It re-exports `KitCatalogConfig`'s entries so callers only require one module. `Roll` also carries the reel's feel - `CardWidth`/`CardHeight` (kept under 1 so the winner's flash can grow without the CanvasGroup cutting it), `CardTilt`, `MinScale`/`MaxScale` for the carousel, `ShakeTime`/`ShakeStrength`, `BackdropTime`/`BackdropTransparency` and `ResultPop`. The point economy is the balancing spine: an item costs its `ItemShopConfig` coin price divided by `ItemPointDivisor`, a stat costs its distance from base times the stat's `Cost`, stats set in the bad direction refund points up to `MaxRefundFraction` of the budget, and `Validate` reports every kit that overspends its rarity's budget or names an unknown stat, item or rarity.
- API: data table - `Rarities`, `RaritiesById`, `Stats`, `StatsById`, `Entries`, `EntriesById`, `DefaultKit`, `Roll`, `Viewport`, `Animation`, `Text`
- API: `KitConfig.GetRarity(kit) -> Rarity`
- API: `KitConfig.ItemPoints(itemId: string) -> number`
- API: `KitConfig.StatPoints(statId: string, value: number) -> number`
- API: `KitConfig.Spend(kit) -> number` - the kit's total point cost after refunds
- API: `KitConfig.Validate() -> { string }` - human-readable problems, empty when the catalogue is sound
- Requires: `KitCatalogConfig`, `ItemShopConfig`, `SprintConfig`

### ItemShopConfig.luau
Catalogue and presentation settings for the in-game item shop, including every purchasable entry's prices, blurb and viewport framing. At load time it builds an `EntriesById` lookup by iterating `Entries`, and exports an `Entry` type.
- API: data table — `StartingCoins`, `RobuxIcon`, `Entries`, `EntriesById`, `Viewport`, `Animation`

### LanternSwayConfig.luau
Tuning for the client-side pendulum simulation that makes hanging hallway lanterns swing.
- API: data table — `SwayModelNames`, `CameraCullRadius`, `MaxSimulated`, `SwingLimit`, `GravityScale`, `LimitBounce`, `WindStrength`, `WindSpeed`, `ImpulseChance`, `ImpulseStrength`, `Damping`, `SettleDamping`, `SettleAngle`, `WallMargin`, `ClearanceProbe`, `RecullInterval`

### LookConfig.luau
Settings for the look-direction system that replicates each player's aim to neck and waist joints on other clients.
- API: data table — `SendInterval`, `SendThreshold`, `MaxPitch`, `MaxYaw`, `Neck`, `Waist`, `Smoothing`, `MimicUpdateInterval`, `Debug`

### MapConfig.luau
Everything tuning the discoverable map: remote names, the `Map` ScreenGui paths, discovery radius and tick rate, canvas resolution and margin, hand-drawn ink style (colour, opacity, width and its variance, wobble amplitude and frequency, overshoot, bleed), the room floor tags, the landmark tags and their discovery radii, line-of-sight sampling, pan and zoom limits, room and computer-room stroke weights and hatch settings, danger layer colours, and marker sizing and effect timings.

### MapOddityConfig.luau
Roll timings, durations and per-effect tuning for the hallway/map oddity system (transparent hallways, doors opening, hallway chaos, gaze-gated blockers and the Void's widened crossing plank).
- API: data table — `Enabled`, `RollInterval`, `InitialDelay`, `TriggerChance`, `MinDuration`, `MaxDuration`, `MinimumPlayerDistance`, `Effects` (`Transparency`, `DoorsOpen`, `HallwayChaos`, `HallwayBlocker`, `HallwayVoid` including `PlankWidth`, `HallwayCrush` (incl. `SafeMargin`, `KillTolerance`, `BackstopDelay`, `TrimOvershoot`, `DoorwayMargin`, `MinimumHRPOverlap`), `ChaosWarning`), plus hallway detection keys `HallwayTransparency`, `HallwayHeightWindow`, `HallwayBelowWindow`, `SpatialPadding`, `MinimumPartHallwayFraction`

### MimicConfig.luau
Behaviour tuning for the Mimic enemy — reaction delays, idle emotes, its reveal sequence, floating, turning and approach distances.
- API: data table — reaction keys (`ReactionDelayMin/Max`, `KeyDeadzone`, `ReactionJitterMin/Max`), emote/spin keys, reveal keys (`HeadSnapDuration`, `RevealHoldTime`, `RevealSound*`, `RevealReverb*`, `RevealSub*`), float keys (`FloatHipRise`, `FloatRiseTime`, `FloatSettleTime`, `FloatBob*`), turning keys (`TurnRate`, `InteractionTurnRate`, `AimDrift*`, `FacingTorque`, `FacingResponsiveness`), and positioning keys (`WallProbeDistance`, `ApproachStopDistance`, `WithdrawGap`, `ShadowGap`, `Behind*`, `ImmediateBehindTurnChance`)

### NotificationConfig.luau
Visual settings for the top-center notification banner used for short player-facing feedback.
- API: data table — `DisplayOrder`, `Width`, `Height`, `TopMargin`, `Gap`, `Duration`, `FadeTime`, `BackgroundColor`, `BackgroundTransparency`, `StrokeColor`, `AccentColor`, `TextColor`, `TextStrokeColor`, `TextSize`

### ObservedFreezeConfig.luau
Tag name, attribute name and reconciliation tolerances for the "freeze while observed" enemy movement system. Assembled field-by-field on a named local table rather than as a literal, but returns only that table.
- API: data table — `Tag`, `FrozenAttribute`, `MaxOffset`, `ConfirmationTimeout`, `ReleaseSpeed`, `MinReportGap`

### PerkConfig.luau
Per-perk settings for the gamepass/perk system, keyed by perk name under a shared attribute prefix.
- API: data table — `AttributePrefix`, `Loadout`, `Visor`, `DoubleSpeed`, `FriendRevive`

### PhotoConfig.luau
Every value the tripod Camera photo system uses: the placed-model tag and attribute names, placement raycast limits, body height, the 180-degree model yaw and the ghost placement preview, countdown length, lens offset/FOV and the subject cone, ShadowFigure placement rules (including the forced test placement), capture flash timings including the figure render warmup, the unseen-despawn rule, the countdown billboard styling, and the film-developing photo UI with its full-screen arrival, expanded view and close button.
`Lens.Offset` is relative to the model's own pivot, which `Place.ModelYaw` has already turned around, so the tripod faces away from whoever placed it while still shooting forward.
- API: data table — `Tag`, `ModelName`, `Attributes`, `Place`, `Countdown`, `Lens`, `Figure`, `Capture`, `Despawn`, `Timer`, `Develop`

### PlayerLocatorConfig.luau
Cooldown, marker layout, focus animation and colour/font palette for the Player Locator tool's on-screen teammate markers.
- API: data table — `Modes`, `Cooldown`, `CooldownFormat`, `MarkerCooldownFormat`, `ArriveDistance`, `Highlight`, `Marker`, `Focus`, `Press`, `Colors`, `Fonts`

### PlayerOddityConfig.luau
Roll timings and effect weights for the player oddity system that randomly resizes a whole character, enlarges a player's head and head accessories, fades or head-stares a player's own character.
- API: data table — `Enabled`, `RollInterval`, `InitialDelay`, `TriggerChance`, `MinDuration`, `MaxDuration`, `MinimumPlayersForHeadStare`, `EffectWeights`, `SizeOptions`, `HeadSizeMultiplier`, `OddTransparency`, `HeadTurnRate`, `HeadReturnRate`

### PropOddityConfig.luau
Per-effect tuning for prop-based oddities — falling lanterns, falling paintings, the painting dweller, and the scurrying rat — covering arming, approach detection, candidate selection, and either repair rules (the fixture effects) or crossing-site sampling and rat motion (`RatScurry`).
- API: data table — `Enabled`, `Effects` (`LanternFall`, `PaintingFall`, `PaintingDweller`, `RatScurry`)

### ShopkeeperConfig.luau
Tag, interaction reach, input bindings, highlight styling and prompt-pill UI settings for the shopkeeper NPC.
- API: data table — `Tag`, `PageAttribute`, `Targeting`, `Input`, `Highlight`, `UI`, `SmileAnimationId`

### SpawnZoneConfig.luau
Tag name, timing and geometry for the spawn safe zone system: which tag marks zone parts, how often the server polls player positions against the zones, the per-enemy cooldown between touch repels, the vertical padding applied to all zone containment tests, and the styling of the runtime border walls.
- API: data table — `Tag`, `PlayerPollInterval`, `RepelCooldown`, `VerticalPad`, `Border` (`Thickness`, `Transparency`, `Color`)

### SprintBoostConfig.luau
Visual definitions for speed-boost aura overlays drawn around the sprint bar, one styled entry per boost item. Exports a `BoostVisual` type.
- API: data table — `TimerGap`, `AuraInset`, `AuraCorner`, `Boosts` (`Soda`, `Energy Drink`)

### SprintConfig.luau
Speed multiplier, stamina economy, camera FOV blend, input bindings and stamina-bar styling for the sprint system.
- API: data table — `SpeedMultiplier`, `Stamina`, `Camera`, `Input`, `UI`

### StatsHUDConfig.luau
Layout, colour thresholds and sampling intervals for the debug stats HUD panel (FPS, ping, danger level, enemy state rows).
- API: data table — `EdgeMargin`, `RowHeight`, `CaptionWidth`, `PanelWidth`, `TextSize`, `BackgroundTransparency`, `Colors`, `Enemies`, `Fps`, `Ping`, `Danger`, `TagWaitTimeout`, `TagPollInterval`, `TagSettlePolls`

### StreamingConfig.luau
Corridor-streaming settings — prediction, replication lead times, reconciliation intervals, teleport timeouts and the tags/attributes used to mark streamed models. Currently disabled via `Enabled = false`.
- API: data table — `Enabled`, `ApproachLength`, `CapLength`, prediction/update keys (`BranchWarmDistance`, `ReplicationLeadTime`, `MaxPingLeadTime`, `PredictionSpeedCap`, `CorridorSelectionSlack`, `UpdateInterval`, `HysteresisTime`, `PersistenceRetryInterval`, `ReconcileInterval`, `ReconcileGraceTime`, `MissingReportCooldown`, `MaxMissingReport`), `GlobalAssetSize`, `TeleportTimeout`, `ClientReadyTimeout`, `FailureMessage`, `IgnoreTag`, `ModelTag`, `ModelIdAttribute`

### ToolConfigs.luau
Per-tool settings keyed by tool name, giving each tool its CollectionService tag plus its own behaviour values (heal amounts, cooldowns, sounds, movement settings and player-oddity effect selections). Exports a `ToolConfig` type.
- API: data table — one entry per tool: `Flashlight`, `Bandage`, `Medkit`, `SpellBook`, `Trap`, `Ball`, `Shovel`, `Pathfinder`, `Soda`, `Energy Drink`, `Visor`, `Gravity Warper`, `Player Locator`, `Walkie Talkie`, `Big Head`, `Big Character`, `Small Character`, `Transparency`, `Random Oddity`
- Player oddity entries use `OddityKind`, optional `OddityOverrides`, or `OddityChoices` for the random four-effect item.

### ViewmodelConfig.luau
Placement, scale, sway/bob and per-tool orientation overrides for the first-person viewmodel and its fake arm. `Overrides.Camera` anchors the tripod by its handle, shrinks it with a per-tool `Scale` and tilts it so the body sits up and to the right instead of sprawling across the screen.
- API: data table — `HandOffset`, `Scale`, `Fit`, `SwayAmount`, `SwaySpeed`, `BobAmount`, `BobSpeed`, `Arm`, `Overrides`

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
Radio ranges, volumes, friend/all modes and the full DSP effect chain (compressor, bandpass, EQ, distortion, limiter, static) for walkie-talkie voice transmission.
- API: data table — `PhysicalDistance`, `TaggedSoundDistance`, `TaggedSoundPickupFalloff`, `RadioAllowedTag`, `DeathActiveGrace`, `TransmissionGrace`, `VoiceVolume`, `ProximityRadioBlend`, `TaggedSoundVolume`, `RadioPhysicalVolume`, `RadioNoiseRadius`, `RelaySyncInterval`, `Modes`, `Effects`

### WatchConfig.luau
Range, angle limits and joint weighting for the Watch class, which makes an NPC's head and torso track the local player.
- API: data table — `TrackRange`, `MaxPitchUp`, `MaxPitchDown`, `MaxYaw`, `Smoothing`, `Neck`, `Waist`
