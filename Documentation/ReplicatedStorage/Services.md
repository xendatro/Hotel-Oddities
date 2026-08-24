# ReplicatedStorage / Services

Self-initializing at require time via the Init scripts. Never add an `:Init()` method.

### AimService.luau
Tiny math helper for pointing something at a target and easing a rotation toward a goal frame-rate-independently.
- API: `Aim.Toward(position: Vector3, target: Vector3) -> CFrame` — rotation-only look-at
- API: `Aim.Ease(rotation: CFrame, goal: CFrame, rate: number, deltaTime: number) -> CFrame` — exponential lerp toward goal

### AmbienceService.luau
Client-only. Cycles the AudioPlayers under `ReplicatedStorage.Sounds.Ambience` one after another through a dedicated `AmbienceDuck` fader, fading that fader down as the walking distance to the nearest tagged enemy shrinks. Swaps to a looping `DeathAmbience` track while the death screen is up, and goes silent entirely on the lobby floor.
- API: no public methods — runs entirely from its own Heartbeat connection.
- Tags: reads `Enemy`
- Requires: `Configs.AmbienceConfig`, `Services.HallwayGraphService`, `DeathScreenService`, `LobbyService`, `AudioService`

### AudioService.luau
Central sound playback helper covering both the new `AudioPlayer`/`AudioEmitter` API and legacy `Sound` instances. Clones templates out of `ReplicatedStorage.Sounds`, wires them to named `AudioFader` buses under `workspace.Sounds`, keeps their volume tied to the bus, and destroys them when they end. Client playback of a `RadioAllowed` template is also relayed to the server so walkie-talkies can rebroadcast it.
- API: `AudioService:GetOutput() -> AudioDeviceOutput` — lazily creates the shared `AudioDeviceOutput`
- API: `AudioService:GetBus(name: string) -> AudioFader` — indexes `workspace.Sounds` by name
- API: `AudioService:Wire(source: Instance, target: Instance) -> Wire` — creates a `Wire` parented to the source
- API: `AudioService:GetPlaybackBounds(player: AudioPlayer) -> (number, number)` — clamped min/max of the playback region
- API: `AudioService:Create3DSound(template: string | AudioEmitter, parent: BasePart, looped: boolean, soundGroup: string, settings: {[string]: any}?) -> AudioPlayer` — clones an emitter onto the part without playing it
- API: `AudioService:Play3DSound(template: string | AudioEmitter, parent: BasePart, looped: boolean, soundGroup: string, settings: {[string]: any}?) -> AudioPlayer` — as above, then plays and relays to radio
- API: `AudioService:Play2D(template: Instance, looped: boolean, soundGroup: string, settings: {[string]: any}?, target: Instance?) -> AudioPlayer | Sound` — non-positional playback; accepts a `Sound`, `AudioPlayer`, or `AudioEmitter`
- API: `AudioService:FindTemplate(name: string) -> Instance?` — finds a named template that actually has an asset set
- API: `AudioService:Play2DSound(name: string, looped: boolean, soundGroup: string, settings: {[string]: any}?, target: Instance?) -> AudioPlayer | Sound` — `Play2D` by template name
- API: `AudioService:StopSound(player: AudioPlayer | Sound)` — stops and destroys the player (or its emitter)
- API: `AudioService:AdjustSoundGroup(soundGroupName: string, newVolume: number)` — sets a bus volume
- Remotes: `WalkieTalkie/TransmitSound` (fired, client only — `Start`/`Stop`/`Loop`/`Sync` actions)
- Tags: reads `RadioAllowed`
- Requires: `Configs.WalkieTalkieConfig`; lazily requires `ServerStorage.Services.WalkieTalkieService` on the server

### BobService.luau
Sine-wave vertical bobbing helper: pick a random phase once, then sample a Y offset each frame.
- API: `Bob.NewPhase() -> number` — random phase in [0, 2pi)
- API: `Bob.Offset(clock: number, phase: number, height: number, period: number) -> Vector3` — Y-axis sine offset

### CameraFovService.luau
Client-only. Owns additive field-of-view offsets so multiple effects can push the camera FOV without fighting each other: each caller registers a named offset, the total is applied on a render step above the camera priority, and the raw FOV is restored when nothing is registered.
- API: `CameraFovService:SetOffset(name: string, degrees: number)` — set or clear (near-zero) a named offset
- API: `CameraFovService:GetOffset() -> number` — current summed offset
- API: `CameraFovService:TweenOffset(name: string, degrees: number, tweenInfo: TweenInfo)` — tweens one named offset, cancelling any prior tween of that name

### CeilingVentDoorService.luau
Client-only, gated on `FLAGS.Enemies`. Listens for the server's ceiling-vent door commands and tweens the named door part's pivot to the target CFrame, cancelling any tween already running on that part.
- API: no public methods — runs entirely from its remote connection.
- Remotes: `Enemies/CeilingVentDoor` (listened)
- Requires: `Configs.FLAGS`, `TweenProxyService`

### ChaosLightService.luau
Client-only. Watches `Floor1Light` models for the server-set `ChaosRed` attribute; when set it recolours every `Light` under the model to the config red, then releases it back to the captured baseline once the nearest `Chaos` model has passed by (or after a grace period from the server clearing the attribute).
- API: `ChaosLightService:IsRed(model: Model) -> boolean` — whether that light model is currently forced red
- Tags: listens `Floor1Light`; reads `Chaos`
- Requires: `Configs.ChaosLightConfig`, `MathService`, `TagService`

### ChaosWarningSoundService.luau
Client-only. Tracks the "ChaosWarning" regions the server announces over `MapDoors`, and if the player is in a hallway (or a room whose doorway touches that region) plays looping `ChaosHallwayAmbience` emitters from an invisible anchor at the nearest point in the hallway, plus a one-shot `ChaosIncoming` sting when first coming within 24 studs.
- API: no public methods — runs entirely from its own connections.
- Remotes: `Oddities/MapDoors` (listened; only `marker == "ChaosWarning"` payloads)
- Requires: `Services.HallwaysService`, `AudioService`, `CharacterService`; hard-coded lookup of `workspace.Maze15.Rooms` / `.Doors`

### CharacterService.luau
Shared client/server helper for the common "is this player's character usable right now" checks, plus two small player-lifecycle utilities. Every function is defined with a dot, so call them with a dot.
- API: `CharacterService.GetHumanoid(character: Model?) -> Humanoid?` — nil-safe `FindFirstChildOfClass("Humanoid")`
- API: `CharacterService.IsAlive(character: Model?) -> boolean` — has a humanoid with `Health > 0`
- API: `CharacterService.GetAliveRootFromCharacter(character: Model?) -> BasePart?` — the `HumanoidRootPart`, or nil if missing/dead
- API: `CharacterService.GetAliveRoot(player: Player) -> BasePart?` — same for `player.Character`
- API: `CharacterService.GetAliveHumanoid(player: Player) -> Humanoid?` — the humanoid, or nil if missing/dead
- API: `CharacterService.GetPosition(player: Player) -> Vector3?` — position of the alive root
- API: `CharacterService.ForEachPlayer(callback: (player: Player) -> ()) -> RBXScriptConnection` — runs for every present player (spawned) and every future join; returns the `PlayerAdded` connection
- API: `CharacterService.CleanupOnLeave(map: { [Player]: any }) -> RBXScriptConnection` — clears the player's entry from a table on `PlayerRemoving`

### ChaseMusicService.luau
Client-only, gated on `FLAGS.Enemies`. For every tagged enemy that has a chase target, looks up its layered music entry in `ChaseMusicConfig`, and cross-fades the corresponding looping 2D tracks by proximity to the camera. Warns once per template name that is missing from `ReplicatedStorage.Sounds` and then stays silent.
- API: no public methods — runs entirely from its Heartbeat connection.
- Tags: reads `Enemy`
- Requires: `Configs.ChaseMusicConfig`, `MathService`, `TagService`, `AudioService`

