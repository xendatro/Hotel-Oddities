# ReplicatedStorage / Classes

Roblox class-syntax classes. Connections live in `self.Connections`, built by a local `setUpConnections`.

### Animation.luau
Plays one looping animation on a rig, chosen by the rig's `Animation` string attribute looked up in `ReplicatedStorage.Animations`. Warns and returns an inert object if the named animation is missing.
- API: `Animation.new(rig: Model) -> Animation` — loads, sets Action priority, loops and plays immediately
- API: `Animation:Destroy()` — stops and destroys the track

### Breathe.luau
RigMotion subclass that adds a subtle idle breathing offset to a rig's Root, Waist, Neck and Shoulder joints. Only breathes while the local player is within `BreatheConfig.MaxDistance`, easing the amplitude to zero otherwise.
- API: `Breathe.new(rig: Model) -> Breathe` — inherits RigMotion's PreAnimation/PreSimulation loop
- API: `Breathe:Update(deltaTime: number)` — advances the phase and applies joint offsets
- API: `Breathe:RemoveApplied()` — undoes last frame's joint transforms
- Requires: `Classes.RigMotion`, `Configs.BreatheConfig`, `Services.MathService`

### ClientTool.luau
Client-side base class for tools, extending ToolBase with limb-reveal in first person, tool animation lookup and stock consumption. Limb reveal is refcounted globally across tools and drives `LocalTransparencyModifier` on a render-step bind.
- API: `ClientTool.extend(className: string) -> class` — makes a subclass of ClientTool
- API: `ClientTool.new(tool: Tool, class: any?) -> ClientTool` — builds an instance (defaults to ClientTool)
- API: `ClientTool:Consume(n: number?)` — asks the server to remove `n` (default 1) of this tool
- API: `ClientTool:WaitForToolAnimation(animationName: string, timeout: number?) -> AnimationTrack?` — yields for a track under `Tool.Animations`, nil on timeout (default 2s)
- API: `ClientTool:RevealLimbs()` — fades own limbs in first person using `Config.LimbTransparency`
- API: `ClientTool:ReleaseLimbs()` — drops this tool's reveal claim
- API: `ClientTool:_BeforeActivate()` / `ClientTool:_AfterActivate()` — auto reveal/release when `Config.RevealLimbs`
- API: `ClientTool:OnDestroy()` — releases limbs
- Remotes: `Backpack/Delete` (fired)
- Requires: `Classes.ToolBase`, `Services.CommunicationService`

### Deadline.luau
Runs a function but gives up after `n` seconds, using Race against a `task.wait`. Fires once; a second `Fire` is a no-op.
- API: `Deadline.new(f: () -> (), n: number) -> Deadline` — the function and its time limit
- API: `Deadline:Fire() -> boolean?` — yields; true if the function won, false if it timed out
- Requires: `Classes.Race`

### DebugPanel.luau
Builds a keyboard-toggled developer overlay ScreenGui with labels, buttons and drag sliders. Toggling unlocks the mouse through InterfaceService and hides `PlayerGui.SideGui` while any debug panel is open, restoring its prior state after the last panel closes.
- API: `DebugPanel.new(title: string, toggleKey: Enum.KeyCode) -> DebugPanel` — creates the hidden panel in PlayerGui
- API: `DebugPanel:SetTitle(title: string)`
- API: `DebugPanel:AddLabel(text: string) -> TextLabel`
- API: `DebugPanel:AddTextBox(text: string) -> TextBox` — creates selectable, editable multiline text
- API: `DebugPanel:AddButton(text: string, activated: () -> ()) -> TextButton`
- API: `DebugPanel:AddSlider(label, minimum, maximum, initial, step, apply: (number) -> ()) -> (number) -> ()` — returns a setter that redraws the slider
- API: `DebugPanel:Destroy()`
- Requires: `Services.InterfaceService`

### DoorPart.luau
Spring-driven swinging door leaf: picks a hinge side from who opened it, swings toward the opener, and can be driven instead by the length of the door audio clip. Also carries "oddity" claims (tokens that force the door open or make it swing chaotically on a random interval) and a forced-shut mode.
- API: `DoorPart.new(part: BasePart) -> DoorPart` — captures the closed pivot and outward direction from the parent `Door` model, plus the doorway's `DoorConfig.AnchorName` part as a moving anchor
- API: `DoorPart:_syncAnchor() -> boolean` — rebases the closed pivot, hinge, arm and outward vector off the anchor's current CFrame, so a doorway the server moves (as `HallwayCrush` does) carries its leaf with it instead of the client dragging the leaf back to a stale pivot; a no-op when the anchor has not moved
- API: `DoorPart:IsOpen() -> boolean`
- API: `DoorPart:IsInside(position: Vector3) -> boolean` — is the point behind the door's outward face
- API: `DoorPart:SetOpen(open: boolean, from: Vector3?)` — normal open/close; ignored while oddity claims exist
- API: `DoorPart:SetOddityOpen(token: number, playbackSpeed: number)` — claim the door held open
- API: `DoorPart:SetOddityChaos(token, openSpeed, closeSpeed, intervalMin, intervalMax)` — claim the door flapping randomly
- API: `DoorPart:ClearOddity(token: number)` — drop a claim and re-settle
- API: `DoorPart:SetForced(forced: boolean)` — jam shut and non-collidable, blocking all claims
- API: `DoorPart:Step(deltaTime: number)` — advance the spring or the audio-synced swing and pivot the part
- API: `DoorPart:Destroy()` — restores collision and the closed pivot
- Requires: `Classes.Spring`, `Configs.DoorConfig`, `Services.AudioService` (uses `GetPlaybackBounds`), `Services.MathService`

