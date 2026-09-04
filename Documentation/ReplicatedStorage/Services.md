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
Client-only. Owns additive field-of-view offsets so multiple effects can push the camera FOV without fighting each other: each caller registers a named offset, the total is applied on a render step above the camera priority, and the raw FOV is restored when nothing is registered. A lock captures the current raw FOV and holds it against later camera effects until released.
- API: `CameraFovService:SetOffset(name: string, degrees: number)` — set or clear (near-zero) a named offset
- API: `CameraFovService:GetOffset() -> number` — current summed offset
- API: `CameraFovService:SetLocked(locked: boolean)` — hold the current raw FOV and suppress all named offsets while locked
- API: `CameraFovService:TweenOffset(name: string, degrees: number, tweenInfo: TweenInfo)` — tweens one named offset, cancelling any prior tween of that name

### CaptureGalleryService.luau
Client-only front end for Roblox's Captures API, and the single place captures are taken, kept or thrown away. Wraps a capture (screenshot or video) in a `Media` record so the rest of the codebase never touches the raw `Capture` object, whose `FilePathString` and `Resolution` properties both throw on read. Captures taken this session sit in a pending list until the player keeps or burns them; kept ones go to the player's own Roblox captures gallery and come back on later sessions through `Refresh`. Nothing here is shareable — Roblox scopes an uploaded capture asset to the uploader, so a capture is only ever visible to the player who took it. Gallery permission is requested as soon as a capture is taken, and re-prompts on every later capture until the player accepts, since a denial is what silently stops captures persisting. Only a granted answer is cached. The prompt is always fired through `EnsurePermission`, never awaited inline: `PromptCaptureGalleryPermissionAsync` never returns in Studio, so blocking a capture on it would wedge the shutter permanently. Capture failures report the engine's actual reason — most usefully `NoSpaceOnDevice`, which is literal and is what a full disk looks like. `TakeScreenshotCaptureAsync` returns `NoSpaceOnDevice` in Studio, so `TakeScreenshot` silently falls back to the legacy `CaptureScreenshot` path, which produces a viewable capture that cannot be saved to the gallery.
- API: `CaptureGalleryService:TakeScreenshot() -> (Media?, string?)` — take a still with UI excluded; on failure falls back to the legacy path and returns the reason it could not be saved
- API: `CaptureGalleryService:StartVideo(onFinished: (Media?, string?) -> ()) -> boolean` — begin recording; Roblox hides all UI and mutes voice for the duration and stops itself at 30s
- API: `CaptureGalleryService:StopVideo()` / `CaptureGalleryService:IsRecording() -> boolean`
- API: `CaptureGalleryService:Save(media: Media) -> boolean` — prompt the player to keep the capture in their gallery
- API: `CaptureGalleryService:Discard(media: Media)` — drop a pending capture
- API: `CaptureGalleryService:Refresh(force: boolean?) -> boolean` — reload the gallery, keeping only captures whose `SourceUniverseId` is this universe
- API: `CaptureGalleryService:List() -> {Media}` — pending plus saved captures, newest first
- API: `CaptureGalleryService:Content(media: Media) -> Content?` — a `Content` for `ImageLabel.ImageContent` or `VideoFrame.VideoContent`
- API: `CaptureGalleryService:RequestPermission() -> boolean` — prompts and yields; returns false immediately if a prompt is already in flight
- API: `CaptureGalleryService:EnsurePermission()` — fire-and-forget prompt, safe to call from a capture sequence
- API: `CaptureGalleryService:WaitForPermission() -> boolean` — waits out an in-flight prompt, then asks
- API: `CaptureGalleryService:HasPermission() -> boolean`
- API: `CaptureGalleryService.Changed` — BindableEvent fired when the pending or saved set changes
- Requires: `Configs.CaptureConfig`

### CaptureOverlayService.luau
Draws the camcorder furniture over a displayed capture: date and time in the bottom-right, and a red `REC` dot in the top-left for video. Roblox strips UI from the recording itself, so this is applied to whatever GUI is showing the capture rather than baked in at capture time. Replaces any overlay already on the target.
- API: `CaptureOverlayService.Apply(parent: GuiObject, media: any) -> Frame` — build the overlay inside `parent` and return it
- API: `CaptureOverlayService.Blink(overlay: Frame) -> () -> ()` — blink the record dot; returns a stop function
- Requires: `Configs.CaptureConfig`

### CeilingVentDoorService.luau
Client-only, gated on `FLAGS.Enemies`. Listens for the server's ceiling-vent door commands and tweens the named door part's pivot to the target CFrame, cancelling any tween already running on that part.
- API: no public methods — runs entirely from its remote connection.
- Remotes: `Enemies/CeilingVentDoor` (listened)
- Requires: `Configs.FLAGS`, `TweenProxyService`

### ChaosLightService.luau
Client-only. Watches `Floor1Light` models for the server-set `ChaosRed` attribute; while it is true every `Light` under the model is recoloured to the config red, and the captured baseline colours are restored the moment the server clears it. Purely event-driven — no per-frame loop — and streaming-safe because the tag listener rebinds models as they stream in with the attribute already replicated.
- API: `ChaosLightService:IsRed(model: Model) -> boolean` — whether that light model is currently forced red
- Tags: listens `Floor1Light`
- Requires: `Configs.ChaosLightConfig`, `TagService`

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
Client-only. Builds the small "hacked / total" pill in the top-right corner, reading both numbers from `ComputerService:GetProgress()` so the display stays stable while computers stream in and out. Hidden when there are no computers, and pulses its stroke and text once all of them are hacked.
- API: `ComputerHUDService:GetProgress() -> (number, number)` — hacked count and total count
- Tags: reads `HackComputer`
- Requires: `Configs.ComputerConfig`, `ComputerService`, `GuiBuilderService`; optionally `Configs.ComputerAssets` for the icon image (falls back to a text glyph)

### ComputerService.luau
Client-only. Owns the hackable computers: registers each tagged model with `InteractionService` (selectable only once its screen part has streamed in), draws the animated idle SurfaceGui on its screen part, and on activation locks the raw camera FOV, tweens the camera onto the screen, frees the camera lock through `InterfaceService:SetCameraFreed` so the cursor works during the session, disables player controls, and hands the model to `MinigameService`. Completing the minigame marks the computer hacked locally and tells the server the moment the win fanfare starts, so leaving or dying during the fanfare cannot drop the completion; the server's snapshot remote is authoritative. Hacked state is keyed by each model's `ComputerConfig.IdAttribute` string, so it survives the model instance being destroyed and recreated by streaming; a fresh snapshot is requested over the Sync remote at startup.
- API: `ComputerService.Changed` — `RBXScriptSignal` fired whenever the hacked set changes
- API: `ComputerService:IsHacked(model: Model) -> boolean` — whether that computer is already done
- API: `ComputerService:GetProgress() -> (number, number)` — hacked count and the server-synced total (falls back to counting replicated tags before the first snapshot)
- API: `ComputerService:GetFocused() -> Model?` — the computer currently under the interaction cursor
- API: `ComputerService:IsSessionOpen() -> boolean` — whether a minigame session is running
- API: `ComputerService:Activate(model: Model?) -> boolean` — opens a session on the given (or focused) computer
- Remotes: `Computer/Complete` (fired), `Computer/Sync` (listened — `{ Hacked = { id, ... }, Total = n }` replaces the whole hacked set; also fired once to request the initial snapshot)
- Tags: listens `HackComputer`
- Requires: `Configs.ComputerConfig`, `InterfaceService`, `CameraFovService`, `InteractionService`, `GuiBuilderService`, `CharacterService`; lazily and optionally requires `MinigameService` (retried once a second, and a session cannot open without it)

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