### ChaserCameraService.luau
Gated on `FLAGS.Enemies`. Drives camera reactions to enemies chasing the local player: a fading FOV offset while a ceiling dweller or mimic is hunting, and per-enemy dynamic rumble shakes scaled by distance from `ChaserCameraConfig.ChaseShakes`. Also reacts to the server's vent-open and scream phases with one-shot shakes and a scream sound.
- API: `ChaserCameraService:IsActive() -> boolean` — whether any chase camera effect is currently running (returns `false` when the flag is off)
- Remotes: `Enemies/CeilingDwellerCamera` (listened; `Open` / `Scream` phases)
- Tags: reads `Enemy`
- Requires: `Configs.ChaserCameraConfig`, `ShakeService`, `CameraFovService`, `MathService`, `AudioService`

### CommunicationService.luau
Shared accessor for `ReplicatedStorage.Communication`. On the server it creates the folder if it is missing; on the client it waits for it. All three functions are defined with a dot and return the remote as `any`, so cast at the call site.
- API: `CommunicationService.Get(folderName: string, remoteName: string) -> any` — waits for the topic folder and the remote inside it (yields)
- API: `CommunicationService.Find(folderName: string, remoteName: string) -> any` — non-yielding lookup; nil if anything is missing
- API: `CommunicationService.Ensure(folderName: string, remoteName: string, className: string?) -> any` — creates the folder and the remote if absent; `className` defaults to `"RemoteEvent"`

### ComputerHUDService.luau
Client-only. Builds the small "hacked / total" pill in the top-right corner, counting every `HackComputer` model in the workspace and asking `ComputerService` which are done. Hidden when there are no computers, and pulses its stroke and text once all of them are hacked.
- API: `ComputerHUDService:GetProgress() -> (number, number)` — hacked count and total count
- Tags: reads `HackComputer`
- Requires: `Configs.ComputerConfig`, `ComputerService`, `GuiBuilderService`; optionally `Configs.ComputerAssets` for the icon image (falls back to a text glyph)

### ComputerService.luau
Client-only. Owns the hackable computers: registers each tagged model with `InteractionService`, draws the animated idle SurfaceGui on its screen part, and on activation tweens the camera onto the screen, disables player controls, and hands the model to `MinigameService`. Completing the minigame marks the model hacked locally and tells the server; the server's snapshot remote is authoritative.
- API: `ComputerService.Changed` — `RBXScriptSignal` fired whenever the hacked set changes
- API: `ComputerService:IsHacked(model: Model) -> boolean` — whether that computer is already done
- API: `ComputerService:GetFocused() -> Model?` — the computer currently under the interaction cursor
- API: `ComputerService:IsSessionOpen() -> boolean` — whether a minigame session is running
- API: `ComputerService:Activate(model: Model?) -> boolean` — opens a session on the given (or focused) computer
- Remotes: `Computer/Complete` (fired), `Computer/Sync` (listened, replaces the whole hacked set)
- Tags: listens `HackComputer`
- Requires: `Configs.ComputerConfig`, `InteractionService`, `GuiBuilderService`, `CharacterService`; lazily and optionally requires `MinigameService` (retried once a second, and a session cannot open without it)

### CreepRenderService.luau
Gated on `FLAGS.Enemies`. Renders the Creep enemy: turns every part of the model to face the camera each frame, and places a black neon backdrop across the hallway a set distance behind it so the creep reads as a silhouette. When the creep is untagged it launches a `CreepDistortion` effect that sweeps down the hallway away from where it stood.
- API: no public methods — runs entirely from its render-step connection.
- Tags: listens `Creep`
- Requires: `Services.AimService`, `Services.HallwaysService`, `Configs.CreepConfig`, `Configs.FLAGS`, `TagService`; clones `ReplicatedStorage.Effects.CreepDistortion`

### CrouchService.luau
Client-only. Owns crouching: binds the crouch keys (and a touch button on mobile) through an `InputContext`, tells the server, applies the sprint speed factor, blends the camera and hip-height drop over time, and plays the configured crouch idle/walk animations.
- API: `CrouchService:IsCrouching() -> boolean` — current crouch state
- API: `CrouchService:GetWeight() -> number` — 0-1 blend weight of the crouch pose
- API: `CrouchService:Stand()` — force the player out of crouch
- Remotes: `Crouch/Update` (fired on every state change)
- Requires: `Configs.CrouchConfig`, `SprintService`, `GuiBuilderService`, `MathService`

### DangerDebugService.luau
Client-only developer tool, gated on `FLAGS.DangerDebug`. Waits for the `MazeFloor` tags to settle, rebuilds the danger-field settings from them, and opens an F4 debug panel with a live readout at the player's position plus sliders for every field parameter. Sliders redraw a local heatmap of coloured markers; one button pushes the same numbers to the server.
- API: no public methods — the panel is built at require time.
- Remotes: `Danger/SetConfig` (fired by the "apply to server" button)
- Tags: reads `MazeFloor`, `Start`
- Requires: `Classes.DebugPanel`, `Services.DangerFieldService`, `Configs.FLAGS`

### DangerFieldService.luau
Procedural "danger" heat field over the maze: fractal Brownian noise per floor, gated by distance from the spawn so the area around start is always safe. Also bakes a grid of candidate spawn points with their danger values.
- API: `DangerField.GetFloorIndex(position: Vector3, settings: FieldSettings) -> number` — floor number from Y
- API: `DangerField.SampleField(position: Vector3, settings: FieldSettings) -> number` — raw fBm noise 0-1 with contrast
- API: `DangerField.SampleGate(position: Vector3, settings: FieldSettings) -> number` — smoothstep ramp out of the safe radius
- API: `DangerField.Sample(position: Vector3, settings: FieldSettings) -> number` — gate * field, the usable danger value
- API: `DangerField.MeasureExtent(floors: { BasePart }) -> (number, Vector3)` — largest horizontal span and center
- API: `DangerField.BakePoints(floors: { BasePart }, spacing: number, settings: FieldSettings) -> { SpawnPoint }` — grid of `{ Position, Danger }` on floor tops
- API: `DangerField.BuildSettings(startPosition: Vector3, extent: number, overrides: { [string]: any }?) -> FieldSettings` — config values scaled to the map extent
- Requires: `Configs.DangerConfig`

### DeathScreenService.luau
Client-only. Builds and drives the glitch death screen: scanlines, a moving sweep, RGB-split name text, glitch slice bursts, a vignette, and a typed-out hint, all faded by blur and colour-correction effects. The server sends the cause and a token; once the screen has been held long enough and faded out, the token is sent back.
- API: `DeathScreenService:Show(causeId: string?, token: number)` — show the screen for a cause from `DeathConfig.Causes` (falls back to `DeathConfig.Unknown`)
- API: `DeathScreenService:IsVisible() -> boolean` — whether the screen is up
- API: `DeathScreenService:GetTimeUntilEnd() -> number?` — seconds until the fade-out finishes, or nil if no hide is scheduled
- API: `DeathScreenService:Hide()` — schedules the fade-out after the minimum hold time
- Remotes: `Death/Show` (listened), `Death/Complete` (fired with the token once faded out)
- Requires: `Configs.DeathConfig`, `GuiBuilderService`, `MathService`

### DeathSoundService.luau
Client-only. For every player, silences Roblox's built-in `Died` sound on the root part and plays the custom `PlayerDied` sound positionally there instead when the humanoid dies.
- API: no public methods — runs entirely from its player connections.
- Requires: `AudioService`, `CharacterService`; plays `ReplicatedStorage.Sounds.PlayerDied`

### DoorService.luau
Client-only. Owns every swinging door part inside a `Doorway`+`RoomDoor` model: on a polling interval it opens each door toward whichever of the local player or nearest tagged enemy is in range, and holds it forced shut when the player is inside a room with an enemy close by. Also applies the server's "map opening" boxes, which push every door inside a region open — or into a rattling chaos mode.
- API: no public methods — runs entirely from its own connections.
- Remotes: `Oddities/MapDoors` (listened; `Start` / `Stop` with a region box, speed and mode)
- Tags: listens `DoorPart`; reads `Enemy`, `Doorway`, `RoomDoor`
- Requires: `Classes.DoorPart`, `Configs.DoorConfig`, `CharacterService`, `TagService`