### Drawer.luau
Spring-driven sliding drawer model. Infers its outward axis from a part whose name contains `DrawerConfig.HandleKeyword`, ignoring parts belonging to tagged drawer items.
- API: `Drawer.new(model: Model) -> Drawer`
- API: `Drawer:IsOpen() -> boolean`
- API: `Drawer:IsMoving() -> boolean`
- API: `Drawer:SetOpen(open: boolean, immediate: boolean?)`
- API: `Drawer:Step(deltaTime: number) -> boolean` — true while still animating
- API: `Drawer:Destroy()` — drops the model reference only
- Tags: reads `DrawerItemConfig.Tag`
- Requires: `Classes.Spring`, `Configs.DrawerConfig`, `Configs.DrawerItemConfig`

### Hole.luau
Client crawl-hole: attaches a `CrawlPrompt`, and on trigger walks the character to the hole, plays the crawl animation, teleports it to the twin hole sharing the same `ID` attribute, and emits the twin's VFX. Puts every active hole on a shared 5 second cooldown and disables player controls for the duration.
- API: `Hole.new(hole: Model) -> Hole` — clones the prompt onto the hole's PrimaryPart
- API: `Hole:Crawl()` — yields through the whole crawl sequence
- API: `Hole:Destroy()`
- Tags: reads `Hole`
- Requires: `Services.TagService` (`GetTaggedOfPredicate`), `Services.AudioService`, `PlayerModule` controls, `ReplicatedStorage.Props.Prompts.CrawlPrompt`

### Interaction.luau
Client look-at interaction system: raycasts from the camera each render step over registered models, highlights the hit target, and draws/animates a key-prompt pill cloned from the `Cursor` gui. Handles keyboard, gamepad and touch input through ContextActionService, and supports targets that ignore occlusion. A fresh `Highlight` is created under `workspace` for each newly selected model and destroyed once its fade reaches zero — no single long-lived Highlight instance is reused across selections.
- API: `Interaction.new() -> Interaction` — binds the render step and builds the prompt UI
- API: `Interaction:Register(model: Model, options: TargetOptions)` — `Prompt` (string or function), `TextWidth`, `CanSelect`, `Reach`, `IgnoreOcclusion`, `OnActivated`
- API: `Interaction:Unregister(model: Model)`
- API: `Interaction:GetSelected() -> Model?`
- API: `Interaction.Selected` — event fired with the newly selected model or nil
- API: `Interaction:Destroy()`
- Requires: `Configs.DrawerConfig` (Targeting/Input/Highlight/UI sections), `PlayerGui.Cursor` UI template

### InventorySlot.luau
One inventory hotbar slot: an ImageButton with a ViewportFrame preview of the tool model, a quantity label and an optional slot number. The preview clones the tool from `ReplicatedStorage.Tools`, strips scripts/effects and frames a camera using ItemShopConfig per-item yaw/pitch/zoom.
- API: `InventorySlot.new(index: number, showNumber: boolean) -> InventorySlot` — builds the (unparented) frame
- API: `InventorySlot:SetTool(toolName: string, quantity: number, icon: string?)` — re-renders the preview only when the tool changed; `icon` is unused
- API: `InventorySlot:SetEmpty()`
- API: `InventorySlot:IsEmpty() -> boolean`
- API: `InventorySlot:SetEquipped(equipped: boolean)`
- API: `InventorySlot:SetDropTarget(active: boolean)`
- API: `InventorySlot:Destroy()`
- Requires: `Configs.InventoryConfig`, `Configs.ItemShopConfig`

### GalleryCard.luau
One tile in the Gallery grid. Clones the complete Studio-authored `GalleryGui.Design.MediaCanvas.Media.Template` frame, then fills its `Card` with a cropped photo or first-frame tape thumbnail, a `TAPE`/`STILL` badge, the capture date, and a green edge while the capture awaits a keep-or-burn choice. Tape tiles use `ImageLabel.ImageContent` rather than one live `VideoFrame` per card.
- API: `GalleryCard.new(template: Frame, parent: Instance, media: any, order: number, onSelect: (any) -> ()) -> GalleryCard`
- API: `GalleryCard:Pose(override: TweenInfo?)` — settle to the hover/press/selected pose
- API: `GalleryCard:SetSelected(selected: boolean)`
- API: `GalleryCard:Deal(delay: number)` — staggered entrance
- API: `GalleryCard:Destroy()`
- Requires: `Configs.CaptureConfig`, `CaptureGalleryService`; expects the authored gallery card template

### KitCard.luau
One kit tile in the inventory or shop grid: clones the GUI's `Template` ImageButton into a layout holder, dresses it with its rarity stroke, rarity ribbon, kit name, status line and dim overlay through `KitVisualService`, renders the kit's showcase item into the tile's ViewportFrame, and owns the hover/press/select/deal motion. Used by both kit pages so the two grids cannot drift apart.
- API: `KitCard.new(template: ImageButton, parent: Instance, kit, order: number, onSelect: (kit) -> ()) -> KitCard`
- API: `KitCard:Pose(override: TweenInfo?)` - re-tween to whatever the current hover/press/selected state implies
- API: `KitCard:SetSelected(selected: boolean)`
- API: `KitCard:SetStatus(text: string, dimmed: boolean, color: Color3?)` - the per-page status line (price, OWNED, EQUIPPED)
- API: `KitCard:Deal(delay: number)` - drop-in entrance used when a page opens
- API: `KitCard:Destroy()`
- Requires: `Configs.KitConfig`, `Services.KitVisualService`