### GalleryUIService.luau
Drives the Gallery page: the ruled notepad column holds a two-wide filmstrip of every capture the player has taken or kept, and selecting one lays it out large across the scrapbook page as an `ImageLabel`, or plays it in a looping muted `VideoFrame` for a tape. Date and time come from the capture overlay drawn on the image itself rather than a separate caption. Captures still pending a decision carry a green edge in the filmstrip and expose Keep/Burn buttons under the photo. Refreshes from the Roblox gallery when the page opens, and degrades to a warning rather than erroring if `GalleryGui` is missing its expected children.
- API: none — side-effect only.
- Requires: `Classes.GalleryCard`, `Configs.CaptureConfig`, `CaptureGalleryService`, `CaptureOverlayService`, `GuiBuilderService`, `InterfaceService`, `NotificationService`

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
Client-only rendering of `Ghost` tagged models: builds a semi-transparent stand-in rig from a random friend's (or the local player's) avatar description, plays the ghost fly idle while drifting and the standing `Lurk` idle while the replicated leg is a zero-duration hold, and hides the server model behind it. Each frame it drives the rig along the server's replicated leg motion with a bob, aims the ghost's head at the player's head, and blends transparency for the fade-out/appear attributes.
- API: data table — empty; the tag listener and render-step job run on require.
- Tags: listens `Ghost` (via `TagService:Listen`, scoped to workspace); removes `Ghost` from the cloned fallback visual
- Requires: `Services.BobService`, `Services.GhostMotionService`, `Configs.AnimationConfig`, `Configs.FLAGS`, `TagService`

### GraphicsFogService.luau
Applies heavy distance fog on low graphics settings to cut render load: reads the saved quality level, or estimates one from a rolling FPS average when quality is Automatic, then blends `Lighting.FogEnd` toward the per-level distance. While fog is active it parks any Atmosphere out of Lighting and keeps a six-slab black cage parented to the camera so the skybox cannot be seen through the fog.
- API: `GraphicsFogService:GetEffectiveLevel(): number` — the saved quality level, or the current FPS-based estimate
- API: `GraphicsFogService:IsFogActive(): boolean` — whether the fog and cage are currently applied
- Requires: `Configs.GraphicsFogConfig`, `MathService`

### GravityWarpService.luau
Client executor for the Gravity Warper item, deliberately independent of the tool instance's lifetime (consuming the last charge destroys the Tool mid-warp). On `GravityWarp/Warp` it tweens the anchored root up to the ceiling while an explicit camera-roll value follows the same easing from zero to pi, applies that roll after the stock camera step, and rotates PlayerModule's two-axis look input by the same value so left/down remain left/down on screen without mutating the cached world-up frame. It enables `WallstickService` with a fixed world-down surface normal so the player remains level on ceilings and cannot transfer onto walls for the given duration, then disables it and reverses the character, camera and input roll onto the floor (raycast to the floor, falling back to a short drop). Bails out safely on death or character removal at any stage (also refusing when Wallstick is already enabled); only one warp runs at a time. Every exit path after a warp command — completion, bail-out, or failed validation — fires `GravityWarp/Finished` so the server clears the `GravityWarping` gate exactly when the client is actually done rather than on a timer.
- API: `GravityWarpService.IsActive() -> boolean`
- Remotes: `GravityWarp/Warp` (listened), `GravityWarp/Finished` (fired)
- Requires: `CharacterService`, `CommunicationService`, `TweenProxyService`, `WallstickService`, `Configs.ToolConfigs` (`Gravity Warper`: `AscendTime`, `DescendTime`, `MaxCeilingDistance`)

### GuiBuilderService.luau
Small shared helper for building GUI instances; every other UI service uses it to reach the PlayerGui and to create ScreenGuis and common UI modifiers. All four functions are dot-defined and return the instance they created.
- API: `GuiBuilderService.GetPlayerGui(): PlayerGui` — `WaitForChild("PlayerGui")` on the local player
- API: `GuiBuilderService.CreateScreenGui(name: string, displayOrder: number?, ignoreGuiInset: boolean?): ScreenGui` — parented to PlayerGui with `ResetOnSpawn = false` and sibling ZIndex behaviour; the two optional arguments are only applied when truthy
- API: `GuiBuilderService.Corner(parent: GuiObject, radius: UDim): UICorner` — adds a UICorner of that radius
- API: `GuiBuilderService.Stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke` — adds a border-mode UIStroke

### HallwayCrushDamageService.luau
Shared crush-volume helper plus the client-side kill decision for the `HallwayCrush` map oddity. Listens on `Oddities/MapCrush` for the closing region — its centre/axis/across, the vertical window, the intervals that are genuinely lethal, doorway alcoves, seals and the closing curve — then each `Heartbeat` recomputes the current clear corridor width from `workspace:GetServerTimeNow()` (the same smoothstep the server runs, so both sides agree without any per-frame traffic) and reports once when at least `MinimumHRPOverlap` of the local HRP's sampled volume is inside a lethal region, outside every doorway alcove, and the gap has closed past `KillWidth`. The server reuses the same overlap helper for every report and its delayed backstop, so a client that never reports still dies.
- Remotes: `Oddities/MapCrush` (listens for `"Start"`/`"Stop"`, fires `"Crushed"`)
- API: `HallwayCrushDamageService.GetSquishFraction(root: BasePart, region, slack: number) -> number` — sampled HRP volume fraction inside the lethal hallway/seal regions, excluding doorway alcoves
- Requires: `Services.CharacterService`, `Services.CommunicationService`