### DrawerItemService.luau
Client-only. Registers every `DrawerItem` model as an interactable pick-up and fires the server when one is activated, with a short cooldown. Newly appearing items also re-sync their parent drawer so the item sits at the drawer's current position.
- API: `DrawerItemService:GetFocused() -> Model?` — the item currently under the interaction cursor
- API: `DrawerItemService:Pickup(model: Model?) -> boolean` — request pickup of the given (or focused) item
- Remotes: `DrawerItem/Pickup` (fired)
- Tags: listens `DrawerItem`
- Requires: `Configs.DrawerItemConfig`, `DrawerService`, `InteractionService`

### DrawerService.luau
Client-only. Wraps every `Drawer` model in a `Drawer` class instance, registers it as an interactable with an open/close prompt, and animates it toward the server's open attribute each frame. Toggling predicts the new state locally for up to a second so the drawer moves immediately, then falls back to the replicated attribute.
- API: `DrawerService:GetFocused() -> Model?` — the drawer currently under the interaction cursor
- API: `DrawerService:IsOpen(model: Model?) -> boolean` — open state of the given (or focused) drawer
- API: `DrawerService:Sync(model: Model)` — reapplies the drawer's current position (used when contents appear)
- API: `DrawerService:Toggle(model: Model?) -> boolean` — predicts and requests the opposite state
- Remotes: `Drawer/Toggle` (fired)
- Tags: listens `Drawer`
- Requires: `Classes.Drawer`, `Configs.DrawerConfig`, `InteractionService`

### EffectsHUDService.luau
Client HUD that stacks timed effect tiles down the right edge of the screen, each with a dimmed icon, a bright fill that drains as the timer runs out, and a tenths-of-a-second countdown. Tiles are raised by speed-boost attributes on the player, the Vanished tag on the character (SpellBook), a freshly dug hole in workspace (Shovel), a drop in an inventory item count, and a `uses` decrease on a held Pathfinder tool.
- API: data table — empty; the whole HUD is built and wired at require time.
- Remotes: `Inventory/Update` (listened)
- Tags: listens `Ignore` (Vanished tag, added/removed on the local character)
- Requires: `Configs.EffectsHUDConfig`, `Configs.ToolConfigs`, `Services.VanishedService`, `GuiBuilderService`

### ElevatorDoorService.luau
Client-side sliding doors for tagged elevator models: polls every player's distance on a config interval and tweens `Part1`/`Part2` apart when someone is close, with separate open and close distances for hysteresis. Only elevators whose type attribute marks them as the lobby elevator ever open; all others are forced shut.
- API: data table — empty; registration and the poll loop run on require.
- Tags: listens `Elevator`
- Requires: `Configs.ElevatorConfig`, `AudioService`, `CharacterService`, `MathService`

### ElevatorLoadingUIService.luau
Drives the pre-built `ElevatorLoadingGui` fade-in/fade-out loading screen used while a hallway loads, panning the hero image to random points and sweeping a shimmer gradient across the loading text. Fires the fade-complete remote back with the server's token once the overlay has fully faded in; validates the GUI's shape and bails out with a warning if anything is missing.
- API: data table — empty; the overlay is wired to the remote on require.
- Remotes: `Elevator/Loading` (listened), `Elevator/FadeComplete` (fired)
- Requires: `Configs.ElevatorConfig`, `TweenProxyService`, `GuiBuilderService`; reaches remotes by direct `ReplicatedStorage.Communication` indexing with `WaitForChild`

### EnemyDamageService.luau
Client-authoritative death check: watches every `Enemy` tagged model's parts for touches against the local character and, if the player is not inside a tagged safe `Room`, not vanished, and the enemy is neither harmless nor an inactive Mimic, plays a random attack animation, tells the server, and zeroes the humanoid's health. Also kills on a server-sent `Strike` and replays the attack animation when another player is killed.
- API: data table — empty; the touch watchers are installed on require.
- Remotes: `Death/Kill` (fired and listened), `Death/Strike` (listened)
- Tags: listens `Enemy`; reads `Room`
- Requires: `Services.VanishedService`, `Configs.AnimationConfig`, `CharacterService`

### EnemyObservationService.luau
Reports to the server, roughly 20 times a second, which `Observable` models the local camera can currently see, along with the camera position and look vector. Skips sends when nothing changed and the camera has not moved, and rate-limits forced reports to the configured minimum gap.
- API: `EnemyObservationService:SetSeen(model: Model, seen: boolean?)` — force a model to count as seen/unseen, or `nil` to go back to real sightline checks
- API: `EnemyObservationService:Report()` — force an immediate send, deferring if the minimum gap has not elapsed
- Remotes: `Enemies/UpdateView` (fired)
- Tags: listens `Observable`
- Requires: `Services.SightlineService`, `Configs.ObservedFreezeConfig`, `Configs.FLAGS` (whole module is inert when `FLAGS.Enemies` is off)

### EyeHitEffectService.luau
Full-screen feedback for the Eye enemy: on a hit remote it plays an eyelid blink, a blur pulse, a colour flash, an FOV punch, and a damage sound. Also exposes the continuous "being stared at" effect — vignette edges, a breathing pulse, and camera roll/sway — driven each frame by EyeRenderService.
- API: `EyeHitEffectService:UpdateGaze(strength: number, deltaTime: number)` — advance the gaze vignette and camera sway toward `strength` (0-1)
- Remotes: `Enemies/EyeHit` (listened)
- Requires: `Configs.EyeConfig`, `Configs.FLAGS`, `CameraFovService`, `AudioService`, `GuiBuilderService`, `MathService`

### EyeRenderService.luau
Renders every `Eye` tagged model client-side each frame: bobs it on its own phase, eases its rotation to face the camera (or droop downward while the `Stunned` attribute is set), and pivots the model. Computes how centred and close the nearest visible eye is and hands that gaze strength to EyeHitEffectService.
- API: data table — empty; the render-step job is bound on require.
- Tags: listens `Eye` (via `TagService:Listen`, scoped to workspace)
- Requires: `Services.AimService`, `Services.BobService`, `Services.SightlineService`, `Services.VanishedService`, `Configs.EyeConfig`, `Configs.FLAGS`, `EyeHitEffectService`, `TagService`

### FirstPersonCameraService.luau
Hides the default mouse icon, enables the custom `Cursor` GUI, and adds walking camera bob — a sine sway plus roll whose speed and amplitude scale with horizontal walk speed, fading in and out as the player starts and stops. Bob is suppressed entirely while the chaser camera is active.
- API: data table — empty; the render-step job is bound on require.
- Requires: `Configs.CameraBobConfig`, `ChaserCameraService`, `MathService`

### FriendAvatarService.luau
Client-only cache that loads the local player's friend list and builds R15 character models from their HumanoidDescriptions, keyed by an arbitrary string so the same key always yields the same friend. Clones a pre-assembled prototype per user id and strips accessories that failed to weld.
- API: `FriendAvatar.GetUserIds() -> { number }` — yields until the friend list has loaded
- API: `FriendAvatar.PickUserId(key: string) -> number` — stable random friend per key, falls back to the local player
- API: `FriendAvatar.GetDescription(userId: number) -> HumanoidDescription?` — cached, pcall-guarded
- API: `FriendAvatar.Build(key: string) -> Model?` — clone of the cached avatar prototype for that key

### FriendReviveUIService.luau
Shows a stack of revive-offer cards cloned from the `ReviveFriendUI` template, each with the downed player's headshot, name, and a countdown bar, plus Revive and Cancel buttons. Cards open and close on server remotes, expire on their own when the bar empties, and drop the oldest card when the configured maximum is exceeded.
- API: `FriendReviveUIService:Open(target: Player, window: number)` — show (or extend) a card for `target` lasting `window` seconds
- API: `FriendReviveUIService:Close(target: Player)` — fade and destroy that player's card
- Remotes: `Revive/Offer` (listened), `Revive/Withdraw` (listened), `Revive/Request` (fired)
- Requires: `Configs.PerkConfig` (`FriendRevive`), `GuiBuilderService`; expects a pre-built `ReviveFriendUI` ScreenGui with a `Card` template

