# Hotel Oddities

Roblox game source. The root folders mirror Roblox service containers:
`ReplicatedFirst`, `ReplicatedStorage`, `ServerScriptService`, `ServerStorage`,
`StarterPlayer`. Architecture rules live in `CLAUDE.md` and are not optional.

## How to find things

Full documentation lives in `Documentation\`, mirroring the container layout:

```
Documentation\
  ReplicatedFirst\Preload.md
  ReplicatedStorage\Services.md   Classes.md   Configs.md   Modules.md   Frameworks.md
  ServerScriptService\Init.md
  ServerStorage\Services.md   Classes.md   Configs.md   Modules.md
  StarterPlayer\Init.md
```

Every script has a `### FileName.luau` heading with a description, its public
API, the remotes it uses, the tags it listens to or applies, and its notable
dependencies.

Search the docs before searching the code.

PowerShell:

```powershell
Select-String -Pattern "keyword" -Path Documentation\**\*.md
Select-String -Pattern "Sprint" -Path Documentation\**\*.md
Select-String -Pattern "^### " -Path Documentation\ServerStorage\Services.md
```

Grep / ripgrep:

```
rg -i "keyword" Documentation
rg -i "sprint" Documentation
rg "^### " Documentation/ServerStorage/Services.md
```

To find where a remote or a tag is used, grep the docs for its name — the
`Remotes:` and `Tags:` bullets carry them.

## Shared helpers — do not re-implement these

Check this list before writing any utility. If the behaviour you need is here,
extend it instead of writing a second copy.

| Helper | Where | What it covers |
| --- | --- | --- |
| `CharacterService` | `ReplicatedStorage\Services` | Character, humanoid and root-part lookup and alive checks |
| `MathService` | `ReplicatedStorage\Services` | Shared numeric/vector math helpers |
| `CommunicationService` | `ReplicatedStorage\Services` | Getting, finding and creating remotes under `ReplicatedStorage.Communication` |
| `TweenProxyService` | `ReplicatedStorage\Services` | Tweening values that are not directly tweenable |
| `GuiBuilderService` | `ReplicatedStorage\Services` | Building GUI objects (frames, labels, buttons, strokes, corners) — client and server |
| `ChatCommandService` | `ServerStorage\Services` | Registering and dispatching chat commands |
| `TagService` | `ReplicatedStorage\Services` | Binding CollectionService tags to apply/unapply handlers |
| `MinigameBase` | `ReplicatedStorage\Classes\Minigames` | Base class every minigame extends |
| `RigMotion` | `ReplicatedStorage\Classes` | Procedural motion applied to character rigs |
| `Spring` | `ReplicatedStorage\Classes` | Spring integrator for smoothed motion |
| `ToolBase` / `ClientTool` / `ServerTool` | `ReplicatedStorage\Classes`, `ServerStorage\Classes` | Base classes for the two halves of every tool |
| `EnemyBase` | `ServerStorage\Classes` | Base class every enemy extends |
| `NPC` | `ServerStorage\Classes` | Base class for pathfinding humanoid enemies |
| `SurfaceWalker` | `ServerStorage\Classes` | Walks any humanoid rig/NPC along walls or ceilings kinematically |
| `Wallstick` / `WallstickService` | `ReplicatedStorage\Classes`, `ReplicatedStorage\Services` | Player wall/ceiling sticking (vendored EgoMoose controller) |
| `Oddity` / `PropOddity` / `PlayerOddity` / `HallwayOddity` / `FixtureFall` | `ServerStorage\Classes` | The oddity hierarchy every concrete oddity extends |
| `FixturePool` / `CrossingPool` | `ServerStorage\Classes` | Arming and approach detection for oddities triggered by walking toward a fixture or a hallway point |