### HallwayGraphService.luau
Builds a navigable node graph from the tagged maze floor parts by intersecting hallway rectangles (perpendicular crossings and end-to-end parallel joins; the join's end-gap tolerance is twice the narrower floor's half-width, so a wide connector floor cannot bridge to a hallway dead-ending outside its walls), then offers nearest-node lookup, Dijkstra pathfinding, and walking-distance queries. Nodes inside a `SpawnSafeZone` part and edges crossing one are pruned from the graph, so nothing that routes over it ever passes through the spawn safe zone. The graph is cached and invalidated automatically whenever a tagged floor or spawn zone is added or removed.
- API: `HallwayGraph:Build() -> { RouteNode }` — forces a fresh build, bypassing the cache
- API: `HallwayGraph:Get() -> { RouteNode }` — cached node list
- API: `HallwayGraph:Invalidate()` — drops the cache
- API: `HallwayGraph:FindNearestNode(position: Vector3) -> RouteNode?` — linear scan
- API: `HallwayGraph:CountExits(node: RouteNode) -> number` — neighbor count
- API: `HallwayGraph:FindPath(from: RouteNode, to: RouteNode, edgeCost: ((RouteNode, RouteNode) -> number)?) -> { RouteNode }?` — Dijkstra with optional custom cost
- API: `HallwayGraph:GetWalkingDistance(firstPosition: Vector3, secondPosition: Vector3) -> number` — off-graph positions snapped to the nearest hallway span
- API: `HallwayGraph:IsFarFromPlayers(position: Vector3, distance: number) -> boolean` — true if no alive player root is within `distance`
- Tags: listens `MazeFloor`, `HallwayRoomFloor`, `SpawnSafeZone` (added/removed only, to invalidate the cache); `HallwayRoomFloor` nodes are marked not usable as destinations
- Requires: `Services.CharacterService`, `SpawnZoneService`, `Configs.SpawnZoneConfig`

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

### HumanoidStatsService.luau
Generic named-source stat stack for any Humanoid, not just players. Sources are set by name and compose: `Absolute` stats (`MaxHealth`, `WalkSpeed`, `JumpPower`, `Stamina`) sum their deltas from base, `Scale` stats (`SprintMultiplier`, `DetectionRadius`) multiply, and the result is clamped to each stat's configured range. Only stats a source actually names are written - the humanoid's own spawn values are captured on first use and restored when the last source stops naming that stat, so a kit that says nothing about jump never touches jump. Each stat declares an `Apply` of `Humanoid` or `Attribute`: the first three are Humanoid properties, while `Stamina`, `SprintMultiplier` and `DetectionRadius` are published as attributes on the character model, because they are consumed elsewhere - the first two by the client's `SprintService`, the last by enemy code on the server.
- API: `HumanoidStatsService:SetSource(humanoid: Humanoid, source: string, stats: { [string]: number }?)`
- API: `HumanoidStatsService:ClearSource(humanoid: Humanoid, source: string)`
- API: `HumanoidStatsService:Get(humanoid: Humanoid, statId: string) -> number`
- API: `HumanoidStatsService.ReadAttribute(character: Instance?, statId: string) -> number` - the attribute-applied stat, clamped, falling back to the stat's base when unset
- API: `HumanoidStatsService.GetDetectionRadius(character: Instance?) -> number` - 1 when the character has no modifier
- API: `HumanoidStatsService.Describe(stats) -> { { Stat, Value, Delta, Better } }` - display rows for the UI, base-valued stats omitted
- Requires: `Configs.KitConfig`

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
Client-only singleton wrapper: returns a single `Interaction` instance (an empty table on the server), which raycasts from the camera each frame to find the registered model under the crosshair, highlights it, and draws the key prompt. The `Highlight` itself is created per selection and destroyed when the selection fades out, so no Highlight instance outlives the model it adorns.
- API: `InteractionService:Register(model: Model, options: Interaction.TargetOptions)` — register a target with its prompt text/function, reach, `CanSelect`, `IgnoreOcclusion`, and `OnActivated` callback
- API: `InteractionService:Unregister(model: Model)` — drop a target and clear the selection if it was selected
- API: `InteractionService:GetSelected(): Model?` — the model currently under the crosshair
- API: `InteractionService.Selected` — BindableEvent signal fired with the newly selected model, or `nil`
- API: `InteractionService:Destroy()` — unbind the render step, action, and connections and destroy the current highlight and the prompt
- Requires: `Classes.Interaction` (which reads `Configs.DrawerConfig` and clones its prompt from the `Cursor` ScreenGui)

### InterfaceService.luau
Owns the main menu page group: enables/disables the Index, Shop, VIP, Gems, Items, KitInventory, KitsShop, RollGui, Map and Gallery ScreenGuis through an xenterface controller, blurs and pulls back the camera FOV while a page is open, and manages mouse unlocking (including a Q toggle when no page is open). Also wires hover/press motion onto tagged side buttons and close buttons using named motion presets.
- API: `InterfaceService.WireMotion(button: GuiButton, visual: GuiObject?, motionPreset: any?)` — add hover/press scale and tilt motion to any button (defaults to the button itself and the `HotelSideButton` preset)
- API: `InterfaceService:Open(pageId: string)` — open one of the known pages, warning on an unknown id
- API: `InterfaceService:Close()` — close whatever page is open
- API: `InterfaceService:GetActive(): string` — the active page id (empty string when closed)
- API: `InterfaceService:SetMouseUnlocked(unlocked: boolean, force: boolean?)` — unlock/relock the mouse; `force` pins it unlocked until cleared
- API: `InterfaceService:SetCameraFreed(freed: boolean)` — the half of unlocking that fights the camera: drops `Player.CameraMode` from `LockFirstPerson` to `Classic` (zoom stays pinned, so the view stays first person) and holds `MouseBehavior` on `Default` from a late render step, restoring the saved mode when relocked. Under `LockFirstPerson` the PlayerModule re-locks the mouse every frame and `GuiButton.Modal` has no effect, so without this the cursor appears but cannot move. Used by the Q toggle, the menu pages and `ComputerService` terminal sessions.
- Tags: listens `SideButton`, `InterfaceCloseButton`
- Requires: `Frameworks.xenterface` and its `Config.PresetConfig`, `CameraFovService`, `GuiBuilderService`, `Lighting.InterfaceBlur`
- Page ids map to their ScreenGui and page-root child name, including `Map` -> `Map`/`Main`; a page missing from that table never gets enabled.

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

### KitInventoryUIService.luau
Drives the `KitInventory` page: builds a `KitCard` for every kit the player owns, sorted rarest first, into the `Kits` ScrollingFrame (wrapped in a `KitsCanvas` CanvasGroup so hover-scaled tiles clip at the grid edge instead of bleeding over the page), marks the equipped kit on its tile, and fills the info panel with the kit's name in its rarity colour, a ViewportFrame of its showcase item, and its BUFFS/ITEMS list. The Equip button flips to EQUIPPED and goes uninteractable for the kit already worn. The nav button follows roll eligibility: it reads ROLL and opens `RollGui` for players who may use paid random items, and SHOP into `KitsShop` for everyone else. The grid's ScrollingFrame carries a `UIPadding` inset so hover-scaled and tilted tiles have room to grow inside the clip region instead of being cut at the edge. Cards deal in with a stagger each time the page opens.
- Remotes: through `KitStateService` (`Kits/Sync`, `Kits/Equip`)
- Requires: `Classes.KitCard`, `Configs.KitConfig`, `KitStateService`, `KitVisualService`, `InterfaceService`, `GuiBuilderService`, `TweenProxyService`; expects a pre-built `KitInventory.Design` tree