### GhostMotionService.luau
Shared math and attribute protocol for ghost drift: builds a travel "leg" (origin, target, duration) that the server publishes onto the model as attributes and clients read back, plus bobbing and fade timing.
- API: `GhostMotion.NewLeg(origin: CFrame, goal: Vector3, speed: number, startedAt: number) -> Leg` — leg facing the direction of travel
- API: `GhostMotion.NewHold(cframe: CFrame, startedAt: number) -> Leg` — zero-duration stationary leg
- API: `GhostMotion.Evaluate(leg: Leg, now: number) -> CFrame` — position lerp plus separate turn lerp
- API: `GhostMotion.Bob(clock: number, phase: number) -> Vector3` — GhostConfig-sized bob offset
- API: `GhostMotion.Publish(model: Model, leg: Leg)` — writes `DriftOrigin`/`DriftTarget`/`DriftDuration`/`DriftStartedAt`
- API: `GhostMotion.Read(model: Model) -> Leg?` — reads those attributes back
- API: `GhostMotion.PublishFade(model: Model, startedAt: number)` / `GhostMotion.ReadFade(model: Model) -> number?` — `FadeStartedAt`
- API: `GhostMotion.PublishAppear(model: Model, startedAt: number)` / `GhostMotion.ReadAppear(model: Model) -> number?` — `AppearStartedAt`
- API: `GhostMotion.FadeAlpha(startedAt: number, now: number) -> number` — sine in-out 0-1 over `GhostConfig.FadeTime`
- Requires: `Services.BobService`, `Configs.GhostConfig`

### GhostRenderService.luau
Client-only rendering of `Ghost` tagged models: builds a semi-transparent stand-in rig from a random friend's (or the local player's) avatar description, plays the ghost idle animation, and hides the server model behind it. Each frame it drives the rig along the server's replicated leg motion with a bob, aims the ghost's head at the player's head, and blends transparency for the fade-out/appear attributes.
- API: data table — empty; the tag listener and render-step job run on require.
- Tags: listens `Ghost` (via `TagService:Listen`, scoped to workspace); removes `Ghost` from the cloned fallback visual
- Requires: `Services.BobService`, `Services.GhostMotionService`, `Configs.AnimationConfig`, `Configs.FLAGS`, `TagService`

### GraphicsFogService.luau
Applies heavy distance fog on low graphics settings to cut render load: reads the saved quality level, or estimates one from a rolling FPS average when quality is Automatic, then blends `Lighting.FogEnd` toward the per-level distance. While fog is active it parks any Atmosphere out of Lighting and keeps a six-slab black cage parented to the camera so the skybox cannot be seen through the fog.
- API: `GraphicsFogService:GetEffectiveLevel(): number` — the saved quality level, or the current FPS-based estimate
- API: `GraphicsFogService:IsFogActive(): boolean` — whether the fog and cage are currently applied
- Requires: `Configs.GraphicsFogConfig`, `MathService`

### GuiBuilderService.luau
Small shared helper for building GUI instances; every other UI service uses it to reach the PlayerGui and to create ScreenGuis and common UI modifiers. All four functions are dot-defined and return the instance they created.
- API: `GuiBuilderService.GetPlayerGui(): PlayerGui` — `WaitForChild("PlayerGui")` on the local player
- API: `GuiBuilderService.CreateScreenGui(name: string, displayOrder: number?, ignoreGuiInset: boolean?): ScreenGui` — parented to PlayerGui with `ResetOnSpawn = false` and sibling ZIndex behaviour; the two optional arguments are only applied when truthy
- API: `GuiBuilderService.Corner(parent: GuiObject, radius: UDim): UICorner` — adds a UICorner of that radius
- API: `GuiBuilderService.Stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke` — adds a border-mode UIStroke

### HallwayGraphService.luau
Builds a navigable node graph from the tagged maze floor parts by intersecting hallway rectangles (perpendicular crossings and end-to-end parallel joins), then offers nearest-node lookup, Dijkstra pathfinding, and walking-distance queries. The graph is cached and invalidated automatically whenever a tagged floor is added or removed.
- API: `HallwayGraph:Build() -> { RouteNode }` — forces a fresh build, bypassing the cache
- API: `HallwayGraph:Get() -> { RouteNode }` — cached node list
- API: `HallwayGraph:Invalidate()` — drops the cache
- API: `HallwayGraph:FindNearestNode(position: Vector3) -> RouteNode?` — linear scan
- API: `HallwayGraph:CountExits(node: RouteNode) -> number` — neighbor count
- API: `HallwayGraph:FindPath(from: RouteNode, to: RouteNode, edgeCost: ((RouteNode, RouteNode) -> number)?) -> { RouteNode }?` — Dijkstra with optional custom cost
- API: `HallwayGraph:GetWalkingDistance(firstPosition: Vector3, secondPosition: Vector3) -> number` — off-graph positions snapped to the nearest hallway span
- API: `HallwayGraph:IsFarFromPlayers(position: Vector3, distance: number) -> boolean` — true if no alive player root is within `distance`
- Tags: listens `MazeFloor`, `HallwayRoomFloor` (added/removed only, to invalidate the cache); `HallwayRoomFloor` nodes are marked not usable as destinations
- Requires: `Services.CharacterService`

### HallwayStreamingService.luau
Client half of the hallway streaming handshake: when the server announces a pending teleport it waits (up to a timeout) for the named streaming models to arrive in workspace and then reports ready or not-ready. A background loop reconciles the server's expected model-id list against what actually arrived and reports anything missing; failures are shown in a small on-screen message banner.
- API: data table — empty; the handshake and reconcile loop run on require.
- Remotes: `Streaming/PrepareTeleport` (listened), `Streaming/ClientReady` (fired), `Streaming/TeleportFailed` (listened), `Streaming/ExpectedModels` (listened), `Streaming/ReportMissing` (fired)
- Tags: reads `StreamingModel` (from `StreamingConfig.ModelTag`)
- Requires: `Configs.StreamingConfig`, `GuiBuilderService`

### HallwaysService.luau
Geometric view of the same tagged floor parts as oriented rectangles: which hallway contains a point, the closest point on one, and the longest unobstructed straight span through a position by merging collinear hallway intervals. Cached per `includeRoomFloors` and auto-invalidated on tag changes.
- API: `Hallways.All(includeRoomFloors: boolean?) -> { Hallway }` — cached hallway rectangles
- API: `Hallways.Invalidate()` — clears both cache variants
- API: `Hallways.At(position: Vector3, includeRoomFloors: boolean?) -> Hallway?` — containing hallway, with a height window
- API: `Hallways.ClosestPoint(hallway: Hallway, position: Vector3) -> Vector3` — clamped point on the floor surface
- API: `Hallways.Nearest(position: Vector3) -> Hallway?` — nearest by closest-point distance
- API: `Hallways.Along(hallway: Hallway, position: Vector3) -> number` — signed distance along the axis
- API: `Hallways.PointAt(hallway: Hallway, along: number) -> Vector3` — point on the axis at floor height
- API: `Hallways.StraightSpanAt(position: Vector3, preferredDirection: Vector3?) -> StraightSpan?` — best straight run through a point
- API: `Hallways.StraightSpans() -> { StraightSpan }` — one span per hallway, deduplicated
- Tags: listens `MazeFloor`, `HallwayRoomFloor` (added/removed only, to invalidate the cache)

### HearingRenderService.luau
Renders the "sound travelling to an enemy's ear" visual: for each server-sent event it spawns a neon ball with a particle wake, lerps it from the noise origin to the target model's ear position over the given duration, then plays an expanding fade-out flash and cleans up. The render loop connects only while motes are alive.
- API: data table — empty; the remote listener is connected on require.
- Remotes: `Hearing/Travel` (listened)
- Requires: `Configs.HearingConfig`