### LocatorMarker.luau
Per-player billboard marker for the player locator: headshot bubble, halo, name plate and distance readout, all tweened between an idle and a focused state, plus a character Highlight. Rebinds itself as the player's character spawns, dies and is removed.
- API: `LocatorMarker.new(player: Player, parent: Instance, onActivated: (Player) -> ()) -> LocatorMarker`
- API: `LocatorMarker:SetFocused(focused: boolean)` — expands/collapses the bubble and plate, plays the hover sound
- API: `LocatorMarker:Pulse(phase: number)` — drives the halo scale while focused
- API: `LocatorMarker:SetAvailable(available: boolean)` — cooldown tint
- API: `LocatorMarker:SetUiScale(scale: number)`
- API: `LocatorMarker:SetDistanceText(text: string)`
- API: `LocatorMarker:Press()` — press-in bounce
- API: `LocatorMarker:Confirm()` — expand-and-fade confirmation
- API: `LocatorMarker:GetAnchor() -> BasePart?` — the adorned root part while shown
- API: `LocatorMarker:Destroy()`
- Requires: `Configs.PlayerLocatorConfig`, `Services.AudioService`

### MapCanvas.luau
A software pixel canvas backing an `EditableImage`. Owns an RGBA `buffer` it composites into with a soft round brush, then pushes only the changed rectangle through `WritePixelsBuffer`. Compositing takes the maximum alpha rather than blending over, which makes repeated drawing of the same ink idempotent and removes seams where separately drawn strokes meet.
- API: `MapCanvas.new(resolution: number) -> MapCanvas` — creates the buffer and the EditableImage
- API: `MapCanvas:Stamp(x, y, radius, color, alpha)` — one antialiased round brush dab
- API: `MapCanvas:Stroke(points: { Vector2 }, widthAt: (number) -> number, color, alpha)` — stamps along a polyline with a width that varies by progress
- API: `MapCanvas:Flush()` — writes the dirty rectangle and clears it
- API: `MapCanvas:Clear()` — zeroes the buffer and writes the whole canvas
- API: `MapCanvas:ResetDirty()`
- API: `MapCanvas:Destroy()`

### MapMarker.luau
One symbol on the discoverable map: an inked disc with a handwriting-font glyph, a spring-driven pop scale, an expanding ping ring and a short glyph flash. Used for landmarks such as computers; a freshly discovered one pops, a restored one simply appears.
- API: `MapMarker.new(parent: GuiObject, kind: string, userId: number?) -> MapMarker` — kind selects the glyph; a `userId` swaps it for that player's circular headshot
- API: `MapMarker:SetPosition(position: UDim2)`
- API: `MapMarker:SetFaded(faded: boolean)` — dims the glyph and disc
- API: `MapMarker:Pop()` — plays the discovery pop, ping ring and flash together
- API: `MapMarker:Destroy()`
- Requires: `Configs.MapConfig`, `Services.GuiBuilderService`, `Classes.Spring`

### MotionTrail.luau
Rolling buffer of a humanoid's recent position, move vector, look vector and jumping flag, trimmed to a duration window. Used to replay or follow a character a few seconds behind.
- API: `MotionTrail.new(humanoid: Humanoid, rootPart: BasePart, duration: number?) -> MotionTrail` — default window 4s
- API: `MotionTrail:Record()` — appends a sample and drops expired ones; skips while dead
- API: `MotionTrail:Latest() -> Sample?`
- API: `MotionTrail:At(delay: number) -> Sample?` — interpolated sample `delay` seconds ago
- API: `MotionTrail:Destroy()`

### NpcAnimator.luau
Replacement for the default Animate script on NPC rigs: disables `Animate`, loads idle/walk/run plus emotes and attacks, and each Heartbeat picks the right track and scales its playback rate to the rig's actual travel speed. Also supports looping override and hold animations by asset id, pausing, and clearing tracks it does not own.
- API: `NpcAnimator.new(model: Model, set: AnimationConfig.AnimationSet?) -> NpcAnimator`
- API: `NpcAnimator:Start()` / `NpcAnimator:Stop()` — connect/disconnect the Heartbeat update
- API: `NpcAnimator:Pause()` / `NpcAnimator:Resume()`
- API: `NpcAnimator:PlayEmote(name: string?) -> boolean` — random emote (optionally from one container), auto-stopped after `MimicConfig.EmoteDuration`
- API: `NpcAnimator:StopEmote()`
- API: `NpcAnimator:PlayAttack() -> boolean` — random attack track
- API: `NpcAnimator:PreloadOverride(assetId: number)`
- API: `NpcAnimator:PlayOverride(assetId: number): AnimationTrack` / `NpcAnimator:StopOverride()` — looping Action-priority override; returns the track so callers can read its length
- API: `NpcAnimator:PlayHold(assetId: number)` / `NpcAnimator:StopHold()` — second looping Action-priority slot
- API: `NpcAnimator:SetMovementSpeed(speed: number)` — drive gait from a value instead of the rig's velocity
- API: `NpcAnimator:SetMovementTrack(trackName: "Walk" | "Run"?)` — force a locomotion track
- API: `NpcAnimator:ClearForeignTracks()` — stops any playing track this animator did not load
- API: `NpcAnimator:Reload()` — reloads locomotion and emote tracks in place
- API: `NpcAnimator:Destroy()`
- Requires: `Configs.AnimationConfig`, `Configs.MimicConfig`, the rig's `Animate` script

