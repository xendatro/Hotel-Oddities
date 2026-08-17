local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)

--- First-person viewmodel: a camera-locked copy of the equipped tool (plus a simple sleeve arm)
--- that the local player sees instead of the real held one. The real tool is hidden with
--- `LocalTransparencyModifier`, which never replicates -- other players keep seeing the genuine
--- tool in the character's hand, animations and all.
---
--- The rig steps down during the limb reveal: while a tool's activation animation is showing the
--- player their own arms (ClientTool:RevealLimbs), the real tool comes back and the viewmodel
--- hides, so the swing the reveal exists to show is the real one. That state is read off the
--- limbs' LocalTransparencyModifier rather than asked of ClientTool, so neither file owns the
--- other; this service's render bind runs after the reveal's, which is what makes the read safe.
local ViewmodelService = {}

if not RunService:IsClient() then
	return ViewmodelService
end

local BIND_NAME = "ViewmodelStep"

local player = Players.LocalPlayer

local currentTool: Tool? = nil
local rig: Model? = nil
local rigCenterOffset = Vector3.zero
local rigRadius = 0.5
local hiddenParts: { BasePart } = {}
local swayCFrame = CFrame.identity
local lastCameraCFrame: CFrame? = nil
local bobClock = 0
-- Fades the walk bob in and out instead of snapping it on at a speed threshold.
local bobWeight = 0

--- Mirrors ClientTool's first-person test: the engine's own decision, which does not wobble when
--- an animation moves the head.
local function isFirstPerson(character: Model): boolean
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then return true end

	local head = character:FindFirstChild("Head")
	return head ~= nil and head:IsA("BasePart") and head.LocalTransparencyModifier > 0.5
end

--- Whether ClientTool's limb reveal is currently showing the real arms. Its render bind has
--- already run this frame, so a translucent-but-visible hand can only mean a reveal in progress.
local function isRevealing(character: Model): boolean
	local hand = character:FindFirstChild("RightHand")
	return hand ~= nil and hand:IsA("BasePart") and hand.LocalTransparencyModifier < 0.9
end

--- Hiding the real tool ---------------------------------------------------------------------------

local function setRealToolHidden(hidden: boolean)
	for _, part in hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

--- The rig -----------------------------------------------------------------------------------------

local function destroyRig()
	if rig then
		rig:Destroy()
		rig = nil
	end
end