### HeartbeatService.luau
Plays a looping heartbeat that swells as the configured enemy gets closer and speeds up while it is pursuing, pitch-corrected through an AudioPitchShifter so the faster playback does not raise the pitch. The track is created on demand and stopped again once the volume fades to silence.
- API: `HeartbeatService:GetNearness(): number` — the current smoothed heartbeat volume (0 when silent)
- Tags: reads `Enemy` (filtered by the `EnemyId` attribute)
- Requires: `Configs.HeartbeatConfig`, `Configs.FLAGS`, `AudioService` (`FindTemplate`, `Play2D`, `Wire`, `GetBus`), `TagService`, `CharacterService`, `MathService`

### IndexUIService.luau
Builds and drives the bestiary/index UI: a paginated grid of cards with ViewportFrame headshots (real models, stand-in primitives, or a friend-avatar rig), hover/press/select card motion, and an info panel whose description is progressively unredacted as discovery progress rises. Also plays the word-by-word reveal animation after a death, waiting for the death screen to clear before opening the page itself.
- API: `IndexUIService:Refresh()` — rebuild the listed entries, repaint every card, and repaint the info panel
- API: `IndexUIService:GetProgress(id: string): number` — discovery progress (0-1) for an entry
- API: `IndexUIService:IsDiscovered(id: string): boolean` — whether progress is past the named threshold
- API: `IndexUIService:SetProgress(id: string, progress: number)` — set one entry's progress and refresh
- API: `IndexUIService:SetProgressSet(set: { [string]: number })` — replace the whole progress table and refresh
- API: `IndexUIService:GetProgressSet(): { [string]: number }` — a clone of the progress table
- API: `IndexUIService:Select(id: string?)` — select a card and animate the info panel across
- API: `IndexUIService:GetSelected(): string?` — the selected entry id
- API: `IndexUIService:SetPage(page: number)` — clamp to a valid page, re-lay out, and deal the cards in
- API: `IndexUIService:GetPage(): number` — the current page number
- API: `IndexUIService:NextPage()` — page forward
- API: `IndexUIService:PreviousPage()` — page back
- API: `IndexUIService:PlayReveal(id: string, before: number, after: number)` — animate the words newly unlocked between two progress values
- Remotes: `Index/Update` (listened and fired), `Index/Reveal` (listened) — both looked up with `CommunicationService.Find` and skipped if absent
- Requires: `Configs.IndexConfig`, `Services.RedactionService`, `Services.FriendAvatarService`, `DeathScreenService`, `InterfaceService`, `TweenProxyService`, `GuiBuilderService`; expects a pre-built `IndexGui.Design` tree

### InteractionService.luau
Client-only singleton wrapper: returns a single `Interaction` instance (an empty table on the server), which raycasts from the camera each frame to find the registered model under the crosshair, highlights it, and draws the key prompt.
- API: `InteractionService:Register(model: Model, options: Interaction.TargetOptions)` — register a target with its prompt text/function, reach, `CanSelect`, `IgnoreOcclusion`, and `OnActivated` callback
- API: `InteractionService:Unregister(model: Model)` — drop a target and clear the selection if it was selected
- API: `InteractionService:GetSelected(): Model?` — the model currently under the crosshair
- API: `InteractionService.Selected` — BindableEvent signal fired with the newly selected model, or `nil`
- API: `InteractionService:Destroy()` — unbind the render step, action, and connections and destroy the highlight and prompt
- Requires: `Classes.Interaction` (which reads `Configs.DrawerConfig` and clones its prompt from the `Cursor` ScreenGui)

### InterfaceService.luau
Owns the main menu page group: enables/disables the Index, Shop, VIP, Gems, and Items ScreenGuis through an xenterface controller, blurs and pulls back the camera FOV while a page is open, and manages mouse unlocking (including a Q toggle when no page is open). Also wires hover/press motion onto tagged side buttons and close buttons using named motion presets.
- API: `InterfaceService.WireMotion(button: GuiButton, visual: GuiObject?, motionPreset: any?)` — add hover/press scale and tilt motion to any button (defaults to the button itself and the `HotelSideButton` preset)
- API: `InterfaceService:Open(pageId: string)` — open one of the known pages, warning on an unknown id
- API: `InterfaceService:Close()` — close whatever page is open
- API: `InterfaceService:GetActive(): string` — the active page id (empty string when closed)
- API: `InterfaceService:SetMouseUnlocked(unlocked: boolean, force: boolean?)` — unlock/relock the mouse; `force` pins it unlocked until cleared
- Tags: listens `SideButton`, `InterfaceCloseButton`
- Requires: `Frameworks.xenterface` and its `Config.PresetConfig`, `CameraFovService`, `GuiBuilderService`, `Lighting.InterfaceBlur`

### InventoryUIService.luau
Replaces the Roblox backpack with a built-from-code hotbar plus a toggleable backpack grid of `InventorySlot` objects. Handles click-to-equip, number-key equipping, and drag-and-drop reordering (with a ghost clone and drop-target highlighting), applying the swap locally before telling the server.
- API: `InventoryUIService:Refresh()` — repaint every slot from the latest server snapshot and the equipped tool
- Remotes: `Inventory/Update` (listened and fired), `Inventory/Move` (fired)
- Requires: `Classes.InventorySlot`, `Configs.InventoryConfig`, `InterfaceService` (mouse unlocking), `CharacterService`, `GuiBuilderService`; disables the core Backpack GUI

### ItemsUIService.luau
Drives the `ItemsGui` item shop: builds a card per shop entry with a live ViewportFrame preview of the tool model, animates hover/press/select and a staggered deal-in when the page opens, and fills the info panel with name, description, coin price, and the live Robux price fetched from MarketplaceService. Coin purchases go through a remote; Robux purchases prompt a developer product, and voice-only entries are hidden from players without voice chat.
- API: data table — empty; the shop is built and wired on require.
- Remotes: `Items/Purchase` (fired), `Items/Sync` (listened and fired)
- Requires: `Configs.ItemShopConfig`, `MarketplaceService` (project wrapper, for `Products.Items` and product info), `TweenProxyService`, `GuiBuilderService`, `ReplicatedStorage.Tools`

### LanternSwayService.luau
Makes named hanging lantern models physically swing while their light is in the chaos-red state. Each active lantern gets an invisible hinged proxy part with wind torque, random jolts, gravity scaling, and a swing limit computed from raycast wall clearance; the visible model is pivoted to the hinge angle each frame. Lanterns are culled by camera distance and a maximum simulated count, and are settled and torn down when the red state ends.
- API: data table — empty; the tag listeners and heartbeat loop run on require.
- Tags: listens `Floor1Light` (filtered to the model names in the config, and gated by the `ChaosRed` attribute)
- Requires: `Configs.LanternSwayConfig`, `ChaosLightService`

### LobbyService.luau
Answers whether a player is standing on the lobby floor, by requiring the humanoid to be grounded and then raycasting down from the root part against only the `LobbyFloor` tagged parts.
- API: `LobbyService:IsPlayerOnLobbyFloor(player: Player?): boolean` — defaults to the local player
- Tags: reads `LobbyFloor`
- Requires: `CharacterService`

### LookService.luau
Two halves of head/torso look-at: it reports the local camera's pitch and yaw relative to the character's facing to the server on an interval (only when they move past a threshold), and it bends the Neck and Waist joints of every other player's character and every `Enemy` model toward their replicated `LookPitch`/`LookYaw` attributes. The applied transform is undone in PreAnimation so animations still play cleanly, and joints are cached weakly per model.
- API: data table — empty; the report and joint-bend loops run on require.
- Remotes: `Look/Update` (fired)
- Tags: reads `Enemy`
- Requires: `Configs.LookConfig`, `MathService`