### PathfinderMarker.luau
One numbered waypoint marker for the pathfinder debug/authoring tool, cloned from `ReplicatedStorage.Props.Other.PathfinderMarker` and scaled in on placement. Returns nil (with a warning) if the template is missing.
- API: `PathfinderMarker.new(cframe: CFrame, index: number, config, parent: Instance) -> PathfinderMarker?`
- API: `PathfinderMarker:SetShade(alpha: number)` — lerps pad/blade/dot colour between `config.OldColor` and `config.NewColor`
- API: `PathfinderMarker:Pulse()` — brief transparency flash
- API: `PathfinderMarker:Destroy()` — scales and fades out, then destroys after `config.RemoveTime`
- Requires: `Services.TweenProxyService` (`ScaleModel`)

### Race.luau
Runs several functions at once and returns the key of whichever finishes first, cancelling the rest. Yields the calling thread.
- API: `Race.new(functions: { [any]: () -> () }) -> Race`
- API: `Race:Fire() -> any?` — the key of the winner; errors on an empty table
- API: `Race:Cancel()` — abort from outside the racing functions

### RigMotion.luau
Shared base class for procedural rig motions. Handles the `PreAnimation` (undo last frame's offsets) / `PreSimulation` (apply new offsets) pair so subclasses layer their transforms on top of the animator without fighting it.
- API: `RigMotion.extend() -> class` — creates a subclass table
- API: `RigMotion.new(rig: Model, class: any?) -> RigMotion` — sets `self.Rig` and connects `self.Connections`
- API: `RigMotion.FindJoint(rig: Model, partNames: { string }, jointName: string) -> Motor6D | AnimationConstraint | nil` — first matching joint under any named part
- API: `RigMotion:RemoveApplied()` — subclass override; strip the offsets applied last frame
- API: `RigMotion:Update(deltaTime: number)` — subclass override; apply this frame's offsets
- API: `RigMotion:Destroy()` — removes applied offsets and disconnects

### Spin.luau
Rotates an instance about the world Y axis every RenderStepped at the rate given by its `RPS` attribute (revolutions per second), tracking live changes to that attribute.
- API: `Spin.new(instance: Instance) -> Spin` — works with a BasePart or any pivotable instance
- API: `Spin:Destroy()`

### Spring.luau
Plain numeric critically-tunable spring integrated in fixed sub-steps, used by the door and drawer motion. `deltaTime` is capped at 0.1s per `Step`.
- API: `Spring.new(stiffness: number, dampingRatio: number, maxStep: number) -> Spring` — damping is stored as `dampingRatio * 2 * sqrt(stiffness)`
- API: `Spring:Snap(position: number)` — jump to a position and zero the velocity
- API: `Spring:Step(deltaTime: number, clamp: ((position, velocity) -> (number, number))?)` — integrate, optionally clamping each sub-step
- API: fields `Position`, `Velocity`, `Target`, `Stiffness`, `Damping`, `MaxStep` — `Target` is set directly by callers

### StateMachine.luau
Coroutine state machine: each state is a function that runs to completion and returns the next state, while "evaluators" run in parallel and can interrupt the current state. Transitions are gated by a reason table (a reason may only override the states listed for it), and a failed state warns and recovers to the machine's recovery state after 0.5s.
- API: `StateMachine.new(states, reasons, evaluators, initialState: string, ...) -> StateMachine`
- API: `StateMachine:SetStartState(stateId: string, ...)` — only before Start
- API: `StateMachine:AddState(stateId: string, func: StateFunction)` — errors on duplicates
- API: `StateMachine:AddEvaluator(evaluatorId: string, func: EvaluatorFunction)` — starts immediately if already running
- API: `StateMachine:SetState(stateId: string, reasonId: string?, ...)` — interrupt the current state; `"root"` or nil bypasses the reason check
- API: `StateMachine:Start()` — spawns the machine thread and all evaluators
- API: `StateMachine:Stop()` — back to Ready
- API: `StateMachine:Destroy()` — permanent
- API: fields `OnStateChanged: (string) -> ()`, `OnBeforeCancel: () -> ()` — optional hooks assigned by the owner
- Requires: `Classes.Vow`

### ToolBase.luau
Shared base class for every tool on both client and server. Wires Equipped/Unequipped/Activated, guards activation with a busy flag, liveness check and `Config.Cooldown`, pcalls the subclass hooks, and provides a name-and-event messaging channel between the two sides of the same tool.
- API: `ToolBase.extend(className: string) -> class` — makes a subclass
- API: `ToolBase.new(tool: Tool, class: any?) -> ToolBase` — reads `ToolConfigs[tool.Name]` into `self.Config`
- API: `ToolBase:GetPlayer() -> Player?` — from the character or backpack the tool sits in
- API: `ToolBase:IsAlive() -> boolean`
- API: `ToolBase:GetQuantity() -> number` — the tool's `quantity` attribute
- API: `ToolBase:Activate()` — the guarded activation sequence; normally called by the Activated connection
- API: `ToolBase:WaitForMarker(track: AnimationTrack, markerName: string, timeout: number?) -> boolean` — true if the marker fired before the track ended or timed out (default 10s)
- API: `ToolBase:WaitForTrack(track: AnimationTrack, timeout: number?) -> boolean` — waits for `track.Ended`
- API: `ToolBase:PlaySound(soundName: string?, part: BasePart?)` — 3D SFX, no-op on nil
- API: `ToolBase:Fire(eventName: string, ...)` — sends to the opposite side over the shared tool signal
- API: `ToolBase:On(eventName: string, handler: (...any) -> ())` — register a handler for `_Dispatch`
- API: `ToolBase:_Dispatch(eventName: string, ...)` — invoke a registered handler, pcalled
- API: `ToolBase:OnEquipped()` / `:OnUnequipped()` / `:OnActivated()` / `:OnCleanup()` / `:OnDestroy()` — empty subclass hooks
- API: `ToolBase:_BeforeActivate()` / `:_AfterActivate()` — empty hooks around activation
- API: `ToolBase:Destroy()` — fires OnDestroy and disconnects
- Remotes: `Tools/Signal` (fired both directions)
- Requires: `Configs.ToolConfigs`, `Services.AudioService`, `Services.CommunicationService`

### ToolCounter.luau
Bottom-right ScreenGui readout showing a caption and a remaining/total count, or an infinity sign when unlimited.
- API: `ToolCounter.new(caption: string) -> ToolCounter`
- API: `ToolCounter:Set(remaining: number?, total: number?)` — nil remaining shows `∞`
- API: `ToolCounter:Destroy()`
- Requires: `Configs.InventoryConfig`

### Vow.luau
Runs one function on its own thread and lets the caller be resumed early. The function receives a `cancel` closure it can call to hand a result back and suspend itself; the owner can also `Cancel` or `Destroy` from outside. Backs StateMachine's states and evaluators.
- API: `Vow.new(func: (cancel: Cancel, ...any) -> ...any) -> Vow`
- API: `Vow:Fire(...) -> ...any` — yields the caller until the function returns or cancels; re-raises the function's error
- API: `Vow:Cancel(...)` — resume the caller with these values from outside the function
- API: `Vow:Destroy()` — resume the caller and mark the vow dead

### Watch.luau
RigMotion subclass that turns an NPC's neck and waist to look at the local player's head while within `WatchConfig.TrackRange`, clamped and eased. Splits the rotation between neck and waist by config weights, falling back to whichever joint exists.
- API: `Watch.new(rig: Model) -> Watch`
- API: `Watch:Update(deltaTime: number)` — recomputes and applies the look angles
- API: `Watch:RemoveApplied()` — undoes last frame's neck/waist transforms
- Requires: `Classes.RigMotion`, `Configs.WatchConfig`, `Services.MathService`

### Wallstick\ (init.luau, CharacterHelper.luau, GravityCamera.luau, GravityCameraModifier.luau, Replication.luau, RotationSpring.luau, CharacterAnimate\, CharacterSounds\, Signal.luau, Trove.luau, RaycastHelper.luau)
Vendored EgoMoose Rbx-Wallstick (June 2026 upstream): sticks the local player's character to any surface -- walls, ceilings, moving parts -- by simulating a hidden "fake" character in a de-rotated geometry world under `workspace.Wallstick` and CFraming the real character to match every physics step. Uses modern `AlignPosition`/`AlignOrientation` constraints; the upstream's one deprecated call (`FindPartsInRegion3WithIgnoreList`) was replaced with `GetPartBoundsInBox`, `Replication.luau` was adapted to `CommunicationService` remotes instead of TypedRemote, and `Trove`/`RaycastHelper`/`Signal` (stravant goodsignal) are vendored as children. Nothing in StarterPlayer is replaced or installed — everything applies at runtime, client-side, only when wallstick is first enabled: `GravityCamera` monkey-patches the live stock `PlayerModule` with `GravityCameraModifier` (adds gravity up-vector, spin-part, rotation-type and screen-relative look-input control to the camera; guards its camera-plane projection at steep view angles; falls back to a tilt-less camera if patching fails; the patch forces `UserGameSettings.RotationType` to `MovementRelative` only while a Wallstick instance exists — the constructor calls `GravityCamera.setRotationTypeForced(true)` and teardown restores the real rotation type, so first-person/shift-lock character facing on the ground is untouched when not wallsticking), and `CharacterHelper.setMyPerformer` temporarily disables the character's stock `Animate` and the player's stock `RbxCharacterSounds` LocalScripts, driving the real character's animations and sounds from the fake humanoid via the vendored `CharacterAnimate`/`CharacterSounds` packages, then restores the stock scripts when wallstick is disabled. The fake humanoid mirrors the real humanoid's `WalkSpeed` so movement modifiers such as sprint continue to apply while stuck. Its optional `directMovement` mode turns off the hidden Humanoid's competing state solver, pins the rig to its current surface plane before and after physics, and drives planar velocity from held input each step, preventing the Gravity Warper from falling off, bobbing with gravity or catching on cloned ceiling seams while collision still blocks walls. Destroying the controller removes its real-character alignment constraints and restores the original `PlatformStand` and `EvaluateStateMachine` values before returning the humanoid to `GettingUp`. Client-only; other players' stuck characters render through the replication channel: senders stream `part + offset` frames every 0.2s, receiving clients anchor and CFrame the sender's root to follow them, and destroying the controller sends `Replication.sendClear()` so the server drops the sender's frame and every receiving client unanchors the root and hands it back to normal replication (without this, other clients would keep the character pinned at its last stuck position — even across respawns). Drive it through `Services.WallstickService` rather than constructing directly.
- API: `Wallstick.new(options: { parent: Instance, origin: CFrame, retainWorldVelocity: boolean, directMovement: boolean?, camera: { tilt: boolean, spin: boolean } }) -> Wallstick`
- API: `Wallstick:set(part: BasePart, normal: Vector3, teleportCF: CFrame?)` / `:setAndPivot(part, normal, position)` / `:setAndTeleport(part, normal, position)` -- stick to a surface
- API: `Wallstick:getPart() -> BasePart`, `:getNormal(worldSpace: boolean) -> Vector3`, `:getFallDistance() -> number`, `:getMoveDirection() -> Vector3`, `:Destroy()`
- Remotes: `Wallstick/Replicator`, `Wallstick/Sync` (via `Replication.luau`)
- Requires: `Services.CommunicationService`; expects the server `WallstickService` collision groups and streaming foci

### CameraShaker\ (init.luau, CameraShakeInstance.luau, CameraShakePresets.luau)
Vendored third-party camera shake library (Sleitnick's CameraShaker); used through ShakeService — not modified in this project.

## Minigames

### Minigames\MinigameBase.luau
Shared base class every terminal minigame extends: it owns the root frame, theme, run state, tracked connections and heartbeat, and supplies GUI builders (board, status bar, D-pad), input helpers and win/fail plumbing. Subclasses are created with `MinigameBase.extend(id, title, supportsReset)` (which stamps `Id`, `Title`, `SupportsReset` on the class) and must pass their class into `MinigameBase.new(root, api, class)`. The host supplies an `Api` of `{ Complete, Fail?, Theme, Sound? }`; the lifecycle contract a subclass fulfils is `:Start(saved)` (build UI and begin), `:Serialize() -> any?` (resume payload or nil), `:Reset()` (only when `SupportsReset`), plus optional `:IdleMessage()` and `:OnDestroy()` hooks — `:Destroy()` is provided and calls them.
- API: `MinigameBase.extend(id: string, title: string, supportsReset: boolean) -> class` — makes a subclass table with `Id`/`Title`/`SupportsReset`
- API: `MinigameBase.new(root: Frame, api: Api, class: any?) -> self` — sets `Root`, `Api`, `Theme`, `State`, `Completed`, `MessageUntil`, `MessageTime`, `Connections`
- API: `MinigameBase.Directions` — data table mapping WASD/arrow `KeyCode`s to `{x, y}` steps
- API: `MinigameBase:Track(connection: RBXScriptConnection) -> RBXScriptConnection` — store for auto-disconnect on destroy
- API: `MinigameBase:NewFrame(parent: Instance, color: Color3, strokeColor: Color3?, thickness: number?) -> Frame`
- API: `MinigameBase:NewLabel(parent: Instance, text: string, textSize: number) -> TextLabel` — themed font and text color
- API: `MinigameBase:NewButton(parent: Instance, text: string) -> TextButton` — panel fill, primary stroke
- API: `MinigameBase:AddStroke(parent: GuiObject, color: Color3, thickness: number) -> UIStroke`
- API: `MinigameBase:BuildBoardFrame(aspectRatio: number, options: {Position: UDim2?, Size: UDim2?, Clip: boolean?}?) -> Frame` — centred aspect-locked board, also stored as `self.Board`
- API: `MinigameBase:BuildStatusBar(leftName: string, initialMessage: string) -> (TextLabel, TextLabel)` — top bar; right label becomes `self.MessageLabel`
- API: `MinigameBase:BuildDirectionalPad(callback: (x: number, y: number) -> ())` — on-screen WASD pad
- API: `MinigameBase:ConnectDirectionalKeys(callback: (x: number, y: number) -> ())` — WASD/arrow keyboard input
- API: `MinigameBase:ConnectKeys(map: {[Enum.KeyCode]: any}, callback: (value: any) -> ())` — arbitrary key map
- API: `MinigameBase:PlaySound(name: string, pitch: number?)` — routed through `Api.Sound` if present
- API: `MinigameBase:FailRun(reason: string?)` — routed through `Api.Fail` if present
- API: `MinigameBase:Climb(count: number, total: number) -> number` — 0-1 progress ramp, used for rising pitch
- API: `MinigameBase:Say(text: string, color: Color3)` — flash a status message for `MessageTime`
- API: `MinigameBase:StepMessage()` — call per frame; restores `IdleMessage` when the flash expires
- API: `MinigameBase:IdleMessage()` — no-op hook subclasses override
- API: `MinigameBase:StartHeartbeat(callback: (deltaTime: number) -> ())`
- API: `MinigameBase:StopHeartbeat()`
- API: `MinigameBase:ClampedSavedNumber(saved: any, field: string, minimum: number, maximum: number) -> number?` — safe read of a resume field
- API: `MinigameBase:Win()` — marks won, says "BREACHED", stops heartbeat, calls `Api.Complete`
- API: `MinigameBase:OnDestroy()` — no-op hook subclasses override
- API: `MinigameBase:Destroy()` — stops heartbeat, disconnects tracked connections, runs `OnDestroy`, clears `Root`

### Minigames\AimTrainer.luau
Click-the-target trainer: hit 20 ringed targets before missing 3, with each target's lifetime shrinking from 5s to 1.875s as hits climb. Timing out counts as a miss; the third miss wipes the run back to zero hits and reports a failure. Placement retries up to 24 times to keep targets at least 200px from the last one.
- API: `AimTrainer.new(root: Frame, api: Api) -> self`
- API: `AimTrainer:Start(saved: any?)` — builds header/timer bar/target area, restores saved `Hits`, starts the countdown heartbeat
- API: `AimTrainer:Serialize() -> any?` — `{ Hits }`, or nil when finished or at zero
- API: `AimTrainer:Reset()` — zeroes hits and misses, respawns a target
- Requires: `Classes\Minigames\MinigameBase`

### Minigames\Frogger.luau
Frogger on a 13x9 grid: hop from the bottom row to the goal row twice while six lanes of wrapping traffic sweep across. Getting hit resets crossings to zero, plays a splat and reports a failure; two clean crossings win.
- API: `Frogger.new(root: Frame, api: Api) -> self`
- API: `Frogger:Start(saved: any?)` — restores `Crossings`, builds board/lanes/chrome, binds keys and D-pad, starts the traffic heartbeat
- API: `Frogger:Serialize() -> any?` — `{ Crossings }`, or nil at zero
- API: `Frogger:Reset()` — clears crossings, re-phases every lane, returns the frog to start
- API: `Frogger:IdleMessage()` — restores the "REACH THE TOP" prompt
- Requires: `Classes\Minigames\MinigameBase`

### Minigames\Memory.luau
4x4 emoji pair-matching game: flip two cards per move, matched pairs stay lit, and all 8 pairs must be found within 20 moves. Exceeding the move limit reshuffles the board and reports a failure. Saves validate the whole layout (every pair present exactly twice) before being trusted, and a `Generation` counter cancels stale flip-back timers.
- API: `Memory.new(root: Frame, api: Api) -> self`
- API: `Memory:Start(saved: any?)` — builds the header and card grid, restores a validated save or deals a fresh shuffle
- API: `Memory:Serialize() -> any?` — `{ Layout, Matched, FaceUp, Moves }`, or nil when won or untouched
- API: `Memory:Reset()` — reshuffles and clears all progress
- API: `Memory:OnDestroy()` — bumps `Generation` to kill pending flip-backs and drops UI references
- Requires: `Classes\Minigames\MinigameBase`

### Minigames\Minesweeper.luau
8x8 Minesweeper with 10 mines: left-click reveals with flood-fill on empty cells, right-click (or the FLAG toggle) flags, and clearing all 54 safe cells wins. Mines are placed after the first click so that click and its neighbours are always safe; hitting a mine shows the field and auto-resets one second later.
- API: `Minesweeper.new(root: Frame, api: Api) -> self`
- API: `Minesweeper:Start(saved: any?)` — builds header, flag toggle and grid, restores a validated save
- API: `Minesweeper:Serialize() -> any?` — `{ Placed, Flagging, Mines, Revealed, Flags }`, or nil when dead, won, or untouched
- API: `Minesweeper:Reset()` — clears mines/reveals/flags and bumps `Generation` to cancel the pending boom timer
- API: `Minesweeper:OnDestroy()` — bumps `Generation` and drops cell references
- Requires: `Classes\Minigames\MinigameBase`

### Minigames\Simon.luau
Simon says with four pads driven by WASD/arrows or clicks: watch the playback, repeat it, and the sequence grows by one each round until 7 is reached. Three mistakes reseed the sequence to length 1, show a LOCKOUT and report a failure; the highest length reached is what gets saved.
- API: `Simon.new(root: Frame, api: Api) -> self`
- API: `Simon:Start(saved: any?)` — builds pads and status bar, reseeds to the saved length, binds keys, starts the playback heartbeat
- API: `Simon:Serialize() -> any?` — `{ Length }` (best round reached), or nil at zero
- API: `Simon:Reset()` — clears mistakes and best, reseeds to length 1
- API: `Simon:OnDestroy()` — drops pad button references
- Requires: `Classes\Minigames\MinigameBase`

### Minigames\Snake.luau
Snake on a 16x12 grid: eat 15 pellets to win, with the tick interval speeding up from 0.16s toward 0.106s per pellet eaten. Turns are queued (max 2) so fast inputs are not dropped, and reversing into yourself is rejected; hitting a wall or your own body zeroes the score, respawns and reports a failure. Only the best pellet count survives a save.
- API: `Snake.new(root: Frame, api: Api) -> self`
- API: `Snake:Start(saved: any?)` — restores `Best`, builds board and chrome, spawns the snake, binds keys and D-pad, starts the tick heartbeat
- API: `Snake:Serialize() -> any?` — `{ Best }`, or nil at zero
- API: `Snake:Reset()` — banks the score into `Best`, respawns the snake
- API: `Snake:IdleMessage()` — shows the best score, or the "EAT FIFTEEN" prompt
- API: `Snake:OnDestroy()` — drops segment frame references
- Requires: `Classes\Minigames\MinigameBase`

## Tools

### Tools\Ball.luau
Client half of the throwable ball: raycasts through the mouse at Eye-tagged parts, plays the Throw animation while turning the character to face the target, then flies a cloned ball prop toward the Eye's head and tells the server it connected. Consumes one ball per throw and deletes the visible handle when the stack runs out.
- API: `Ball.new(tool: Tool) -> self`
- API: `Ball:OnEquipped()` — loads the Throw animation track
- API: `Ball:OnActivated()` — find target, play throw, consume, launch the projectile
- API: `Ball:OnCleanup()` / `Ball:OnDestroy()` — stops the face-target loop
- Remotes: `Ball/Hit` (fired); `Backpack/Delete` (fired, via `ClientTool:Consume`)
- Tags: reads `Eye` via `TagService:GetTaggedOfAncestor`
- Requires: `Classes\ClientTool`, `TagService`, `ReplicatedStorage.Props.Other` (Ball prop)

### Tools\Camcorder.luau
Client half of the unlimited-use camcorder. Activation asks the server to check the gamepass; on `Allowed` it unequips itself so the camera body stays out of frame, waits a beat, then starts a video capture. The tool stays in its inventory slot but is disabled until the take ends, and any outside attempt to equip it is stowed again. The Studio-authored `StarterGui.CamcorderRecording` panel blinks its red light and offers a touch STOP button, with X or gamepad B as the stop key. Recording also ends at the configured duration or Roblox's 30-second cap. The finished tape is handed to `PhotoDevelopService` for playback and the keep-or-burn prompt.
- API: none beyond the `ClientTool` hooks.
- Remotes: `Tools/Signal` — fires `Record`, listens `Allowed` and `Denied`
- Requires: `Classes.ClientTool`, `Configs.CaptureConfig`, `CaptureGalleryService`, `NotificationService`, `PhotoDevelopService`; expects `StarterGui.CamcorderRecording`

### Tools\Camera.luau
Client half of the tripod Camera: while equipped it keeps a local ForceField-material ghost of the tripod standing wherever the shot would land, updated every render step and hidden when there is no valid spot. On activation it raycasts from the camera through the crosshair for a floor within `Place.Range`, rejects steep surfaces and spots too close to the player, and asks the server to stand the tripod there facing the way the player is looking. The photo itself is taken later by PhotoCaptureService.
- API: `Camera.new(tool: Tool) -> self`
- API: `Camera:OnEquipped()` / `Camera:OnUnequipped()` — build and tear down the placement ghost
- API: `Camera:OnActivated()` — find a floor spot and fire the placement request
- Remotes: `Tools/Signal` (fired, `Place`)
- Requires: `Classes\ClientTool`, `Configs.PhotoConfig`

### Tools\Pathfinder.luau
Drops breadcrumb markers on the floor beneath the player, ray-snapping to ground and refusing to place one within `MinSpacing` of an existing marker (it pulses that marker instead). Markers live in a module-level list shared by every Pathfinder instance, are re-shaded oldest-to-newest and culled past `MaxInWorld`. Shows a `ToolCounter` of uses left unless the player owns the unlimited-Pathfinder perk attribute.
- API: `Pathfinder.new(tool: Tool) -> self`
- API: `Pathfinder:GetUses() -> number` — the tool's `uses` attribute, falling back to `Config.Uses`
- API: `Pathfinder:OnEquipped()` — opens the counter and watches the uses/perk attributes
- API: `Pathfinder:OnUnequipped()` / `Pathfinder:OnDestroy()` — closes the counter and its listeners
- API: `Pathfinder:OnActivated()` — place (or pulse) a marker and predict the new use count
- Remotes: `Tools/Signal` (fired as event `Placed`, via `ToolBase:Fire`)
- Requires: `Classes\ClientTool`, `Classes\PathfinderMarker`, `Classes\ToolCounter`, `Configs\PerkConfig`

### Tools\Player Locator.luau
Thin wrapper that turns `PlayerLocatorService` on while the tool is equipped and off when it is unequipped or destroyed.
- API: `PlayerLocator.new(tool: Tool) -> self`
- API: `PlayerLocator:OnEquipped()` / `PlayerLocator:OnUnequipped()` / `PlayerLocator:OnDestroy()`
- Requires: `Classes\ClientTool`, `PlayerLocatorService`

### Tools\Shovel.luau
Digs an escape hole: raycasts down onto MazeFloor-tagged parts, freezes the player's walk speed, plays the Dig animation while a dummy hole prop tween-grows in place, then consumes a shovel charge and asks the server to create the real hole. Cleanup always removes the dummy, stops the animation and restores walk speed.
- API: `Shovel.new(tool: Tool) -> self`
- API: `Shovel:OnEquipped()` — plays the looping Equip animation
- API: `Shovel:OnUnequipped()` — stops it
- API: `Shovel:OnActivated()` — the dig sequence
- API: `Shovel:OnCleanup()` / `Shovel:OnDestroy()` — destroy dummy, stop dig track, restore walk speed
- Remotes: `Hole/Create` (invoked); `Backpack/Delete` (fired, via `ClientTool:Consume`)
- Tags: reads `MazeFloor` via `TagService:GetTaggedOfAncestor`
- Requires: `Classes\ClientTool`, `TagService`, `TweenProxyService`, `ReplicatedStorage.Props.Other` (DummyHole prop)

### Tools\SpellBook.luau
Minimal tool that just blocks activation until the tool's "Book" animation has started and then finished, so the cast cannot be spammed; the actual spell effect lives elsewhere.
- API: `SpellBook.new(tool: Tool) -> self`
- API: `SpellBook:OnActivated()` — waits for the Book track to start (2s) then end (`Config.MaxCastTime`)
- Requires: `Classes\ClientTool`

### Tools\Visor.luau
Applies a night-vision-style `ColorCorrectionEffect` in Lighting while equipped, tweening in on equip and back to neutral on unequip. The effect instance and an equip counter are module-level, so several Visor instances share one correction and it only fades out when the last one is put away; all tint/brightness/contrast values come from the tool config.
- API: `Visor.new(tool: Tool) -> self`
- API: `Visor:OnEquipped()` / `Visor:OnUnequipped()` / `Visor:OnDestroy()`
- Requires: `Classes\ClientTool`

### Tools\Walkie Talkie.luau
Thin wrapper that reports equip state to `WalkieTalkieService`. Equipping does not power the radio on — that is the player's G press — but transmitting and raising the radio both require it.
- API: `WalkieTalkie.new(tool: Tool) -> self`
- API: `WalkieTalkie:OnEquipped()` / `WalkieTalkie:OnUnequipped()` / `WalkieTalkie:OnDestroy()`
- Requires: `Classes\ClientTool`, `WalkieTalkieService`