local function buildRig(tool: Tool)
	destroyRig()

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end

	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local clone = tool:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") or descendant:IsA("AudioEmitter") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
			descendant.LocalTransparencyModifier = 0
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire") or descendant:IsA("Light") then
			-- The hidden real tool keeps emitting light and effects; a second source would double up.
			descendant.Enabled = false
		end
	end
	clone.Parent = model
	-- Shrink before the sleeve is added, so the arm keeps its authored thickness.
	model.WorldPivot = handle:GetPivot()
	model:ScaleTo(ViewmodelConfig.Scale)

	local armConfig = ViewmodelConfig.Arm
	if armConfig.Enabled then
		local arm = Instance.new("Part")
		arm.Name = "Sleeve"
		arm.Size = armConfig.Size
		arm.Anchored = true
		arm.CanCollide = false
		arm.CanTouch = false
		arm.CanQuery = false
		arm.CastShadow = false
		arm.Material = Enum.Material.SmoothPlastic

		local character = player.Character
		local realArm = character and character:FindFirstChild("RightUpperArm")
		arm.Color = (realArm and realArm:IsA("BasePart")) and realArm.Color or Color3.fromRGB(204, 158, 116)
		arm.Parent = model
	end

	-- Pivot stays at the handle so one PivotTo a frame carries every part with its offsets intact.
	model.Parent = workspace.CurrentCamera
	rig = model

	-- Tools differ wildly in size and in where their Handle sits inside the model (the Player
	-- Locator's is at its base), so placement anchors the model's *bounding centre* and scales the
	-- offset by its size instead of trusting the handle. Both measured once here, in handle space,
	-- after the shrink so they describe what is actually drawn.
	local sleeve = model:FindFirstChild("Sleeve")
	if sleeve then sleeve.Parent = nil end
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	if sleeve then sleeve.Parent = model end
	local cloneHandle = clone:FindFirstChild("Handle") :: BasePart
	rigCenterOffset = cloneHandle:GetPivot():ToObjectSpace(boundsCFrame).Position
	rigRadius = boundsSize.Magnitude / 2
end

--- Per-frame step ----------------------------------------------------------------------------------

local function step(deltaTime: number)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")

	-- Equip changes rebuild the rig and the hidden-part list.
	if tool ~= currentTool then
		setRealToolHidden(false)
		hiddenParts = {}
		currentTool = tool
		destroyRig()

		if tool then
			for _, descendant in tool:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(hiddenParts, descendant)
				end
			end
			buildRig(tool)
		end
	end

	if not character or not tool or not rig then
		if not tool then
			swayCFrame = CFrame.identity
			lastCameraCFrame = nil
		end
		return
	end

	local firstPerson = isFirstPerson(character)
	local revealing = firstPerson and isRevealing(character)
	local showViewmodel = firstPerson and not revealing

	setRealToolHidden(showViewmodel)
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = showViewmodel and 0 or 1
		end
	end
	if not showViewmodel then
		lastCameraCFrame = nil
		return
	end

	local camera = workspace.CurrentCamera
	if rig.Parent ~= camera then
		rig.Parent = camera
	end

	-- Sway: the rig chases the camera's turning instead of matching it instantly. Yaw only -- pitch
	-- lag made the whole rig (arm included) visibly rotate whenever the player looked up or down,
	-- and the positional delta would push the tool through the near clip while walking.
	-- Exponential smoothing keeps the catch-up identical at any frame rate.
	local camCFrame = camera.CFrame
	if lastCameraCFrame then
		local delta = camCFrame:ToObjectSpace(lastCameraCFrame).Rotation
		local _, deltaYaw = delta:ToEulerAnglesYXZ()
		local target = CFrame.Angles(0, deltaYaw * ViewmodelConfig.SwayAmount, 0)
		swayCFrame = swayCFrame:Lerp(target, 1 - math.exp(-deltaTime * ViewmodelConfig.SwaySpeed))
	end
	lastCameraCFrame = camCFrame

	-- Bob: a light figure-eight whose strength fades in with movement and back out at rest,
	-- rather than cutting on and off at a speed threshold.
	local root = character:FindFirstChild("HumanoidRootPart")
	local speed = (root and root:IsA("BasePart")) and root.AssemblyLinearVelocity.Magnitude or 0
	local targetWeight = math.clamp(speed / 8, 0, 1)
	bobWeight += (targetWeight - bobWeight) * (1 - math.exp(-deltaTime * 6))
	local bob = CFrame.identity
	if bobWeight > 0.01 then
		bobClock += deltaTime * ViewmodelConfig.BobSpeed
		bob = CFrame.new(
			math.sin(bobClock) * ViewmodelConfig.BobAmount * bobWeight,
			math.abs(math.cos(bobClock)) * ViewmodelConfig.BobAmount * bobWeight,
			0
		)
	end

	-- Anchor point for the tool's bounding centre: lower-right of the view, pushed further out the
	-- bigger the tool is, so a paper ball and the Player Locator both land readable and unobtrusive.
	local base = camCFrame * swayCFrame * bob
	local fit = ViewmodelConfig.Fit
	local override = ViewmodelConfig.Overrides[tool.Name]
	local anchor = (override and override.Anchor)
		or Vector3.new(
			fit.Base.X + rigRadius * fit.PerStud.X,
			fit.Base.Y - rigRadius * fit.PerStud.Y,
			fit.Base.Z - rigRadius * fit.PerStud.Z
		)
	local centerTarget = (base * CFrame.new(anchor)).Position

	-- The engine holds tools as Handle = grip attachment * Grip:Inverse(); keeping that rotation
	-- preserves each tool's authored held orientation, and only the position is re-anchored.
	-- A per-tool Rotate corrects grips that read badly this close to the lens.
	local rotation = (base * ViewmodelConfig.HandOffset * tool.Grip:Inverse()
		* ((override and override.Rotate) or CFrame.identity)).Rotation

	-- AnchorAt = "Handle" grips the tool by its Handle part instead of its bounding centre --
	-- right for anything carried by an actual handle, like the medkit case.
	local gripOffset = if override and override.AnchorAt == "Handle" then Vector3.zero else rigCenterOffset
	local handlePosition = centerTarget - rotation:VectorToWorldSpace(gripOffset)
	rig:PivotTo(CFrame.new(handlePosition) * rotation)

	local sleeve = rig:FindFirstChild("Sleeve")
	if sleeve and sleeve:IsA("BasePart") then
		-- From a shoulder just off the lower-right screen edge toward the tool, like a held arm.
		-- Rolled against the CAMERA's up, not the world's: with world up, pitching the view spun
		-- the sleeve around its own axis on screen.
		local shoulder = (base * ViewmodelConfig.Arm.Shoulder).Position
		local mid = shoulder:Lerp(centerTarget, 0.45)
		sleeve.CFrame = CFrame.lookAt(mid, centerTarget, base.UpVector)
	end
end

-- After the camera pass and after ClientTool's reveal bind (Camera + 1), so both the engine's
-- first-person transparency and the reveal's are already written when this frame is judged.
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, step)

return ViewmodelService