### MarketplaceService\init.luau
Wrapper around Roblox's own MarketplaceService that adds a shared server/client gamepass-ownership cache, cross-boundary purchase prompts, and a registry of per-product receipt handlers. Server also grants the VIP pass to holders of a legacy VIP subscription. `extend` merges the real MarketplaceService in, so every native member is still reachable through this module.
- API: `MarketplaceService:PromptProductPurchase(player: Player, productId: number)` — server relays to the owning client, client prompts
- API: `MarketplaceService:PromptGamePassPurchase(player: Player, gamePassId: number)` — same server/client split
- API: `MarketplaceService:UserOwnsGamePass(player: Player | number, gamePassId: number) -> boolean` — cached; client round-trips to the server and yields up to 10s
- API: `MarketplaceService:GetProductInfo(id: number, infoType: Enum.InfoType?) -> ProductInfo` — with `infoType` calls the async API, otherwise reads the client-preloaded cache
- API: `MarketplaceService:CreateReceipt(productId: number, f: (ReceiptInfo) -> Enum.ProductPurchaseDecision)` — server only; `"ALL"` registers a fire-and-forget observer
- API: `MarketplaceService:DeleteReceipt(productId: number)` — server only
- API: `MarketplaceService.Gamepasses` / `.Products` — the two id tables below
- Remotes: three RemoteEvents created as children of the module script itself (not in `Communication`): `PromptProductPurchase`, `PromptGamePassPurchase` (fired to client, listened on client), `GamePassSync` (both directions, actions `RequestSync` / `CheckGamePass` / `FullSync` / `UpdatePass`)
- Requires: `Modules.extend` (metatable merge, also blocks reassigning `ProcessReceipt`); owns `_MarketplaceService.ProcessReceipt`

### MarketplaceService\Gamepasses.luau
Gamepass asset ids keyed by name.
- API: data table — `Pathfinder`, `KeepItems`, `Visor`, `DoubleSpeed` (all currently `0`, i.e. unpublished)

### MarketplaceService\Products.luau
Developer-product asset ids, with per-item product ids nested under `Items`.
- API: data table — `Revive`, `ReviveFriend`, and `Items` (Ball, Bandage, EnergyDrink, Flashlight, Medkit, Pathfinder, Shovel, Soda, SpellBook, Trap, Visor); only `Revive` has a real id

### MathService.luau
Small pure-math helper library shared across the codebase: easing, framerate-independent lerp alphas, horizontal-plane vector work, angles, and pulses. No state, no connections.
- API: `MathService.TAU` — `math.pi * 2`
- API: `MathService.Smoothstep(alpha: number) -> number` — clamped 3t²-2t³ ease
- API: `MathService.ExpAlpha(speed: number, deltaTime: number) -> number` — `1 - exp(-speed*dt)`, the standard lerp alpha used by every render loop here
- API: `MathService.Horizontal(vector: Vector3) -> Vector3` — zeroes Y
- API: `MathService.HorizontalMagnitude(vector: Vector3) -> number` — XZ length
- API: `MathService.DistanceToSegment(point: Vector3, origin: Vector3, destination: Vector3, minimumLengthSquared: number?) -> number` — degenerate segments fall back to distance from `origin`
- API: `MathService.AngleBetween(a: Vector3, b: Vector3) -> number` — degrees, 0 for near-zero vectors
- API: `MathService.IsWithinCone(origin: Vector3, direction: Vector3, point: Vector3, maximumAngle: number) -> boolean` — degrees
- API: `MathService.RandomRange(minimum: number, maximum: number) -> number` — continuous
- API: `MathService.SinePulse(time: number, period: number) -> number` — 0..1 sine

### MimicMotionService.luau
Turns a recorded movement sample into discrete WASD-style key values so a mimic can replay a player's inputs, with mirroring, reaction-delay latching, and idle aim drift.
- API: `MimicMotion.Keys(sample: MotionTrail.Sample, walkSpeed: number) -> (number, number)` — forward/right key from move vs look
- API: `MimicMotion.MirrorKeys(forwardKey: number, rightKey: number) -> (number, number)` — flips strafe only
- API: `MimicMotion.Direction(forward: Vector3, forwardKey: number, rightKey: number) -> Vector3` — unit move direction
- API: `MimicMotion.NewKey() -> Key` — latch state `{ Held, Pending, At }`
- API: `MimicMotion.HoldKey(key: Key, desired: number, clock: number) -> number` — applies the change after a random reaction delay
- API: `MimicMotion.Drift(look: Vector3, clock: number, seed: number) -> Vector3` — two-frequency yaw wander
- API: `MimicMotion.Turn(cframe: CFrame, look: Vector3, deltaTime: number, turnRate: number?) -> CFrame` — exponential turn toward a flattened look
- Requires: `Configs.MimicConfig`, `Classes.MotionTrail`

### MimicService.luau
Client-side driver for the Mimic enemy: mirrors the local player's recorded movement onto the mimic model, runs its "spin to face you" mode, twitches and head-locks enemy necks, and plays the reveal sting. Disabled entirely when `FLAGS.Enemies` is off.
- API: none — side-effect only.
- Remotes: `Enemies/Mirror` (listened), `Enemies/MimicReveal` (listened)
- Tags: listens `Enemy` (raw CollectionService signals, to find necks to twitch/head-lock)
- Requires: `Classes.MotionTrail`, `Classes.NpcAnimator`, `Services.MimicMotionService`, `Configs.MimicConfig`, `Configs.AnimationConfig`, `AudioService` (reverb wiring)

### MinigameService.luau
Client-only arcade shell for the hackable computers: picks which minigame a given terminal runs (deterministic by position within its maze), builds the CRT-styled SurfaceGui with title bar, scanlines, win/deny overlays, and hosts one game module at a time. Owns its own pooled `AudioPlayer` sound-cue graph under SoundService.
- API: `MinigameService:Open(model: Model, screen: BasePart, callbacks: { OnExit, OnComplete })` — closes any current session first
- API: `MinigameService:Close()` — serializes unfinished progress into a weak per-model cache, clears it on a win
- API: `MinigameService:IsOpen() -> boolean`
- API: `MinigameService:GameFor(model: Model) -> string` — assigns a game id by sorting the terminals in the same `Maze*` ancestor
- API: `MinigameService:ResolvedFor(model: Model) -> string` — alias for `GameFor`
- API: `MinigameService.Theme` — the shared arcade `Theme` table handed to every game module
- API: `MinigameService.List` — ids that actually loaded, from `{ "Memory", "AimTrainer", "Frogger", "Snake", "Simon" }`
- Tags: reads `HackComputer` (to enumerate peer terminals)
- Requires: `Classes.Minigames.<Id>` modules, each exporting `Id`, `Title`, `SupportsReset`, `new(root, api)`

### ObservedFreezeService.luau
Client-side "weeping angel" renderer: while a tagged enemy is inside the camera frustum and unoccluded it is pinned in place visually (and its animation tracks are held at speed 0), then eased back to the server's real CFrame when you look away. Includes drift limits, a confirmation timeout, and a predicted-release slide so mispredictions self-correct. Disabled when `FLAGS.Enemies` is off.
- API: none — side-effect only.
- Tags: listens `ObservedFreezeConfig.Tag`
- Requires: `Services.SightlineService` (frustum/occlusion), `EnemyObservationService` (reports what the client can see), `Configs.ObservedFreezeConfig`

### PaintingDwellerShakeService.luau
Twenty-line client shim: on the painting dweller pop remote, fires a one-shot `Slam` camera shake.
- API: none — side-effect only.
- Remotes: `Oddities/PaintingDwellerPop` (listened)
- Requires: `ShakeService`

### PerfLogService.luau
Client performance watchdog behind `FLAGS.PerfLog`: prints server-sent perf messages, alerts on frame spikes and sustained FPS drops, and every second reports bursts of workspace instance churn bucketed by top-level owner (Map, Characters, Vents, …). Also logs each respawn.
- API: none — side-effect only.
- Remotes: the PerfLog remote obtained from `PerfLog.GetRemote()` (listened)
- Requires: `Services.PerfLoggerService`, `Configs.FLAGS`