### KitRollUIService.luau
Drives the `RollGui` reel, the only kit-buying surface players who may use paid random items ever see. A roll asks the server first - the result is authoritative and arrives before anything moves - then a strip of `ReelLength` tiles is built with rarity-weighted filler and the real kit planted at `WinnerIndex`, and the strip slides under the centre marker on a quintic ease-out, lands slightly off centre, and settles back with a small back-ease so the stop reads as mechanical rather than snapped.
The motion is a carousel, not a sliding line: a render-step job scales every tile by how near its centre is to the marker and tilts it by its signed offset (tiles are centre-anchored, so a `UIScale` grows and a rotation turns them about their own middle - anchored at the left edge they grew rightwards and the gaps either side of the winner came out uneven), the reel is a CanvasGroup whose `EdgeFade` UIGradient dissolves tiles at both edges, and the marker kicks each time a new tile takes the centre. On landing the winner grows and its rarity stroke flares, a rarity-coloured `Backdrop` blooms and fades behind the reel, the reel shakes with a strength scaled by rarity order, and the result panel slams in from `ResultPop`. Duplicates say so and name the gem refund. Failures (not enough gems, restricted account, save still loading) show as a notice instead of a spin, and the button reads UNAVAILABLE for restricted accounts.
- Remotes: through `KitStateService` (`Kits/Roll`, `Gems/Sync`)
- Requires: `Configs.KitConfig`, `KitStateService`, `KitVisualService`, `MathService`, `InterfaceService`, `GuiBuilderService`; borrows the card template from `KitsShop.Design.Kits.Template`

### KitShopUIService.luau
Drives the `KitsShop` page - the straight-purchase path, reached only by players who cannot use paid random items; anyone who can roll is sent to `RollGui` instead and never sees this page. A `KitCard` for every kit in the catalogue, sorted most common first, with owned kits dimmed and marked OWNED and the rest showing their rarity's gem price. Like the inventory's, the grid is inset with a `UIPadding` so hover-scaled tiles do not clip at the edges. Every gem figure - prices, the tile badges and the balance - goes through `MathService.Comma`, and the balance reads `KitConfig.Text.BalancePrefix` before its number. The info panel mirrors the inventory's, plus the gem price badge and a buy button that reads BUY, OWNED or NOT ENOUGH and only stays interactable when the purchase can actually go through. The gem balance flashes green or red on the purchase result. The Robux button gets hover/press motion but is deliberately inert - it prompts nothing yet.
- Remotes: through `KitStateService` (`Kits/Sync`, `Kits/Purchase`, `Gems/Sync`)
- Requires: `Classes.KitCard`, `Configs.KitConfig`, `KitStateService`, `KitVisualService`, `MathService`, `InterfaceService`, `GuiBuilderService`, `TweenProxyService`; expects a pre-built `KitsShop.Design` tree

### KitStateService.luau
Client-side single source of truth for kits and gems: owns the `Kits/Sync` and `Gems/Sync` subscriptions plus the `Gems` and `CanRoll` player attributes, and hands the three kit pages one shared view instead of three competing ones. Also the client's outbound side - equipping, buying and rolling all go through here.
- API: `KitStateService:IsOwned(kitId: string) -> boolean`
- API: `KitStateService:GetEquipped() -> string`
- API: `KitStateService:GetGems() -> number`
- API: `KitStateService:CanAfford(kitId: string) -> boolean`
- API: `KitStateService:CanRoll() -> boolean` - false until the server's PolicyService lookup lands, and for restricted accounts
- API: `KitStateService:Equip(kitId: string)` / `:Buy(kitId: string)`
- API: `KitStateService:RequestRoll() -> { Ok, Reason?, KitId?, Duplicate?, Refund?, Gems }` - yields on the server
- API: `KitStateService.KitsChanged` / `.GemsChanged` - signals carrying the server's result code
- Remotes: `Kits/Sync`, `Kits/Equip`, `Kits/Purchase`, `Kits/Roll`, `Gems/Sync` (all listened and fired)
- Requires: `Configs.KitConfig`, `CommunicationService`

### KitVisualService.luau
The look of a kit, shared by all three kit pages so they cannot drift: renders a tool model into a ViewportFrame with the framing and lighting from `KitConfig.Viewport` (an explicit `Ambient`/`LightColor`/`LightDirection`, without which tool models read as near-black silhouettes), picks a kit's showcase item (explicit `Showcase`, else its most expensive item), dresses a card with its rarity stroke, rarity ribbon, name, status line and dim overlay, and fills a details holder with a `BUFFS` section and an `ITEMS` section. The sections stack vertically at the holder's full width rather than sitting side by side - the info column is only ~180px wide, so two columns made every row width-bound and tiny. Row height is the holder divided by the line count (floored at `MINIMUM_LINES` so short kits do not get comically large rows) and rows fade in on a stagger. Rows keep `TextScaled` on and never set `TextWrapped = false` - in Roblox that assignment silently clears `TextScaled` too, which drops every row to the default 8px. Stat rows are green when the change helps and red when it hurts, which is how a lower `DetectionRadius` reads as a gain.
- API: `KitVisualService.Showcase(kit) -> string?`
- API: `KitVisualService.BuildPreview(viewport: ViewportFrame, itemName: string?)`
- API: `KitVisualService.DressCard(button: ImageButton, kit)`
- API: `KitVisualService.SetCardStatus(button: ImageButton, text: string, dimmed: boolean, color: Color3?)`
- API: `KitVisualService.FillDetails(holder: Frame, kit, animate: boolean)`
- API: `KitVisualService.SortByRarity(entries, rarestFirst: boolean) -> { Kit }`
- API: constants - `Ink`, `Good`, `Bad`, `Font`, `BoldFont`
- Requires: `Configs.ItemShopConfig`, `Configs.KitConfig`, `HumanoidStatsService`, `MathService`

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

### MapControlService.luau
Client-only. Owns panning and zooming of the map contents inside the clipped viewport. Left-drag or a one-finger touch pans, the scroll wheel or a two-finger pinch zooms about the pointer, and both settle through an exponential ease. Panning tracks absolute pointer positions rather than `InputObject.Delta`, because Delta is zero for mouse movement while the cursor is unlocked. Offsets are clamped so the map cannot be dragged off the paper.
- API: `MapControlService:Attach(viewport: Frame, content: Frame)` — takes ownership of the content transform
- API: `MapControlService:Detach()` — disconnects and clears input state
- API: `MapControlService:Reset()` — returns to fully zoomed out and centred
- API: `MapControlService:GetZoom() -> number`
- Requires: `Configs.MapConfig`, `Services.MathService`