Never add files to a `Modules\` folder — those are legacy. New shared helpers
become Services or Classes.

## Every script

### ReplicatedFirst

- ReplicatedFirst\Preload.local.luau — Preloads every content asset and drives the loading screen before anything else runs.

### ReplicatedStorage\Services

- ReplicatedStorage\Services\AimService.luau — Look-at rotation and frame-rate-independent rotational easing.
- ReplicatedStorage\Services\AmbienceService.luau — Plays the looping ambience playlist, ducking it by distance to the nearest enemy and swapping to death ambience.
- ReplicatedStorage\Services\AudioService.luau — Central sound playback helper for 2D and positional audio, bus volumes and walkie-talkie relaying.
- ReplicatedStorage\Services\BobService.luau — Random phase plus sine-wave vertical bob offset.
- ReplicatedStorage\Services\CameraFovService.luau — Combines named additive field-of-view offsets from multiple effects into one camera FOV.
- ReplicatedStorage\Services\CeilingVentDoorService.luau — Tweens ceiling vent doors on the client when the server commands them.
- ReplicatedStorage\Services\ChaosLightService.luau — Turns tagged floor lights red while a Chaos oddity is near, restoring their original colours after it passes.
- ReplicatedStorage\Services\ChaosWarningSoundService.luau — Plays hallway ambience and an incoming sting near the server's chaos warning regions.
- ReplicatedStorage\Services\CharacterService.luau — Shared nil-safe helpers for humanoids, alive root parts and player lifecycle cleanup.
- ReplicatedStorage\Services\ChaseMusicService.luau — Cross-fades layered chase music by proximity to enemies that are hunting.
- ReplicatedStorage\Services\ChaserCameraService.luau — Drives chase FOV pushes and per-enemy camera rumble, plus vent-open and scream reactions.
- ReplicatedStorage\Services\CommunicationService.luau — Shared accessor for the ReplicatedStorage.Communication remote folders.
- ReplicatedStorage\Services\ComputerHUDService.luau — Shows the hacked/total computer counter pill and flashes it when all are done.
- ReplicatedStorage\Services\ComputerService.luau — Runs hackable computers: idle screens, camera sessions and the minigame handoff.
- ReplicatedStorage\Services\CreepRenderService.luau — Renders the Creep as a camera-facing silhouette against a hallway backdrop, with a parting distortion sweep.
- ReplicatedStorage\Services\CrouchService.luau — Owns crouch input, speed, camera drop and crouch animations.
- ReplicatedStorage\Services\DangerDebugService.luau — F4 developer panel for tuning and heatmapping the danger field.
- ReplicatedStorage\Services\DangerFieldService.luau — Procedural per-floor danger noise field, gated by distance from spawn, with baked spawn points.
- ReplicatedStorage\Services\DeathScreenService.luau — Builds and drives the glitch death screen and reports back when it finishes.
- ReplicatedStorage\Services\DeathSoundService.luau — Replaces Roblox's default death sound with the custom one at the character's position.
- ReplicatedStorage\Services\DoorService.luau — Swings room doors open near players and enemies, and applies the server's map opening regions.
- ReplicatedStorage\Services\DrawerItemService.luau — Registers drawer items as interactable pickups and requests them from the server.
- ReplicatedStorage\Services\DrawerService.luau — Animates drawers open and closed with local prediction over the server's attribute.
- ReplicatedStorage\Services\EffectsHUDService.luau — Right-edge HUD of timed effect tiles with draining icons and countdowns.
- ReplicatedStorage\Services\ElevatorDoorService.luau — Opens and closes tagged lobby elevator doors as players approach.
- ReplicatedStorage\Services\ElevatorLoadingUIService.luau — Fades the elevator loading overlay in and out around a hallway load.
- ReplicatedStorage\Services\EnemyDamageService.luau — Client-side enemy touch detection that kills the local player outside safe rooms.
- ReplicatedStorage\Services\EnemyObservationService.luau — Reports which observable models the local camera can see to the server.
- ReplicatedStorage\Services\EyeHitEffectService.luau — Blink, blur, flash and gaze-vignette screen effects for the Eye enemy.
- ReplicatedStorage\Services\EyeRenderService.luau — Bobs and aims tagged Eye models at the camera and computes gaze strength.
- ReplicatedStorage\Services\FirstPersonCameraService.luau — Walking camera bob plus custom cursor setup for first person.
- ReplicatedStorage\Services\FriendAvatarService.luau — Client-only cache that builds character models from the local player's friends' avatars.
- ReplicatedStorage\Services\FriendReviveUIService.luau — Timed revive-offer cards for downed teammates.
- ReplicatedStorage\Services\GhostMotionService.luau — Ghost drift leg math and the model-attribute protocol the server and clients share.
- ReplicatedStorage\Services\GhostRenderService.luau — Renders ghosts as translucent friend-avatar rigs driven by replicated motion.
- ReplicatedStorage\Services\GraphicsFogService.luau — Distance fog and a camera-parented cage on low graphics levels.
- ReplicatedStorage\Services\GravityWarpService.luau — Client executor for the Gravity Warper; tweens the player onto the ceiling, runs WallstickService for the warp duration, then tweens them back down.
- ReplicatedStorage\Services\GuiBuilderService.luau — Shared helper for PlayerGui access, ScreenGuis, corners and strokes.
- ReplicatedStorage\Services\HallwayCrushDamageService.luau — Client-side kill decision for the closing-walls oddity, using the local character's own position against the server's lethal intervals.
- ReplicatedStorage\Services\HallwayGraphService.luau — Navigable node graph built from tagged maze floors, with Dijkstra pathfinding and walking distance; nodes and edges touching spawn safe zones are pruned.
- ReplicatedStorage\Services\HallwayStreamingService.luau — Client handshake confirming streamed hallway models arrived before a teleport.
- ReplicatedStorage\Services\HallwaysService.luau — Geometry queries over tagged floor parts: containment, closest point, and longest straight span.
- ReplicatedStorage\Services\HearingRenderService.luau — Flies glowing motes from a noise source to an enemy's ear.
- ReplicatedStorage\Services\HeartbeatService.luau — Proximity heartbeat audio that swells and quickens near a pursuing enemy.
- ReplicatedStorage\Services\IndexUIService.luau — Paginated bestiary UI with viewport headshots and progressive text reveals.
- ReplicatedStorage\Services\InteractionService.luau — Singleton crosshair interaction target registry, highlight and key prompt.
- ReplicatedStorage\Services\InterfaceService.luau — Main menu page switching, blur, FOV pull-back and mouse unlocking.
- ReplicatedStorage\Services\InventoryUIService.luau — Custom hotbar and backpack with equipping and drag-and-drop slots.
- ReplicatedStorage\Services\ItemsUIService.luau — Item shop page with tool previews and coin or Robux purchases.
- ReplicatedStorage\Services\LanternSwayService.luau — Physics-hinged swinging for hanging lanterns during the chaos-red state.
- ReplicatedStorage\Services\LobbyService.luau — Checks whether a player is standing on the tagged lobby floor.
- ReplicatedStorage\Services\LookService.luau — Reports local camera pitch/yaw and bends other characters' neck and waist to match.
- ReplicatedStorage\Services\MarketplaceService\init.luau — Wrapper over Roblox MarketplaceService adding a shared gamepass-ownership cache, cross-boundary purchase prompts and per-product receipt handlers.
- ReplicatedStorage\Services\MarketplaceService\Gamepasses.luau — Gamepass asset ids keyed by name.
- ReplicatedStorage\Services\MarketplaceService\Products.luau — Developer-product asset ids, with per-item ids nested under Items.
- ReplicatedStorage\Services\MapControlService.luau — Pan and zoom for the map: drag or pinch to pan, wheel or pinch to zoom, clamped and eased.
- ReplicatedStorage\Services\MapInkService.luau — Rasterises the hand-drawn map ink: seeded wobble, tapered strokes and junction-aware wall culling onto the map canvas.
- ReplicatedStorage\Services\MapLayoutService.luau — Client-side map geometry: world-to-canvas projection plus the wall and cap openings that keep junctions unwalled.
- ReplicatedStorage\Services\MapService.luau — Client map front end: consumes the discovery remotes, drives the ink layer and tracks the local player marker.
- ReplicatedStorage\Services\MathService.luau — Shared pure-math helpers: easing, frame-rate independent lerp alphas, horizontal vector work, angles and pulses.
- ReplicatedStorage\Services\MimicMotionService.luau — Converts recorded movement samples into discrete key presses with reaction delay and aim drift.
- ReplicatedStorage\Services\MimicService.luau — Client driver for the Mimic enemy: mirrors your recorded movement, spins to face you, twitches and head-locks enemy necks, plays the reveal sting.
- ReplicatedStorage\Services\MinigameService.luau — Client arcade shell for hackable computers: picks the terminal's game, builds the CRT SurfaceGui and hosts one game module at a time.
- ReplicatedStorage\Services\ObservedFreezeService.luau — Client weeping-angel renderer that visually pins tagged enemies while they are in view and reconciles them when you look away.
- ReplicatedStorage\Services\PaintingDwellerShakeService.luau — Fires a one-shot Slam camera shake when the painting dweller pops.
- ReplicatedStorage\Services\PerfLogService.luau — Client performance watchdog for frame spikes, FPS drops and bursts of workspace instance churn.
- ReplicatedStorage\Services\PerfLoggerService.luau — Flag-gated startup timing log broadcast from server to all clients.
- ReplicatedStorage\Services\PlayerLocatorService.luau — Client teleport-to-player HUD with per-player markers, crosshair focus and a shared cooldown readout.
- ReplicatedStorage\Services\PlayerOddityRenderService.luau — Client renderer that turns every other player's head toward you while the stare oddity is active.
- ReplicatedStorage\Services\RecordPlayerAudioService.luau — Muffles and fades tagged in-world record players while the elevator is loading or the death screen is up.
- ReplicatedStorage\Services\RedactionService.luau — Progressive seeded word-by-word text reveal with block-glyph redaction.
- ReplicatedStorage\Services\ShakeService.luau — Client camera-shake front end with named presets, keyed sustained shakes and adjustable rumble handles.
- ReplicatedStorage\Services\ShopkeeperService.luau — Client service binding shopkeeper NPCs to interactions, smile animations and their interface page.
- ReplicatedStorage\Services\SightlineService.luau — Camera frustum and raycast visibility tests with a self-maintaining per-model part cache.
- ReplicatedStorage\Services\SpawnZoneService.luau — Shared registry of tagged spawn-safe-zone parts with point and segment queries against their boxes.
- ReplicatedStorage\Services\SpeedBoostRenderService.luau — Tweens the FOV offset and colour-correction screen effect for speed boosts.
- ReplicatedStorage\Services\SprintBoostUIService.luau — Decorated overlay drawn over the stamina bar while a speed boost is running.
- ReplicatedStorage\Services\SprintService.luau — Client sprint state machine owning stamina, exhaustion, WalkSpeed and the sprint FOV blend.
- ReplicatedStorage\Services\SprintUIService.luau — The stamina bar itself: eased fill, colour bands, exhaustion pulse and auto-fade.
- ReplicatedStorage\Services\StalkerCameraService.luau — Locks the camera onto the Stalker, anchoring the player and pushing FOV for kills.
- ReplicatedStorage\Services\StatsHUDService.luau — Debug HUD showing FPS, ping, danger-field value and a live enemy list.
- ReplicatedStorage\Services\TagService.luau — The tag-to-module pipeline: registers apply/unapply callbacks per CollectionService tag and stores the data they return.
- ReplicatedStorage\Services\ToolClientService.luau — Bootstraps tool classes for the local player's tools and routes server tool events to them.
- ReplicatedStorage\Services\TweenProxyService.luau — Tweens arbitrary values through a throwaway ValueBase and a callback, including model scaling.
- ReplicatedStorage\Services\VanishedService.luau — Checks whether a character is tagged Ignore or IgnoreExceptEye or holds a ForceField, with an Eye-specific check that skips the exempt tag.
- ReplicatedStorage\Services\ViewmodelService.luau — First-person viewmodel that clones the equipped tool under the camera with sway and bob.
- ReplicatedStorage\Services\VoiceActivityService.luau — Detects when the local player is speaking from an AudioAnalyzer and reports it to the server.
- ReplicatedStorage\Services\VoiceDebugService.luau — Debug panel of sliders for local proximity-voice and radio volumes.
- ReplicatedStorage\Services\WalkSoundService.luau — Footstep engine timing steps from locomotion animations for players and tagged enemies.
- ReplicatedStorage\Services\WalkieTalkieService.luau — Walkie-talkie mode toggle, own-emitter muting and voice-eligibility gate.
- ReplicatedStorage\Services\WallstickService.luau — Client opt-in wall-sticking for the local character plus replication rendering of other players' wall-stuck characters.

### ReplicatedStorage\Classes

- ReplicatedStorage\Classes\Animation.luau — Plays a rig's looping animation named by its Animation attribute.
- ReplicatedStorage\Classes\Breathe.luau — Procedural idle breathing motion for nearby rigs.
- ReplicatedStorage\Classes\ClientTool.luau — Client tool base class adding limb reveal, tool animations and stock consumption.
- ReplicatedStorage\Classes\Deadline.luau — Runs a function with a timeout and reports which won.
- ReplicatedStorage\Classes\DebugPanel.luau — Keyboard-toggled developer overlay with labels, buttons and sliders.
- ReplicatedStorage\Classes\DoorPart.luau — Spring and audio-driven swinging door leaf with oddity and forced-shut modes.
- ReplicatedStorage\Classes\Drawer.luau — Spring-driven sliding drawer that infers its outward axis from the handle.
- ReplicatedStorage\Classes\Hole.luau — Crawl-hole prompt that teleports the player to the twin hole with the same ID.
- ReplicatedStorage\Classes\Interaction.luau — Camera-raycast interaction system with highlight and animated key prompt.
- ReplicatedStorage\Classes\InventorySlot.luau — One hotbar slot with a viewport preview of the tool model.
- ReplicatedStorage\Classes\LocatorMarker.luau — Per-player billboard marker with headshot bubble, name plate and highlight.
- ReplicatedStorage\Classes\MapMarker.luau — One inked map symbol with a spring pop, ping ring and flash for the moment it is discovered.
- ReplicatedStorage\Classes\MapCanvas.luau — Soft-brush pixel canvas over an EditableImage with max-alpha stamping and dirty-rect flushing.
- ReplicatedStorage\Classes\MotionTrail.luau — Rolling buffer of a humanoid's recent motion samples.
- ReplicatedStorage\Classes\NpcAnimator.luau — Replaces the default Animate script for NPC locomotion, emotes and overrides.
- ReplicatedStorage\Classes\PathfinderMarker.luau — Numbered waypoint marker model for the pathfinder tool.
- ReplicatedStorage\Classes\Race.luau — Runs functions concurrently and returns the key of the first to finish.
- ReplicatedStorage\Classes\RigMotion.luau — Base class for procedural rig motions layered over the animator.
- ReplicatedStorage\Classes\Spin.luau — Rotates an instance about world Y at its RPS attribute rate.
- ReplicatedStorage\Classes\Spring.luau — Numeric spring integrator used by the door and drawer motion.
- ReplicatedStorage\Classes\StateMachine.luau — Coroutine state machine with parallel evaluators and reason-gated transitions.
- ReplicatedStorage\Classes\ToolBase.luau — Shared tool base class handling equip, activation guards and client/server signalling.
- ReplicatedStorage\Classes\ToolCounter.luau — On-screen remaining/total count readout for a tool.
- ReplicatedStorage\Classes\Vow.luau — Cancellable single-function thread wrapper backing the state machine.
- ReplicatedStorage\Classes\Watch.luau — Turns an NPC's neck and waist to look at the local player.
- ReplicatedStorage\Classes\CameraShaker\ — Vendored third-party camera shake library used through ShakeService.
- ReplicatedStorage\Classes\Wallstick\ — Vendored EgoMoose Rbx-Wallstick surface-sticking controller (modernized constraints), driven through WallstickService; self-contained — patches the live camera and swaps animation/sound drivers only while enabled.
- ReplicatedStorage\Classes\Minigames\MinigameBase.luau — Base class every terminal minigame extends, providing themed GUI builders, input helpers, heartbeat and win/fail plumbing.
- ReplicatedStorage\Classes\Minigames\AimTrainer.luau — Click-the-target minigame; 20 hits on shrinking timers, 3 misses wipe the run.
- ReplicatedStorage\Classes\Minigames\Frogger.luau — Frogger minigame; cross six lanes of traffic twice without being hit.
- ReplicatedStorage\Classes\Minigames\Memory.luau — 4x4 emoji pair-matching minigame with a 20-move limit.
- ReplicatedStorage\Classes\Minigames\Minesweeper.luau — 8x8 Minesweeper minigame with flag mode and a safe first click.
- ReplicatedStorage\Classes\Minigames\Simon.luau — Simon-says minigame; repeat a growing four-pad sequence up to length seven.
- ReplicatedStorage\Classes\Minigames\Snake.luau — Snake minigame on a 16x12 grid; eat fifteen pellets as the tick speeds up.
- ReplicatedStorage\Classes\Tools\Ball.luau — Client ball tool; throws a ball prop at a targeted enemy and reports the hit to the server.
- ReplicatedStorage\Classes\Tools\Pathfinder.luau — Client pathfinder tool; drops limited, shaded breadcrumb markers on the floor.
- ReplicatedStorage\Classes\Tools\Player Locator.luau — Client tool that enables PlayerLocatorService while equipped.
- ReplicatedStorage\Classes\Tools\Shovel.luau — Client shovel tool; plays the dig sequence and asks the server to create an escape hole.
- ReplicatedStorage\Classes\Tools\SpellBook.luau — Client spell book tool that gates activation on its cast animation.
- ReplicatedStorage\Classes\Tools\Visor.luau — Client visor tool that tweens a shared Lighting color correction while equipped.
- ReplicatedStorage\Classes\Tools\Walkie Talkie.luau — Client tool that enables WalkieTalkieService while equipped.

### ReplicatedStorage\Configs

- ReplicatedStorage\Configs\AmbienceConfig.luau — Distance falloff and fade timing for ambient sound emitters.
- ReplicatedStorage\Configs\AnimationConfig.luau — Animation asset ids and per-enemy animation sets.
- ReplicatedStorage\Configs\BreatheConfig.luau — Idle breathing joint motion settings.
- ReplicatedStorage\Configs\CameraBobConfig.luau — Walk-cycle camera bob amplitude and cadence.
- ReplicatedStorage\Configs\ChaosLightConfig.luau — Red hallway-light warning settings for the Chaos enemy.
- ReplicatedStorage\Configs\ChaseMusicConfig.luau — Per-enemy chase music tracks, ranges and fades.
- ReplicatedStorage\Configs\ChaserCameraConfig.luau — Chase camera FOV changes and per-enemy shake profiles.
- ReplicatedStorage\Configs\ComputerAssets.luau — Image asset ids for the hackable-computer UI.
- ReplicatedStorage\Configs\ComputerConfig.luau — Hackable computer objective: interaction, camera, screen and HUD settings.
- ReplicatedStorage\Configs\CreepConfig.luau — Creep enemy light-killing, backdrop geometry and eye-pair settings.
- ReplicatedStorage\Configs\CrouchConfig.luau — Crouch movement, camera drop, stealth and touch button settings.
- ReplicatedStorage\Configs\DangerConfig.luau — Danger-field noise generation and Director enemy population settings.
- ReplicatedStorage\Configs\DeathConfig.luau — Death causes, player hints and the killed-by death screen styling.
- ReplicatedStorage\Configs\DoorConfig.luau — Swinging door physics and proximity open/close behaviour.
- ReplicatedStorage\Configs\DrawerConfig.luau — Openable drawer motion, interaction, sound and prompt UI settings.
- ReplicatedStorage\Configs\DrawerItemConfig.luau — Drawer loot spawn rates, rarity weights and item table; clones DrawerConfig's Input/UI at load.
- ReplicatedStorage\Configs\EffectsHUDConfig.luau — Layout, colours and icons for the HUD effect tiles.
- ReplicatedStorage\Configs\ElevatorConfig.luau — Elevator door motion, proximity and teleport fade settings.
- ReplicatedStorage\Configs\EyeConfig.luau — Eye enemy tracking, hit reaction and gaze screen-effect settings.
- ReplicatedStorage\Configs\FLAGS.luau — Global on/off switches for major systems and debug output.
- ReplicatedStorage\Configs\GhostConfig.luau — Ghost enemy turn, bob and fade timing.
- ReplicatedStorage\Configs\GraphicsFogConfig.luau — Fog quality levels, fog cage and automatic FPS-driven adjustment.
- ReplicatedStorage\Configs\HearingConfig.luau — Sound-travel visualisation settings for the Blind enemy's hearing.
- ReplicatedStorage\Configs\HeartbeatConfig.luau — Proximity heartbeat sound settings for the Blind enemy.
- ReplicatedStorage\Configs\IndexConfig.luau — Enemy Index UI styling, reveal animation and all bestiary entries.
- ReplicatedStorage\Configs\InventoryConfig.luau — Hotbar/backpack sizes, keybinds and inventory slot styling.
- ReplicatedStorage\Configs\ItemShopConfig.luau — Item shop catalogue, prices, viewport framing and card animation settings.
- ReplicatedStorage\Configs\LanternSwayConfig.luau — Tuning for the swinging hallway lantern simulation.
- ReplicatedStorage\Configs\LookConfig.luau — Replicated aim/look angle limits and neck-waist blend weights.
- ReplicatedStorage\Configs\MapConfig.luau — Map discovery radius, canvas resolution, hand-drawn ink style, danger layer and marker tuning.
- ReplicatedStorage\Configs\MapOddityConfig.luau — Roll timings and per-effect tuning for hallway/map oddities.
- ReplicatedStorage\Configs\MimicConfig.luau — Behaviour tuning for the Mimic enemy's reactions, reveal and movement.
- ReplicatedStorage\Configs\ObservedFreezeConfig.luau — Tag, attribute and tolerances for freeze-when-observed enemies.
- ReplicatedStorage\Configs\PerkConfig.luau — Per-perk settings for the gamepass/perk system.
- ReplicatedStorage\Configs\PlayerLocatorConfig.luau — Marker layout, focus animation and palette for the Player Locator tool.
- ReplicatedStorage\Configs\PlayerOddityConfig.luau — Roll timings and effect weights for player-character oddities.
- ReplicatedStorage\Configs\PropOddityConfig.luau — Per-effect tuning for falling lanterns, falling paintings and the painting dweller.
- ReplicatedStorage\Configs\ShopkeeperConfig.luau — Shopkeeper NPC tag, reach, input bindings and prompt UI styling.
- ReplicatedStorage\Configs\SpawnZoneConfig.luau — Tag, poll interval and repel cooldown for the spawn safe zone system.
- ReplicatedStorage\Configs\SprintBoostConfig.luau — Visual definitions for speed-boost auras on the sprint bar.
- ReplicatedStorage\Configs\SprintConfig.luau — Sprint speed, stamina economy, input bindings and stamina bar styling.
- ReplicatedStorage\Configs\StatsHUDConfig.luau — Layout and thresholds for the debug stats HUD panel.
- ReplicatedStorage\Configs\StreamingConfig.luau — Corridor streaming prediction, reconciliation and tag settings (currently disabled).
- ReplicatedStorage\Configs\ToolConfigs.luau — Per-tool tags and behaviour values for every usable tool.
- ReplicatedStorage\Configs\ViewmodelConfig.luau — First-person viewmodel placement, sway, bob and per-tool overrides.
- ReplicatedStorage\Configs\VoiceChatConfig.luau — Proximity voice chat volume, distance and activity detection settings.
- ReplicatedStorage\Configs\VoiceDebugConfig.luau — Slider definitions for the F6 voice volume debug panel, holding live config references.
- ReplicatedStorage\Configs\WalkSoundConfig.luau — Footstep sound rate and per-enemy step volume overrides.
- ReplicatedStorage\Configs\WalkieTalkieConfig.luau — Radio ranges, volumes, modes and the walkie-talkie DSP effect chain.
- ReplicatedStorage\Configs\WatchConfig.luau — Range, angle limits and joint weights for NPC head tracking of the local player.

### ReplicatedStorage\Modules

- ReplicatedStorage\Modules\extend.luau — Metatable mixin that forwards a table's reads and writes to fallback tables or Instances.
- ReplicatedStorage\Modules\Tagger.luau — Client tag bootstrap wiring Hole, Spin, Watch, and Breathe tags to their classes.

### ReplicatedStorage\Frameworks

- ReplicatedStorage\Frameworks\xenterface\init.luau — Root facade of the xenterface UI framework; boots its Tagger and exposes Controller/Get/Wait.
- ReplicatedStorage\Frameworks\xenterface\Modules\Tagger.luau — Registers the framework's Tab, Page and Hover tag listeners against PlayerGui.
- ReplicatedStorage\Frameworks\xenterface\Services\ControllerService.luau — Registry that hands out one shared Controller per page group.
- ReplicatedStorage\Frameworks\xenterface\Services\ElementService.luau — Looks up GuiObjects by their ElementId attribute, with a yielding Wait.
- ReplicatedStorage\Frameworks\xenterface\Classes\Controller.luau — Tracks the active page of a group and drives the tab/page transition animations.
- ReplicatedStorage\Frameworks\xenterface\Classes\Hover.luau — Toggle subclass that plays its sequences on MouseEnter and MouseLeave.
- ReplicatedStorage\Frameworks\xenterface\Classes\Page.luau — Toggle subclass representing a page shown or hidden by a Controller.
- ReplicatedStorage\Frameworks\xenterface\Classes\Sequence.luau — Parses the framework's compact animation strings and plays them as tweens.
- ReplicatedStorage\Frameworks\xenterface\Classes\Signal.luau — BindableEvent wrapped into a single signal object.
- ReplicatedStorage\Frameworks\xenterface\Classes\Tab.luau — Clickable tab that fires its page group's controller with its PageId.
- ReplicatedStorage\Frameworks\xenterface\Classes\Toggle.luau — Base class resolving Active/Inactive sequences from presets and attributes.
- ReplicatedStorage\Frameworks\xenterface\Config\ParameterConfig.luau — Keyword, property and operation tables for the sequence animation language.
- ReplicatedStorage\Frameworks\xenterface\Config\PresetConfig.luau — Named animation presets referenced by the Preset attribute.

### ServerScriptService

- ServerScriptService\Init.legacy.luau — Server bootstrap; requires every ServerStorage Service and runs the server Tagger.

### ServerStorage\Services

- ServerStorage\Services\BadgeService.luau — Awards and caches Roblox badges limited to the ids listed in BadgeConfigs.
- ServerStorage\Services\CeilingVentService.luau — Springs ceiling vents on approaching players and drops a CeilingDweller through them, after a telegraphed ceiling walk-in where the dweller crawls into the vent.
- ServerStorage\Services\ChaosService.luau — Plans a looping hallway route with timed light and oddity warnings, then spawns Chaos to walk it.
- ServerStorage\Services\ChaseFlickerService.luau — Flickers the lights around a player being chased by a CeilingDweller or Mimic.
- ServerStorage\Services\ChatCommandService.luau — Shared registry and dispatcher for `/` chat commands with an admin gate.
- ServerStorage\Services\ComputerCommandService.luau — Admin `/hack` command for listing, teleporting to, and force-setting computers.
- ServerStorage\Services\ComputerService.luau — Tracks and replicates which computers each player has hacked.
- ServerStorage\Services\CrouchService.luau — Mirrors the client's crouch state onto the character as a stealth attribute.
- ServerStorage\Services\DangerDebugService.luau — Studio-only hook that rebakes the danger map from the client debug panel.
- ServerStorage\Services\DangerMapService.luau — Bakes the map-wide danger field and serves weighted spawn points from it.
- ServerStorage\Services\DataSaveService.luau — Loads, reconciles and releases per-player ProfileService profiles.
- ServerStorage\Services\DeathService.luau — Records the cause of each player's death and drives the death screen and revive offers.
- ServerStorage\Services\DevProductService.luau — Wires every developer product in DevProductConfigs to a receipt handler.
- ServerStorage\Services\DrawerItemService.luau — Stocks drawers with pickable item displays and handles pickup requests.
- ServerStorage\Services\DrawerService.luau — Owns drawer open/closed state, sounds, and auto-closing.
- ServerStorage\Services\ElevatorService.luau — Teleports players from the lobby elevator into the maze with fade, loading and streaming.
- ServerStorage\Services\EnemyCommandService.luau — Developer chat commands for spawning, listing and despawning enemies.
- ServerStorage\Services\EnemyDebugService.luau — Broadcasts a periodic snapshot of active enemies to the stats HUD.
- ServerStorage\Services\EnemyDirectorService.luau — Manages the live enemy population: spawning, placement scoring and despawning.
- ServerStorage\Services\EnemyDiscoveryService.luau — Tracks and persists per-player bestiary discovery progress for each enemy.
- ServerStorage\Services\EnemyObservationService.luau — Holds each client's validated report of which enemies it can see and from where.
- ServerStorage\Services\EnemyService.luau — Enemy factory and active-enemy registry, including collision group setup.
- ServerStorage\Services\EyeHitService.luau — Guarantees the Enemies/EyeHit RemoteEvent exists and returns it.
- ServerStorage\Services\FixtureCommandService.luau — Registers a chat command to teleport to or force-drop a pool's nearest fixture.
- ServerStorage\Services\FriendReviveService.luau — Paid "revive your friend" offers, friend checks and the product receipt that grants the revive.
- ServerStorage\Services\GamepassService.luau — Caches each player's gamepass ownership at join and keeps it current after purchases.
- ServerStorage\Services\GazeService.luau — Server line-of-sight library for cone and raycast visibility checks, with a seen/unseen tracker.
- ServerStorage\Services\GhostAreaService.luau — Picks area-weighted hover points over hallways for the Ghost, avoiding nearby players.
- ServerStorage\Services\HallwayGridService.luau — Finds hallway corner mouths near a viewer for placing things just out of sight.
- ServerStorage\Services\HallwayRegionService.luau — Straight-hallway span helpers for matching, bounding, occupancy and weighted random picks.
- ServerStorage\Services\HallwayWallService.luau — Wall-level geometry for a straight hallway: junction mouths per side, the both-side cut list that keeps opposite walls aligned, and the tagged wall strips flanking the span.
- ServerStorage\Services\HallwayStreamingService.luau — Custom per-player streaming: slices the maze into hallway chunks and gates teleports on them.
- ServerStorage\Services\HearingService.luau — Registry of "ears" that receive NoiseService noises after a distance-based travel delay.
- ServerStorage\Services\HideSpotService.luau — Finds a standing spot on the maze floor that breaks line of sight from every enemy eye.
- ServerStorage\Services\HoleService.luau — Creates and expires linked entry/exit hole pairs for the Shovel's dig.
- ServerStorage\Services\InventoryService.luau — Authoritative slot-ordered backpack/hotbar with client sync and profile persistence.
- ServerStorage\Services\InvincibleCommandService.luau — Admin /invincible toggle that tags a character as Vanished so nothing can touch it.
- ServerStorage\Services\ItemShopService.luau — Coin and Robux item shop with voice gating, receipt dedupe and inventory grants.
- ServerStorage\Services\LanternFallService.luau — Fixture pool that arms lanterns and drops one when a player approaches.
- ServerStorage\Services\LanternSwingCommandService.luau — /lantern swing command that flags the nearest swayable lantern red for a duration.
- ServerStorage\Services\LightService.luau — Central control of every tagged light model: reference-counted blackout claims and flicker effects.
- ServerStorage\Services\LoadoutService.luau — Captures and restores a player's tools, quantities and attributes across inventory wipes.
- ServerStorage\Services\LookService.luau — Stores clamped client camera pitch/yaw on characters and mirrors it onto mimic enemies.
- ServerStorage\Services\MapDiscoveryService.luau — Server owner of per-player map discovery: unions walked hallway intervals, persists them to the profile and replicates them.
- ServerStorage\Services\MapCommandService.luau — Admin /map command that sends the caller straight into the maze.
- ServerStorage\Services\MapOddityCommandService.luau — /mapoddity chat command mapping friendly words to map oddity kinds.
- ServerStorage\Services\MapOddityService.luau — Scope wrapper for starting, warning about and clearing map-scope oddities.
- ServerStorage\Services\NoiseService.luau — Emits and tracks noise events, including automatic footstep noise scaled by crouch/sprint.
- ServerStorage\Services\OddityService.luau — Registry, config merging, ambient spawn loops and lifecycle for every oddity class.
- ServerStorage\Services\PaintingDwellerService.luau — FixturePool wrapper that arms and triggers the painting dweller oddity, plus its /dweller command.
- ServerStorage\Services\PaintingFallService.luau — FixturePool wrapper that arms and drops falling paintings, plus its /painting command.
- ServerStorage\Services\PeekSpotService.luau — Geometry search for corners an enemy can hide behind and lean out of into the player's view.
- ServerStorage\Services\PerkService.luau — Resolves gamepass ownership and applies the double speed, visor and keep-items perks on spawn.
- ServerStorage\Services\PlayerCharacterStreamingService.luau — Marks every player character as persistent so it is never streamed out.
- ServerStorage\Services\PlayerLocatorService.luau — Cooldown-gated teleport behind another player for the Player Locator tool.
- ServerStorage\Services\PlayerOddityCommandService.luau — Registers the /oddity chat command for triggering player oddities by effect and target.
- ServerStorage\Services\PlayerOddityService.luau — Randomly applies one weighted player-scope oddity at a time to a living player.
- ServerStorage\Services\ProfileService.luau — Vendored third-party datastore session-locking library (loleris' ProfileService).
- ServerStorage\Services\ProgrammaticVentService.luau — Spawns and despawns extra ceiling vents at unseen danger-map points at runtime.
- ServerStorage\Services\RatService.luau — CrossingPool wrapper that arms two hallway crossings and sends a rat scurrying across one on approach, plus its /rat command.
- ServerStorage\Services\RecordPlayerService.luau — Loops the record (or lobby record) sound on every tagged record player model.
- ServerStorage\Services\ReviveService.luau — Sells and grants the Revive product, restoring the player's death location, items and a ForceField.
- ServerStorage\Services\RoomService.luau — Tags rooms, gives them enemy-only pathfinding blockers, and tracks which room each player is in.
- ServerStorage\Services\SistersService.luau — Spawns the Sisters enemy to walk a danger-weighted straight hallway span.
- ServerStorage\Services\SpawnZoneGuardService.luau — Tags players inside the spawn safe zone as Ignored and repels NPC enemies that touch it back to patrol.
- ServerStorage\Services\SpeedBoostService.luau — Central WalkSpeed arbiter for named, expiring speed boosts and perk multipliers.
- ServerStorage\Services\StalkerService.luau — Spawns stalker-type enemies at a peek spot found behind the player.
- ServerStorage\Services\StunService.luau — Stuns enemy NPCs and Eyes, and validates client ball-hit reports by range.
- ServerStorage\Services\ToolCommandService.luau — Admin-only /give chat command for handing out tools by name and amount.
- ServerStorage\Services\ToolService.luau — Binds tagged Tools to their server tool classes and routes client tool events to them.
- ServerStorage\Services\VoiceActivityService.luau — Tunes voice chat audio and emits noise at whoever is speaking so enemies can hear them.
- ServerStorage\Services\VoiceDebugService.luau — Studio-only remote for live-tweaking voice and radio volumes behind the VoiceDebug flag.
- ServerStorage\Services\WalkieTalkieService.luau — Builds the per-player radio audio graph, privacy modes, sound relays and radio noise.
- ServerStorage\Services\WallstickService.luau — Server bootstrap for Wallstick: collision groups, the workspace Wallstick model, per-player streaming foci and the replication listener.

### ServerStorage\Classes

- ServerStorage\Classes\EnemyBase.luau — Minimal base class for non-humanoid enemies, owning tags, the active flag and a lingering despawn.
- ServerStorage\Classes\FixturePool.luau — Keeps tagged hallway fixtures armed near players and drops them as oddities on approach.
- ServerStorage\Classes\CrossingPool.luau — Keeps sampled hallway crossing points armed near players and starts an oddity there on approach.
- ServerStorage\Classes\NPC.luau — Full humanoid-enemy base: pathfinding, pursuit, sight and observation checks, targeting, and shared Idle/Wander/Patrol states.
- ServerStorage\Classes\Healer.luau — Server tool that consumes a charge and heals the holder.
- ServerStorage\Classes\FixtureFall.luau — Prop oddity that unanchors and drops a fixture, with the shared "safe to repair yet" test and exact restore.
- ServerStorage\Classes\HallwayOddity.luau — Base class for map-scope oddities that occupy a hallway span.
- ServerStorage\Classes\ServerTool.luau — Server-side tool base class; ToolBase plus inventory consumption.
- ServerStorage\Classes\Sound.luau — Attaches an ambient AudioEmitter clone to a tagged instance from its Sound attribute.
- ServerStorage\Classes\SpeedDrink.luau — Server tool that plays a drink sequence and grants a temporary speed boost.
- ServerStorage\Classes\SurfaceWalker.luau — Kinematic wall/ceiling locomotion for any humanoid rig or NPC; walks a rig along surface contact points with animation.
- ServerStorage\Classes\TrapObject.luau — Placeable trap that snaps shut and stuns the first NPC to touch it.
- ServerStorage\Classes\Enemies\Blind.luau — Hearing-driven hunter whose determination builds from noise and decays in silence.
- ServerStorage\Classes\Enemies\CeilingDweller.luau — Chaser that drops from the ceiling onto its victim before hunting normally.
- ServerStorage\Classes\Enemies\Chaos.luau — Fast hazard that sweeps a precomputed route, killing everything along the segment.
- ServerStorage\Classes\Enemies\Chaser.luau — Plain sight-based pursuer with visual variants; the template most humanoid enemies extend.
- ServerStorage\Classes\Enemies\Creep.luau — Stationary eye-cluster that kills the hallway lights and despawns when approached.
- ServerStorage\Classes\Enemies\Eye.luau — Static hazard that damages players by view angle for looking at it.
- ServerStorage\Classes\Enemies\Ghost.luau — Floating enemy that drifts on published motion legs and lurks unseen in dangerous hallways.
- ServerStorage\Classes\Enemies\Mimic.luau — Copies a player's appearance and acts out odd encounter modes before revealing and chasing.
- ServerStorage\Classes\Enemies\Sisters.luau — Twinned anchored figures that tween down a hallway, killing along their path.
- ServerStorage\Classes\Enemies\Stalker.luau — Tails a player from behind unseen, flees to cover when observed, and seizes the camera to kill.
- ServerStorage\Classes\Enemies\WeepingAngel.luau — Chaser that freezes solid whenever any player is observing it.
- ServerStorage\Classes\Enemies\Behaviors\Peek.luau — Shared state functions for hiding at a spot, leaning into view, and pulling back.
- ServerStorage\Classes\Oddity.luau — Root oddity class: token, merged settings, timed start/stop lifecycle and subclass factory.
- ServerStorage\Classes\PropOddity.luau — Intermediate oddity base whose context is a prop Model in the workspace.
- ServerStorage\Classes\PlayerOddity.luau — Intermediate oddity base whose context is a Player, auto-stopping on death.
- ServerStorage\Classes\Oddities\CeilingSisters.luau — Map oddity that walks two translucent, harmless Sister rigs upside down along the hallway ceilings, pathfinding between random graph nodes forever while both heads track the nearest player.
- ServerStorage\Classes\Oddities\ChaosWarning.luau — Hallway oddity that slams every nearby door open and shut as a telegraph.
- ServerStorage\Classes\Oddities\DoorsOpen.luau — Hallway oddity that swings all doors in an occupied span open and holds them.
- ServerStorage\Classes\Oddities\HallwayBlocker.luau — Hallway oddity that drops a gate prop into an unseen corridor to wall it off.
- ServerStorage\Classes\Oddities\HallwayChaos.luau — Hallway oddity combining chaotic light flicker with slamming doors.
- ServerStorage\Classes\Oddities\HallwayCrush.luau — Hallway oddity that closes both walls of a corridor inward until they seal, dragging the pilasters, lanterns, paintings and doors with them and crushing whoever is left inside.
- ServerStorage\Classes\Oddities\HallwayVoid.luau — Hallway oddity that cuts a bottomless pit into the corridor floor and kills whoever falls in.
- ServerStorage\Classes\Oddities\LanternFall.luau — Fixture-fall oddity that drops a ceiling lantern and kills its light while down.
- ServerStorage\Classes\Oddities\PaintingDweller.luau — Prop oddity that bursts a humanoid rig out of a painting canvas and attacks nearby players.
- ServerStorage\Classes\Oddities\PaintingFall.luau — Fixture-fall oddity that shoves a wall painting off the wall with spin.
- ServerStorage\Classes\Oddities\RatScurry.luau — Runs a rat across a hallway from one wall to the other and destroys it on the far side.
- ServerStorage\Classes\Oddities\PlayerHeadStare.luau — Player oddity that runs the client head-stare effect when enough players are alive.
- ServerStorage\Classes\Oddities\PlayerSize.luau — Player oddity that rescales the victim's character to a random configured size.
- ServerStorage\Classes\Oddities\PlayerTransparency.luau — Player oddity that makes the victim's character parts near-invisible.
- ServerStorage\Classes\Oddities\Transparency.luau — Hallway oddity that fades out every world part inside a hallway box.
- ServerStorage\Classes\Tools\Bandage.luau — Server half of the Bandage tool; a plain Healer subclass.
- ServerStorage\Classes\Tools\Energy Drink.luau — Server half of the Energy Drink tool; a plain SpeedDrink subclass.
- ServerStorage\Classes\Tools\Flashlight.luau — Server half of the flashlight, toggling the handle spotlight on activation.
- ServerStorage\Classes\Tools\Gravity Warper.luau — Server half of the gravity warper; consumes one, tags the character IgnoreExceptEye for the warp duration and cues the client tween.
- ServerStorage\Classes\Tools\Medkit.luau — Server half of the Medkit tool; a plain Healer subclass.
- ServerStorage\Classes\Tools\Pathfinder.luau — Server half of the Pathfinder, spending a use per placed marker unless the perk is owned.
- ServerStorage\Classes\Tools\Soda.luau — Server half of the Soda tool; a plain SpeedDrink subclass.
- ServerStorage\Classes\Tools\SpellBook.luau — Server half of the spell book, vanishing and freezing the caster through the cast animation.
- ServerStorage\Classes\Tools\Trap.luau — Server half of the bear trap, placing trap props and pruning the oldest.
- ServerStorage\Classes\Tools\Visor.luau — Server half of the visor, wearing a face accessory and hiding competing ones.
- ServerStorage\Classes\Tools\Walkie Talkie.luau — Server half of the walkie talkie, registering the owner with WalkieTalkieService.

### ServerStorage\Configs

- ServerStorage\Configs\BadgeConfigs.luau — Empty placeholder table for badge award settings.
- ServerStorage\Configs\DevProductConfigs.luau — Empty placeholder table for developer product definitions.
- ServerStorage\Configs\DiscoveryConfig.luau — Sight, proximity, event and death discovery gain rates per enemy, with a defaults resolver.
- ServerStorage\Configs\EnemyConfigs.luau — Master per-enemy stat table for models, movement, senses, damage and spawn budgeting.
- ServerStorage\Configs\GamepassConfigs.luau — Empty placeholder table for gamepass definitions.

### ServerStorage\Modules

- ServerStorage\Modules\Tagger.luau — Server tag bootstrap wiring TrapObject, Sound and Animation tags to their classes.

### StarterPlayer

- StarterPlayer\StarterPlayerScripts\Init.local.luau — Client bootstrap; requires every ReplicatedStorage Service and runs the client Tagger.