### PerfLoggerService.luau
Flag-gated startup timing log. The server stamps a start time on ReplicatedStorage, and `Log` broadcasts topic/action/timestamp to every client, which prints it; timestamps are formatted as elapsed mm:ss.mmm since that stamp.
- API: `PerfLog.Now() -> number` — seconds since the server start attribute
- API: `PerfLog.Format(timestamp: number) -> string` — `MM:SS.mmm`
- API: `PerfLog.Print(topic: string, action: string, timestamp: number?)` — local print
- API: `PerfLog.Alert(topic: string, action: string, timestamp: number?)` — local warn
- API: `PerfLog.Log(topic: string, action: string)` — no-op unless `FLAGS.PerfLog`; server broadcasts, client prints
- API: `PerfLog.GetRemote() -> RemoteEvent` — creates it on the server, waits for it on the client
- Remotes: `Communication/PerfLog` (fired to all clients; created directly by this service, sitting in Communication with no topic subfolder)
- Requires: `Configs.FLAGS`

### PlayerLocatorService.luau
Client-only teleport-to-player HUD: keeps a `LocatorMarker` per eligible player (all players, or friends only, depending on the toggled mode), highlights whichever marker is nearest the crosshair each frame, and fires the teleport remote on click. Renders the shared cooldown readout. If the `PlayerLocator` GUI is missing its expected children it degrades to a disabled stub exposing only `SetEnabled`/`IsEnabled`.
- API: `PlayerLocatorService:SetEnabled(value: boolean)` — shows/hides the GUI, rebuilds markers, binds/unbinds the render step
- API: `PlayerLocatorService:IsEnabled() -> boolean`
- API: `PlayerLocatorService:GetMode() -> string` — current mode id from `PlayerLocatorConfig.Modes`
- Remotes: `PlayerLocator/Teleport` (fired to request; listened for the returned cooldown)
- Requires: `Classes.LocatorMarker`, `Configs.PlayerLocatorConfig`, `GuiBuilderService`; reads the `Cursor` GUI to find the aim point

### PlayerOddityRenderService.luau
Client renderer for the "everyone stares at you" oddity: while the server-sent stare is active, every other player's neck Motor6D is eased toward looking at your head (clamped to ±80° yaw, ±35° pitch), then eased back and released once settled.
- API: none — side-effect only.
- Remotes: `Oddities/HeadStare` (listened; payload is a duration in seconds, `<= 0` cancels)
- Requires: `Configs.PlayerOddityConfig`, `CharacterService.GetAliveHumanoid`

### RecordPlayerAudioService.luau
Client audio ducker for tagged in-world record players: while the elevator is loading or the death screen is up, it splices an `AudioEqualizer` into each emitter's wire chain to muffle it and fade its volume out, then removes the splice and restores the original volume once both conditions clear.
- API: `RecordPlayerAudioService:SetLoading(value: boolean, token: number)` — token-guarded so a stale `false` cannot cancel a newer load
- Remotes: `Elevator/Loading` (listened)
- Tags: listens `RecordPlayer`
- Requires: `DeathScreenService` (`IsVisible`, `GetTimeUntilEnd`)

### RedactionService.luau
Progressively reveals a string word by word in a stable pseudo-random order derived from a seed, replacing hidden words with block glyphs. Longer words cost more of the reveal budget; word lists, weights, and orders are all memoized.
- API: `Redaction.Words(text: string) -> { string }` — cached whitespace split
- API: `Redaction.WordCount(text: string) -> number`
- API: `Redaction.Weights(text: string) -> ({ number }, number)` — per-word cost and total
- API: `Redaction.Order(text: string, seed: string) -> { number }` — deterministic shuffle from an FNV-1a hash of seed+text
- API: `Redaction.VisibleSet(text: string, seed: string, progress: number) -> { [number]: boolean }` — which word indices are revealed at 0-1 progress
- API: `Redaction.Render(text: string, seed: string, progress: number, options: RenderOptions?) -> string` — plain or RichText output with per-word colors, forced suppression, and block ratio
- API: `Redaction.NewlyVisible(text: string, seed: string, before: number, after: number) -> { number }` — indices gained between two progress values

### ShakeService.luau
Client camera-shake front end over the vendored `CameraShaker`. Offers five named presets, keyed sustained shakes, and a `Rumble` handle whose magnitude can be driven continuously (e.g. by proximity).
- API: `ShakeService:Create(shakeData: { ID: string, ShakeType: "Once" | "Sustained", Preset: string })` — presets are `Scare`, `Small`, `Jumpscare`, `Slam`, `Jolt`
- API: `ShakeService:Delete(ID: string)` — fades out and forgets a sustained shake
- API: `ShakeService:CreateDynamicRumble(startValue: number, params: RumbleParams?) -> Rumble` — handle with `:AdjustValue(n)`, `:Stop(fadeOutTime?)`, `:Start()`
- API: `ShakeService.SustainedShakes` — id → live shake instance
- Requires: `Classes.CameraShaker` (vendored third-party), `Services.PerfLoggerService`

### ShopkeeperService.luau
Client service for shopkeeper NPCs: registers each tagged model with the interaction system, keeps its `PageAttribute` in sync, plays a looping smile animation once FaceControls/Animator exist, and opens the matching interface page on activation.
- API: `ShopkeeperService:GetFocused() -> Model?` — the currently selected shopkeeper
- API: `ShopkeeperService:GetPageId(model: Model?) -> string?` — defaults to the focused one
- API: `ShopkeeperService:Open(model: Model?) -> boolean` — 0.15s cooldown; false if no page id
- Tags: listens `ShopkeeperConfig.Tag` (via `TagService:Listen`, scoped to `workspace`)
- Requires: `InteractionService` (`Register`/`Unregister`/`Selected`), `InterfaceService`, `Configs.ShopkeeperConfig`

### SightlineService.luau
Camera visibility tests: builds a frustum from a Camera, does cone/sphere intersection, and raycasts to each part of a model to decide whether it is actually seen. Keeps a self-maintaining per-model BasePart cache that disconnects itself when the model is destroyed or unparented.
- API: `Sightline.Frustum(camera: Camera) -> Frustum?` — tangents and side factors; nil if the viewport has no height
- API: `Sightline.Intersects(camera: Camera, frustum: Frustum, center: Vector3, radius: number) -> boolean` — sphere vs frustum
- API: `Sightline.OnScreen(camera: Camera, frustum: Frustum, model: Model) -> boolean` — bounding-box test only, no raycast
- API: `Sightline.CanSee(camera: Camera, frustum: Frustum, ignore: Instance?, model: Model) -> boolean` — frustum test plus line-of-sight raycast per part

### SpeedBoostRenderService.luau
Client screen effect for speed boosts: watches the local player's `SpeedBoostFov` attribute and tweens both a camera FOV offset and a `ColorCorrectionEffect` (saturation, contrast, warm tint) in and out, disabling the effect once it fully returns to zero.
- API: none — side-effect only.
- Requires: `CameraFovService`, `TweenProxyService`; reads the `SpeedBoostFov` player attribute

### SprintBoostUIService.luau
Client-only decorated overlay for the stamina bar while a speed boost is active: a gradient/streak/sheen CanvasGroup fill inside the sprint bar plus a separate overlay ScreenGui with aura stroke, expanding rings, flash, pop scale, remaining-time bar and a chromatic label. All visuals are read per-boost from `SprintBoostConfig.Boosts[name]`.
- API: none — side-effect only.
- Requires: `Configs.SprintBoostConfig`, `Configs.SprintConfig`, `SprintUIService` (`GetBar`, `SetForcedVisible`), `GuiBuilderService`; reads the `SpeedBoostName` and `SpeedBoostEndsAt` player attributes

### SprintService.luau
Client sprint state machine: binds hold-to-sprint keys (plus a touch toggle button), drains and regenerates stamina with an exhaustion lockout, and owns the humanoid's `WalkSpeed`. It watches external WalkSpeed writes to re-derive the base speed and respects the server's speed-boost attributes, and drives the sprint FOV offset.
- API: `SprintService:GetStaminaFraction() -> number` — 0..1
- API: `SprintService:IsSprinting() -> boolean`
- API: `SprintService:IsExhausted() -> boolean`
- API: `SprintService:GetWeight() -> number` — eased 0..1 sprint blend, used for camera effects
- API: `SprintService:SetSpeedFactor(name: string, factor: number?)` — named multiplicative modifiers; `nil` removes
- API: `SprintService:SetSprintBlocked(name: string, blocked: boolean)` — named blockers; blocking also drops held/toggled state
- Requires: `Configs.SprintConfig`, `CameraFovService`; reads the `SpeedBoostSpeed` / `SpeedBoostBaseSpeed` player attributes