### MapInkService.luau
Client-only. Rasterises the hand-drawn map onto a `MapCanvas`. Every wall and dead-end cap is generated procedurally from the hallway rectangles: a per-wall seeded wobble (two summed sine harmonics keyed off the hallway coordinate, not the drawn piece, so progressively revealed sections line up seamlessly), a width that varies along the run and tapers at genuine ends, an overshoot past real corners, and a wider low-alpha bleed pass underneath. Rooms are drawn instead as complete boxes; a computer room gets a heavier outline and a diagonal hatch fill, and can draw itself on over time. Junction mouths and partially revealed spans are subtracted before drawing, so no wall is ever drawn across an opening. Overshoot is applied only where a wall genuinely ends, never at a junction mouth, and pieces shorter than a minimum are discarded, which keeps intersections free of stray tick marks. Drawing is append-only and idempotent because the canvas composites with max alpha.
- API: `MapInkService:Attach(paper: ImageLabel)` — builds the canvas and its `Ink` ImageLabel, resetting drawn and style state
- API: `MapInkService:Detach()` — destroys the label and canvas
- API: `MapInkService:IsAttached() -> boolean`
- API: `MapInkService:Reveal(key: string, packed: { number }) -> boolean` — draws only the not-yet-drawn part of a hallway's revealed intervals; false when nothing was new
- API: `MapInkService:Flush()` — pushes the dirty rectangle to the EditableImage
- API: `MapInkService:RevealAnimated(key: string, packed: { number }, duration: number) -> boolean` — draws a room's sides and hatch progressively over `duration`
- API: `MapInkService:IsDrawn(key: string) -> boolean`
- API: `MapInkService:LoadDiscovered(store)` — replays a whole discovery table, yielding to stay inside a frame budget
- Requires: `Configs.MapConfig`, `Classes.MapCanvas`, `Services.MapLayoutService`

### MapLayoutService.luau
Client-side geometric model of the map. Loads the rectangle list the server sends, derives the world-to-canvas projection (square fit with a configurable margin), and precomputes, for each corridor, the intervals along both side walls and both end caps that are covered by another corridor. Entries carry a `Kind` of `Hallway`, `Connector`, `Room` or `ComputerRoom`; only corridors take part in opening calculations, so a room never punches a hole in the hallway wall it sits behind and is drawn as a closed box. Those openings are what turn a grid of rectangles into a maze with connected corridors.
- API: `MapLayoutService:Load(layout: { any })` — rebuilds entries, projection and openings
- API: `MapLayoutService:IsLoaded() -> boolean`
- API: `MapLayoutService:GetEntries() -> { Entry }`
- API: `MapLayoutService:Get(key: string) -> Entry?`
- API: `MapLayoutService:IsRoomKind(entry: Entry) -> boolean` — true for `Room` and `ComputerRoom`
- API: `MapLayoutService:GetScale() -> number` — canvas pixels per stud
- API: `MapLayoutService:ToCanvas(worldX: number, worldZ: number) -> Vector2`
- API: `MapLayoutService:WallPoint(entry: Entry, side: number, along: number) -> Vector2`
- API: `MapLayoutService:Subtract(minimum, maximum, openings) -> { { number } }` — interval minus a packed opening list
- Requires: `Configs.MapConfig`

### MapService.luau
Client-only front end for the map. Waits for the `Map` ScreenGui's paper `ImageLabel`, loads each sync into `MapLayoutService`, attaches `MapInkService` to the paper, replays stored discovery, and applies incremental reveals with a deferred flush so a burst of reveals costs one write. Also owns the local player marker, repositioned every render step.
- API: `MapService:GetPaper() -> ImageLabel?`
- API: `MapService:ToPaperScale(worldX: number, worldZ: number) -> UDim2` — world position as a scale offset inside the paper
- Builds a clipped `Viewport` holding a pannable `Content` frame; the ink, markers, local player dot and other players' headshot markers all live inside it so they pan and zoom together
- A computer room discovered while the map is shut is queued, then draws itself on with its marker popping shortly after, the next time the `Map` page is opened; one discovered while the map is already open plays immediately
- Remotes: `Map/Sync` (listened), `Map/Reveal` (listened), `Map/Landmark` (listened)
- Requires: `Configs.MapConfig`, `Classes.MapMarker`, `CharacterService`, `CommunicationService`, `MapControlService`, `MapInkService`, `MapLayoutService`

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
Small pure-math helper library shared across the codebase: easing, framerate-independent lerp alphas, horizontal-plane vector work, angles, pulses, and number formatting. No state, no connections.
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
- API: `MathService.Comma(value: number) -> string` — rounds to a whole number and groups thousands with commas; the single place any UI turns a currency or count into text

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
- API: `MinigameService:Open(model: Model, screen: BasePart, callbacks: { OnExit, OnComplete })` — closes any current session first; `OnComplete` fires the moment the win fanfare begins, and `OnExit` fires when the session ends (fanfare finished, exit button, or replaced)
- API: `MinigameService:Close()` — serializes unfinished progress into a weak per-model cache, clears it on a win
- API: `MinigameService:IsOpen() -> boolean`
- API: `MinigameService:GameFor(model: Model) -> string` — assigns a game id by sorting the terminals in the same `Maze*` ancestor
- API: `MinigameService:ResolvedFor(model: Model) -> string` — alias for `GameFor`
- API: `MinigameService.Theme` — the shared arcade `Theme` table handed to every game module
- API: `MinigameService.List` — ids that actually loaded, from `{ "Memory", "AimTrainer", "Frogger", "Snake", "Simon" }`
- Tags: reads `HackComputer` (to enumerate peer terminals)
- Requires: `Classes.Minigames.<Id>` modules, each exporting `Id`, `Title`, `SupportsReset`, `new(root, api)`

### NotificationService.luau
Client-only top-center notification banner. Listens for short server messages, renders them in a stacked panel with the shared GUI builder, and fades each one in and out automatically. Client code that needs to say something locally calls `Show` directly rather than round-tripping the server.
- API: `NotificationService:Show(message: string)` — render a banner on this client
- Remotes: `Notifications/Show` (listened)
- Requires: `Configs.NotificationConfig`, `Services.CommunicationService`, `Services.GuiBuilderService`

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

### PerfGraphService.luau
Client-only developer panel behind `FLAGS.PerfGraph`, toggled with F8. Two time-aligned scrolling graphs sharing one X axis (one column per frame, newest at the right edge, bars slide left): the top plots FPS from every RenderStepped delta on a fixed 0-`FpsMaximum` scale coloured by the config thresholds; the bottom is a stacked graph of Workspace descendants added plus removed during that same frame on a fixed 0-`ChurnMaximum` scale, each instance bucketed into the first `ChurnCategories` entry whose `Classes` it `IsA` (parts, models/folders, scripts, lights, effects, textures/meshes, audio, joints/attachments, gui, values, characters/anim, other) and drawn in that category's colour with a key under the header. Both draw labelled reference lines from the config, never auto-scale, show single-instance frames as a one-pixel tick, and cap bars that exceed the top in `ClipColor`. Pause freezes both together; Clear resets them.
- API: none — the panel is built at require time.
- Requires: `Classes.DebugPanel`, `Configs.PerfGraphConfig`, `Configs.FLAGS`

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