### SprintUIService.luau
Client-only stamina bar: builds the CanvasGroup/track/fill GUI, follows the stamina fraction with an eased lerp, recolours through fill → low → empty bands, pulses the track while exhausted, and auto-fades the bar out once stamina has been full for a while.
- API: `SprintUIService:SetForcedVisible(value: boolean)` — keeps the bar shown regardless of the auto-fade (used by the boost overlay)
- API: `SprintUIService:GetBar() -> { Group: CanvasGroup, Track: Frame, Fill: Frame, Stroke: UIStroke }` — the instances other UI decorates
- Requires: `SprintService` (reads stamina/exhaustion), `Configs.SprintConfig`, `GuiBuilderService`

### StalkerCameraService.luau
Client camera lock for the Stalker: on the remote, smoothly turns the camera to face the stalker's UpperTorso over a given time. For kills it also anchors the local root part and tweens a +30 FOV offset, restoring both on release. Disabled when `FLAGS.Enemies` is off.
- API: none — side-effect only.
- Remotes: `Enemies/FaceStalker` (listened; `(model, turnTime, kill)`, a nil model releases)
- Requires: `CameraFovService`, `CharacterService.GetAliveHumanoid`

### StatsHUDService.luau
Client debug HUD in the bottom-left: FPS, ping, sampled danger-field value at your position, and a live list of enemies (id, state, distance) colour-coded by threat, plus the stalker's current target. Waits for maze floor tags to settle before building the danger field.
- API: none — side-effect only.
- Remotes: `Enemies/DebugSnapshot` (listened)
- Tags: reads `MazeFloor`, `Start`
- Requires: `Services.DangerFieldService`, `Configs.StatsHUDConfig`, `GuiBuilderService`

### TagService.luau
The tag-to-module pipeline described in the architecture notes: one registered listener per tag receives an `apply` on every tagged instance (existing and future) and an `unapply` when the tag is removed, the instance is destroyed, or it leaves the optional ancestor. Whatever `apply` returns is stored and handed back to `unapply`, which is how tagged instances get bound to class instances.
- API: `TagService:Listen(tag: string, apply: (Instance) -> any, unapply: (Instance, data: any) -> nil, ancestor: Instance?)` — warns and no-ops if the tag is already listened; `ancestor` also hooks `DescendantAdded`/`DescendantRemoving`
- API: `TagService:Unlisten(tag: string)` — unapplies everything and disconnects
- API: `TagService:GetAllApplied(tag: string) -> { [Instance]: any }` — cloned snapshot of the stored data
- API: `TagService:GetApplied(tag: string, instance: Instance) -> any`
- API: `TagService:GetTaggedOfPredicate(tag: string, predicate: (Instance) -> boolean) -> { Instance }`
- API: `TagService:GetTaggedOfAncestor(ancestor: Instance, tag: string) -> { Instance }` — note the reversed argument order
- API: `TagService:GetListenedTags() -> { string }`
- API: `TagService:GetListenedTagsOfInstance(instance: Instance) -> { string }`

### ToolClientService.luau
Client bootstrap for tool classes: for every entry in `ToolConfigs` that has a matching module under `Classes.Tools`, listens on that tool's tag, constructs the class for tools belonging to the local player, and re-fires `OnEquipped` if the tool was already parented to the character. Also routes server tool events to the right instance.
- API: `ToolClientService:FromTool(tool: Instance?) -> any?` — the class instance bound to a Tool
- Remotes: `Tools/Signal` (listened; dispatched to the first instance whose Tool name matches)
- Tags: listens each `ToolConfigs[name].Tag`
- Requires: `Configs.ToolConfigs`, `Classes.Tools.*`, `TagService`

### TweenProxyService.luau
Generic helper for tweening things TweenService cannot touch directly: it creates a throwaway ValueBase, tweens its `Value`, and pushes each change into a callback, cleaning up on completion.
- API: `TweenProxyService.Proxy(className: string, initialValue: any, goalValue: any, tweenInfo: TweenInfo, apply: (value: any) -> ()) -> Tween` — returns the tween unplayed; snaps to `goalValue` only if it completes normally
- API: `TweenProxyService.ScaleModel(model: Model, from: number, to: number, tweenInfo: TweenInfo) -> Tween` — `Model:ScaleTo` over time, skipped once the model is unparented
- API: `TweenProxyService.CancelAll(tweens: { Tween })` — cancels and clears the list in place

### VanishedService.luau
One-question helper for whether a character should be treated as absent: it carries the `Ignore` tag or has a ForceField anywhere inside it.
- API: `Vanished.Is(character: Instance?) -> boolean` — tagged `Ignore` or contains a ForceField
- API: `Vanished.Tag` — the string `"Ignore"`
- Tags: reads `Ignore`
### ViewmodelService.luau
Client first-person viewmodel: clones the equipped Tool (stripped of scripts, sounds and effects) under the camera, hides the real tool, and each render step positions the clone from camera CFrame plus yaw sway and speed-scaled bob. Auto-hides when not in first person or when the character's real hand is visible; supports per-tool anchor/rotation overrides.
- API: none — side-effect only.
- Requires: `Configs.ViewmodelConfig` (`Scale`, `Fit`, `HandOffset`, `Arm`, `Overrides`)

### VoiceActivityService.luau
Client voice-activity detector: wires an `AudioAnalyzer` onto the local player's `AudioDeviceInput`, polls RMS level against a threshold, and tells the server when you start and stop speaking (with a heartbeat re-send and a release delay). Rebuilds itself if the input device appears or disappears.
- API: none — side-effect only.
- Remotes: `WalkieTalkie/VoiceActivity` (fired)
- Requires: `Configs.VoiceChatConfig` (`Activity.PollInterval`, `.Threshold`, `.Heartbeat`, `.Release`)

### VoiceDebugService.luau
Client-only debug panel behind `FLAGS.VoiceDebug` with sliders for proximity-voice and radio volumes. To make proximity voice adjustable it rewires every remote player's direct voice wire through an inserted `AudioFader`; radio sliders write straight into the named faders it finds in Players and Workspace. All changes are local and session-only.
- API: none — side-effect only.
- Requires: `Classes.DebugPanel`, `Configs.VoiceDebugConfig`, `Configs.FLAGS`

### WalkSoundService.luau
Client footstep engine for players and tagged enemies. Silences the default Roblox running sound and instead times steps from the character's looping Core-priority locomotion track (falling back to a speed-scaled interval), playing a random emitter from `Sounds.Footsteps`. Enemies get custom distance attenuation out to 45 studs and per-enemy volume; crouching players get quieter, slower, shorter-range steps.
- API: none — side-effect only.
- Tags: listens `Enemy`
- Requires: `AudioService.Play3DSound`, `CharacterService.ForEachPlayer`, `TagService`, `Configs.WalkSoundConfig`, `Configs.CrouchConfig` (`Stealth`)

### WalkieTalkieService.luau
Client walkie-talkie mode control. Reuses the `PlayerLocator` GUI's mode frame for its label and toggle button, cycles through `WalkieTalkieConfig.Modes` and reports the choice to the server, and mutes the player's own radio emitter by moving it into a private `AudioInteractionGroup`. Refuses to enable if voice chat is not available for the user.
- API: `WalkieTalkieService:SetEnabled(value: boolean, tool: Tool?)` — enabling checks voice eligibility and starts watching `tool` for its `RadioEmitter`
- API: `WalkieTalkieService:IsEnabled() -> boolean`
- Remotes: `WalkieTalkie/SetMode` (fired)
- Requires: `Configs.WalkieTalkieConfig`, `GuiBuilderService`; shares the `PlayerLocator` ScreenGui with `PlayerLocatorService`