### PhotoCaptureService.luau
Client half of the tripod Camera's shutter. On the snap remote it flashes the screen white, hides every `LayerCollector` under PlayerGui plus every core GUI type and the topbar, hides the viewmodel, clones the named figure rig locally (anchored, never replicated) at the server-chosen CFrame, and pins the camera to the tripod's lens while calling `CaptureGalleryService:TakeScreenshot`. The figure is cloned and the camera is moved `Capture.WarmupFrames` before the shutter, all of it behind the opaque flash, because a model parented the same frame it is photographed renders unshaded — that warmup is what keeps a dark rig from coming out default grey. Frame waits are deadline-bounded and every restore is guarded, so a client that stops rendering mid-shot (alt-tab) still gets its camera, character and interface back. GUIs are unparented rather than merely disabled, because services like MinimapService re-assert `Enabled` every render step and would otherwise win the frame the shutter fires. Every held frame re-asserts the whole disguise — GUIs stay unparented, the local character's parts stay visible, and its root is turned to the player's real camera yaw so a first-person player is photographed facing where they were looking rather than where they last walked.
The camera never visibly snaps back: the finished photo is handed to PhotoDevelopService full-screen while the flash is still white, and only then are the camera, viewmodel, character and interface restored behind it, so the flash covers the jump out and the photo covers the jump home. Warns when the figure rig is missing from `ReplicatedStorage.Enemies`. Captures are per-client, so every player in the shot takes their own copy of the same framing, and Roblox scopes them to their owner — a photo can never be shown to anyone else.
- API: `PhotoCaptureService:Take(lens: CFrame, fieldOfView: number, figure: CFrame?, figureName: string?)` — run the whole flash/capture/restore sequence
- Remotes: `Photo/Snap` (listened)
- Requires: `Configs.PhotoConfig`, `CaptureGalleryService`, `CommunicationService`, `GuiBuilderService`, `PhotoDevelopService`

### PhotoDevelopService.luau
Shows a captured photo as a sheet of film developing. A photo arriving from the shutter fills the whole screen (oversized so its frame sits off-view, masking the camera's return to the player), holds, then flies down into the corner. The image carries its final grade from the first frame it exists, so nothing about it changes tone while the player is looking at it; the film feel comes from a developer sheen that sweeps across once as it travels. Clicking the preview grows a large copy out of the preview's own rectangle over a dimmed backdrop, and closing it shrinks back into the same rectangle rather than cutting. The preview stays until it is closed with its own corner button; clicking the photo itself opens a large centred copy over a dimmed backdrop, closed by its close button or by clicking the backdrop. A new photo replaces whatever is on screen.
- API: `PhotoDevelopService:Show(media: CaptureGalleryService.Media, fullscreen: boolean?)` — build and animate a capture, arriving full-screen when `fullscreen` is set. A capture that has not yet been kept holds full-screen behind Keep/Burn buttons instead of shrinking on a timer; keeping it settles it into the corner, burning it slides it away
- API: `PhotoDevelopService:Expand()` / `PhotoDevelopService:Collapse()` — open and close the large view of the current photo
- API: `PhotoDevelopService:Hide()` — slide the preview away and destroy it
- Requires: `Configs.CaptureConfig`, `Configs.PhotoConfig`, `CaptureGalleryService`, `CaptureOverlayService`, `GuiBuilderService`, `NotificationService`

### PhotoTimerService.luau
Draws the countdown above every placed tripod camera: a billboard over the camera body that ticks down whole seconds against the model's server-time `SnapAt` attribute, pulsing each change and turning red near zero, then flashes `SNAP` and hides itself once the `Snapped` attribute is set. The tagged model can arrive before its parts replicate, so the billboard waits (up to five seconds) for the camera body to exist rather than silently skipping that camera.
- API: none — side-effect only.
- Tags: listens `PhotoConfig.Tag`
- Requires: `Configs.PhotoConfig`, `TagService`

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

### SpawnZoneService.luau
Shared registry of the spawn safe zone parts (tagged `SpawnSafeZone`): keeps the tagged workspace parts cached and answers geometric queries against their oriented boxes. Used to keep the hallway graph, enemy spawn placement and enemy behaviour out of the safe area around the maze spawn.
- API: `SpawnZoneService:GetZones() -> { BasePart }` — current zone parts
- API: `SpawnZoneService:Contains(position: Vector3) -> boolean` — point inside any zone box, with the box's vertical extent padded by `SpawnZoneConfig.VerticalPad` so floor-level points under a hovering zone still count
- API: `SpawnZoneService:IntersectsSegment(from: Vector3, to: Vector3) -> boolean` — slab test of the segment against every zone box, vertically padded the same way
- Tags: reads `SpawnSafeZone` (added/removed refresh the cache)
- Requires: `Configs.SpawnZoneConfig`

### SpeedBoostRenderService.luau
Client screen effect for speed boosts: watches the local player's `SpeedBoostFov` attribute and tweens both a camera FOV offset and a `ColorCorrectionEffect` (saturation, contrast, warm tint) in and out, disabling the effect once it fully returns to zero.
- API: none — side-effect only.
- Requires: `CameraFovService`, `TweenProxyService`; reads the `SpeedBoostFov` player attribute

### SprintBoostUIService.luau
Client-only decorated overlay for the stamina bar while a speed boost is active: a gradient/streak/sheen CanvasGroup fill inside the sprint bar plus a separate overlay ScreenGui with aura stroke, expanding rings, flash, pop scale, remaining-time bar and a chromatic label. All visuals are read per-boost from `SprintBoostConfig.Boosts[name]`.
- API: none — side-effect only.
- Requires: `Configs.SprintBoostConfig`, `Configs.SprintConfig`, `SprintUIService` (`GetBar`, `SetForcedVisible`), `GuiBuilderService`; reads the `SpeedBoostName` and `SpeedBoostEndsAt` player attributes

### SurfaceCursorService.luau
Maps a viewport point onto a `SurfaceGui` canvas by intersecting the camera ray with the adorned face's plane, so in-world screens stay clickable even when their part is parented to the camera (where Roblox delivers no native GUI input). Handles all six `NormalId` faces and returns nil when the ray misses or the plane is behind the camera.
- API: `SurfaceCursorService:Project(part, face, viewportPoint, canvasSize) -> Vector2?` — canvas pixel coordinates
- API: `SurfaceCursorService:Contains(element, point, padding?) -> boolean` — hit-test a `GuiObject` against a projected point, optionally growing it by `padding` canvas pixels
- API: `SurfaceCursorService:GetAlpha(element, point) -> number` — 0-1 position across an element, for sliders
- API: `SurfaceCursorService:GetFaceSize(part, face) -> Vector2` — the face's stud dimensions
- API: `SurfaceCursorService:GetFaceBasis(face)` — the face's right/up/normal unit vectors in part space
- API: `SurfaceCursorService:GetElementFrame(part, face, element, canvasSize) -> (Vector3, Vector2)` — a GUI element's centre offset in part space and its size in studs, for framing a screen in view
- Requires: nothing

### SprintService.luau
Client sprint state machine: binds hold-to-sprint keys (plus a touch toggle button), drains and regenerates stamina with an exhaustion lockout, and owns the humanoid's `WalkSpeed`. Maximum stamina and the sprint speed multiplier are per-character rather than fixed: both are read every time they are needed from the `Stamina` and `SprintMultiplier` character attributes through `HumanoidStatsService.ReadAttribute`, falling back to `SprintConfig` when unset, which is how a kit raises a player's stamina pool or sprint speed. It watches external WalkSpeed writes to re-derive the base speed and respects the server's speed-boost attributes, drives the sprint FOV offset, and uses Wallstick's movement source while the local character is surface-stuck.
- API: `SprintService:GetStaminaFraction() -> number` — 0..1
- API: `SprintService:IsSprinting() -> boolean`
- API: `SprintService:IsExhausted() -> boolean`
- API: `SprintService:GetWeight() -> number` — eased 0..1 sprint blend, used for camera effects
- API: `SprintService:SetSpeedFactor(name: string, factor: number?)` — named multiplicative modifiers; `nil` removes
- API: `SprintService:SetSprintBlocked(name: string, blocked: boolean)` — named blockers; blocking also drops held/toggled state
- Requires: `Configs.SprintConfig`, `CameraFovService`, `WallstickService`; reads the `SpeedBoostSpeed` / `SpeedBoostBaseSpeed` player attributes

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
One-question helper for whether a character should be treated as absent: it carries the `Ignore` tag, the `IgnoreExceptEye` tag or has a ForceField anywhere inside it. The Eye enemy uses `IsForEye`, which deliberately skips the `IgnoreExceptEye` tag so it can still damage ceiling-warped players.
- API: `Vanished.Is(character: Instance?) -> boolean` — tagged `Ignore`, tagged `IgnoreExceptEye` or contains a ForceField
- API: `Vanished.IsForEye(character: Instance?) -> boolean` — tagged `Ignore` or contains a ForceField only
- API: `Vanished.Tag` — the string `"Ignore"`
- API: `Vanished.EyeExemptTag` — the string `"IgnoreExceptEye"`
- Tags: reads `Ignore`, `IgnoreExceptEye`
### ViewmodelService.luau
Client first-person viewmodel: clones the equipped Tool (stripped of scripts, sounds and effects) under the camera, hides the real tool (its parts *and* its SurfaceGuis, which transparency alone cannot hide), and each render step positions the clone from camera CFrame plus yaw sway and speed-scaled bob. Auto-hides when not in first person or when the character's real hand is visible; supports per-tool anchor/rotation overrides, a per-tool `Scale` override for props too large for the shared scale, and named poses that other services switch between, lerped at the override's `PoseSpeed`. A pose either shifts the base placement (`AnchorOffset`, `ArmAnchorOffset`, `RotateOffset`, so live tuning of the base carries into it), replaces it outright (`Anchor`, `ArmAnchor`, `Rotate`), or declares a `Framing` block and is solved from the rig's own geometry — squaring a named part's face to the camera and backing off until a named GUI element covers the requested fraction of the viewport, which keeps it centred and upright no matter how the base pose or `Scale` are tuned. Exposes the currently equipped Tool for client debug panels.
- API: `ViewmodelService:SetPose(pose: string?)` — select a named entry from the current tool's `Overrides[tool].Poses`, or `nil` for the base placement
- API: `ViewmodelService:SetPoseOverride(active: boolean, pose: string?)` — pin a pose regardless of `SetPose`, for the debug panel
- API: `ViewmodelService:GetDefaultAnchor() -> Vector3?` — default fit anchor for the equipped viewmodel
- API: `ViewmodelService:GetTool() -> Tool?` — currently equipped tool in the viewmodel
- API: `ViewmodelService:GetPose() -> string?`
- API: `ViewmodelService:GetRig() -> Model?` — the live viewmodel clone, for services that drive its contents
- API: `ViewmodelService:Refresh()` — rebuild the rig for the current tool
- Requires: `Configs.ViewmodelConfig` (`Scale`, `Fit`, `HandOffset`, `Arm`, `Overrides`), `MathService`, `SurfaceCursorService` (face geometry for framed poses)

### ViewmodelDebugService.luau
F3 developer panel for live tuning of every equipped first-person tool. It follows the selected tool's override, seeds tools without one from the viewmodel's default fit, and updates the title and selectable generated config entry as tools change. A state button cycles Live (the game drives the pose), Base and each configured pose; it only appears when the selected tool has pose states, and pose overrides are released when another tool is selected. Sliders control scale, tool anchor, fake-hand anchor and all three rotation axes — reading absolute values for the base state and offsets for a pose — plus screen coverage for framed poses, which is the only placement control those have. The selectable text box emits the whole config entry including every pose, so pasting it back cannot drop them.
- Requires: `Configs.ViewmodelDebugConfig` (`ToggleKey`, `Step`, `AngleStep`, `PoseOrder`), `Configs.ViewmodelConfig`, `Configs.FLAGS`, `Classes.DebugPanel`, `ViewmodelService`

### VoiceActivityService.luau
Client voice-activity detector: wires an `AudioAnalyzer` onto the local player's `AudioDeviceInput`, polls RMS level against a threshold, and tells the server when you start and stop speaking (with a heartbeat re-send and a release delay). Stops analyzing on death, mutes remote voice emitters locally until respawn, and rebuilds itself if the input device appears or disappears. This drives proximity voice and enemy hearing only — walkie-talkie transmission is toggle-controlled and does not use it.
- API: `VoiceActivityService:GetLevel() -> number` — the analyser's current RMS level, or 0 when there is no live unmuted input
- Remotes: `WalkieTalkie/VoiceActivity` (fired)
- Requires: `Configs.VoiceChatConfig` (`Activity.PollInterval`, `.Threshold`, `.Heartbeat`, `.Release`)

### VoiceDebugService.luau
Client-only debug panel behind `FLAGS.VoiceDebug` with sliders for proximity-voice and radio volumes. To make proximity voice adjustable it rewires every remote player's direct voice wire through an inserted `AudioFader`; radio sliders write straight into the named faders it finds in Players and Workspace, matching the local listener's own per-sender `RadioVoice_<id>` and `RadioMonster_<id>` faders. All changes are local and session-only.
- API: none — side-effect only.
- Requires: `Classes.DebugPanel`, `Configs.VoiceDebugConfig`, `Configs.FLAGS`

### WalkSoundService.luau
Client footstep engine for players and tagged enemies. Silences the default Roblox running sound and instead times steps from the character's looping Core-priority locomotion track (falling back to a speed-scaled interval), playing a random emitter from `Sounds.Footsteps`. Enemies get custom distance attenuation out to 45 studs and per-enemy volume; crouching players get quieter, slower, shorter-range steps.
- API: none — side-effect only.
- Tags: listens `Enemy`
- Requires: `AudioService.Play3DSound`, `CharacterService.ForEachPlayer`, `TagService`, `Configs.WalkSoundConfig`, `Configs.CrouchConfig` (`Stealth`)

### WalkieTalkieService.luau
Client walkie-talkie brain: owns power, equip, raised and toggle-transmit state, and all local audio routing. Power (`Keys.Power`, default G) is independent of holding the tool — a powered radio keeps receiving from the backpack, but transmitting needs it equipped. Transmission toggles on left mouse (or the touch TALK button) and drives the `Talk` viewmodel pose; `Keys.Raise` (default R) lifts the radio into the `Raised` pose for the full-screen UI. Mutes the player's own radio emitter via a private `AudioInteractionGroup`, crossfades each remote player's proximity voice against their incoming radio route by listener distance, multiplies that route by the local per-player mute/volume, and reads each route's level from an `AudioAnalyzer` for the roster meters. Category and per-player sliders remain normalized from 0–100% while translating through their configured maximum gains. Your own meter follows your microphone through `VoiceActivityService:GetLevel` while transmission is toggled on, with the same gain and attack/release ballistics as everyone else's, rather than pinning to full. Refuses to power on when voice chat is unavailable for the user.
- API: `WalkieTalkieService:SetPowered(value)` / `:TogglePower()` / `:IsPowered() -> boolean`
- API: `WalkieTalkieService:SetEquipped(value)` / `:IsEquipped() -> boolean` — driven by the tool class
- API: `WalkieTalkieService:SetRaised(value)` / `:ToggleRaised()` / `:IsRaised() -> boolean`
- API: `WalkieTalkieService:SetTransmitting(value)` / `:IsTransmitting() -> boolean`
- API: `WalkieTalkieService:ToggleTransmitting()` — toggle transmission on left mouse or the touch TALK button
- API: `WalkieTalkieService:GetMode() -> string` / `:GetModeLabel() -> string` / `:CycleMode()`
- API: `WalkieTalkieService:GetCategory(id) -> number` / `:SetCategory(id, value)` — the `Config.Categories` volume sliders
- API: `WalkieTalkieService:IsMuted(player)` / `:SetMuted(player, value)` / `:GetPlayerVolume(player)` / `:SetPlayerVolume(player, value)` — local only
- API: `WalkieTalkieService:GetRoster() -> { { Player, Category, Level } }` — sorted Enabled, then Disabled, then NoVoice; alphabetical by display name within each
- API: `WalkieTalkieService:GetLevel(player) -> number` / `:GetCategoryFor(player) -> string` / `:GetTool() -> Tool?`
- Remotes: `WalkieTalkie/SetMode`, `WalkieTalkie/SetPower`, `WalkieTalkie/SetTransmit` (fired), `WalkieTalkie/SetAudio` (fired and listened — the server replies with the saved settings on join)
- Requires: `Configs.WalkieTalkieConfig`, `Configs.VoiceChatConfig`, `MathService`, `ViewmodelService`, `VoiceActivityService`

### WalkieUIService.luau
Client owner of the walkie-talkie's on-model screen. Binds to the `SurfaceGui` inside the viewmodel rig (falling back to the real tool), clones the authored `Row` and `SettingRow` templates out of `Main.Body`, and each render step repaints the roster — status dot, display name, status line and level meter — plus the header, footer hint and the OFF overlay. Raising the radio unlocks the cursor through `InterfaceService` and swaps each row's meter for its mute button and volume slider; the header's `Mode` button cycles All/Friends and `Settings` flips to the category sliders. Because a `SurfaceGui` on a part parented to the camera receives no native input, every click, drag and slider is dispatched from `SurfaceCursorService` projections against the gui's authored `CanvasSize`; the system mouse cursor is the pointer, and the game's own `Cursor` crosshair is disabled while the radio is raised. Ray points are always inset-included screen coordinates — `GetMouseLocation()` for the mouse, and the touch `InputObject.Position` plus `GetGuiInset()` — because `InputObject.Position` alone lands one GUI inset above the visible cursor. The scroll wheel scrolls the roster whenever the radio is on and equipped, without the cursor being over it; touch drags on the surface do the same.
- API: none — side-effect only.
- Requires: `Configs.WalkieTalkieConfig`, `InterfaceService`, `SurfaceCursorService`, `ViewmodelService`, `WalkieTalkieService`; the `Main` frame authored inside `ReplicatedStorage.Tools["Walkie Talkie"].Screen.Screen`

### WalkieHudService.luau
Client screen-space companion to the walkie-talkie. Drives the `WalkieHud` ScreenGui authored in StarterGui: fades `Main.Prompt` (text and stroke together) in while the radio is equipped but off, and shows `Main.Touch`'s PWR / RADIO / TALK buttons on touch devices to toggle power, raise the radio and toggle transmission. Layout and colours live on the instances; the service only supplies the prompt strings, the fade time and the pressed-state background.
- API: none — side-effect only.
- Requires: `Configs.WalkieTalkieConfig` (`Prompt`, `Touch.ActiveBackground`, `Keys`), `GuiBuilderService`, `WalkieTalkieService`; the `WalkieHud` ScreenGui in StarterGui

### WallstickService.luau
Client front end for the vendored Wallstick controller. Always listens on the replication channel so other players' wall-stuck characters render correctly; wall-sticking for the local character is opt-in via `Enable`, which runs an auto-stick raycast loop under the character's feet each `PreSimulation` (like the upstream demo, resetting to normal gravity after a long fall), optionally limits transfers to surfaces aligned with a fixed world-space normal, and tears down on death or character removal. Guarded to be inert on the server.
- API: `WallstickService.Enable(options: { tilt: boolean?, spin: boolean?, surfaceNormal: Vector3? }?) -> Wallstick?` — starts wall-sticking for the local character; `surfaceNormal` rejects differently oriented surfaces and keeps accepted surfaces exactly aligned to that normal; returns the active (or existing) instance
- API: `WallstickService.Disable()` — destroys the session and restores normal character physics
- API: `WallstickService.IsEnabled() -> boolean`, `WallstickService.Get() -> Wallstick?`
- API: `WallstickService.GetMoveDirection() -> Vector3` — current movement direction from the hidden surface-walking humanoid, or zero when disabled
- API: `WallstickService.SetCameraInputRoll(roll: number)` — rotates PlayerModule's two-axis look input into the currently displayed camera roll without changing PlayerModule's cached world-up frame
- Remotes: `Wallstick/Replicator`, `Wallstick/Sync` (via `Classes.Wallstick.Replication`)
- Requires: `Classes.Wallstick` (+ its `RaycastHelper` and `Replication` children); expects `workspace.Wallstick` from the server `WallstickService`
