local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local MathService = require(ReplicatedStorage.Services.MathService)
local SurfaceCursorService = require(ReplicatedStorage.Services.SurfaceCursorService)

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
local rigParts: { BasePart } = {}
local rigHandle: BasePart? = nil
local lastShowViewmodel: boolean? = nil
local hiddenParts: { BasePart } = {}
local hiddenGuis: { SurfaceGui } = {}
local swayCFrame = CFrame.identity
local lastCameraCFrame: CFrame? = nil
local bobClock = 0
local bobWeight = 0
local currentPose: string? = nil
local poseOverrideActive = false
local poseOverrideName: string? = nil
local poseAnchor: Vector3? = nil
local poseArmAnchor: Vector3? = nil
local poseRotate: CFrame? = nil

local function isFirstPerson(character: Model): boolean
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then return true end

	local head = character:FindFirstChild("Head")
	return head ~= nil and head:IsA("BasePart") and head.LocalTransparencyModifier > 0.5
end

local function isRevealing(character: Model): boolean
	local hand = character:FindFirstChild("RightHand")
	return hand ~= nil and hand:IsA("BasePart") and hand.LocalTransparencyModifier < 0.9
end

local function setRealToolHidden(hidden: boolean)
	for _, part in hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
	for _, gui in hiddenGuis do
		if gui.Parent then
			gui.Enabled = not hidden
		end
	end
end

local function destroyRig()
	if rig then
		rig:Destroy()
		rig = nil
	end
	rigHandle = nil
	table.clear(rigParts)
	lastShowViewmodel = nil
end

local function seatJoints(root: BasePart, clone: Instance)
	local joints: { [BasePart]: { JointInstance } } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("JointInstance") then
			local part0 = descendant.Part0
			if part0 and descendant.Part1 then
				local list = joints[part0]
				if not list then
					list = {}
					joints[part0] = list
				end
				table.insert(list, descendant)
			end
		end
	end

	local queue = { root }
	local seated = { [root] = true }
	local index = 1
	while index <= #queue do
		local part = queue[index]
		index += 1
		for _, joint in joints[part] or {} do
			local child = joint.Part1 :: BasePart
			if not seated[child] then
				seated[child] = true
				child.CFrame = part.CFrame * joint.C0 * joint.C1:Inverse()
				table.insert(queue, child)
			end
		end
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
			table.insert(rigParts, descendant)
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire") or descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
	clone.Parent = model

	local cloneHandle = clone:FindFirstChild("Handle") :: BasePart
	seatJoints(cloneHandle, clone)
	model.WorldPivot = cloneHandle:GetPivot()

	local override = ViewmodelConfig.Overrides[tool.Name]
	model:ScaleTo(override and override.Scale or ViewmodelConfig.Scale)

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
		table.insert(rigParts, arm)
	end

	model.Parent = workspace.CurrentCamera
	rig = model

	local sleeve = model:FindFirstChild("Sleeve")
	if sleeve then sleeve.Parent = nil end
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	if sleeve then sleeve.Parent = model end
	rigHandle = cloneHandle
	rigCenterOffset = cloneHandle:GetPivot():ToObjectSpace(boundsCFrame).Position
	rigRadius = boundsSize.Magnitude / 2
end

local function solveFraming(framing: any, base: CFrame): (Vector3?, CFrame?)
	local model = rig
	local handle = rigHandle
	local tool = currentTool
	local camera = workspace.CurrentCamera
	if not model or not handle or not handle.Parent or not tool or not camera then
		return nil, nil
	end

	local part = model:FindFirstChild(framing.Part, true)
	if not part or not part:IsA("BasePart") then return nil, nil end

	local face = framing.Face or Enum.NormalId.Front
	local basis = SurfaceCursorService:GetFaceBasis(face)
	local offset = Vector3.zero
	local size = SurfaceCursorService:GetFaceSize(part, face)

	local gui = part:FindFirstChildOfClass("SurfaceGui")
	local element = if gui and framing.Element then gui:FindFirstChild(framing.Element, true) else nil
	if gui and element and element:IsA("GuiObject") then
		offset, size = SurfaceCursorService:GetElementFrame(part, face, element, gui.AbsoluteSize)
	end
	if size.Y <= 0 then return nil, nil end

	local coverage = math.clamp(framing.Coverage or 0.5, 0.05, 1)
	local distance = size.Y / (2 * coverage * math.tan(math.rad(camera.FieldOfView) / 2))

	local view = (base * (framing.Rotate or CFrame.identity)).Rotation
	local localFrame = CFrame.fromMatrix(
		Vector3.zero,
		basis.Up:Cross(basis.Normal),
		basis.Up,
		basis.Normal
	)
	local partRotation = view * localFrame:Inverse()

	local centre = (base * CFrame.new(0, 0, -distance)).Position
	local partCFrame = CFrame.new(centre) * partRotation * CFrame.new(-offset)
	local handleCFrame = partCFrame * handle.CFrame:ToObjectSpace(part.CFrame):Inverse()

	local anchor = base:PointToObjectSpace(handleCFrame.Position)
	local rotate = (base * ViewmodelConfig.HandOffset * tool.Grip:Inverse()):Inverse()
		* handleCFrame.Rotation
	return anchor, rotate.Rotation
end

local function step(deltaTime: number)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")

	if tool ~= currentTool then
		setRealToolHidden(false)
		hiddenParts = {}
		hiddenGuis = {}
		currentTool = tool
		poseAnchor = nil
		poseArmAnchor = nil
		poseRotate = nil
		destroyRig()

		if tool then
			for _, descendant in tool:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(hiddenParts, descendant)
				elseif descendant:IsA("SurfaceGui") then
					table.insert(hiddenGuis, descendant)
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
	if showViewmodel ~= lastShowViewmodel then
		lastShowViewmodel = showViewmodel
		for _, part in rigParts do
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

	local camCFrame = camera.CFrame
	if lastCameraCFrame then
		local delta = camCFrame:ToObjectSpace(lastCameraCFrame).Rotation
		local _, deltaYaw = delta:ToEulerAnglesYXZ()
		local target = CFrame.Angles(0, deltaYaw * ViewmodelConfig.SwayAmount, 0)
		swayCFrame = swayCFrame:Lerp(target, MathService.ExpAlpha(ViewmodelConfig.SwaySpeed, deltaTime))
	end
	lastCameraCFrame = camCFrame

	local root = character:FindFirstChild("HumanoidRootPart")
	local speed = (root and root:IsA("BasePart")) and root.AssemblyLinearVelocity.Magnitude or 0
	local targetWeight = math.clamp(speed / 8, 0, 1)
	bobWeight += (targetWeight - bobWeight) * MathService.ExpAlpha(6, deltaTime)
	local bob = CFrame.identity
	if bobWeight > 0.01 then
		bobClock += deltaTime * ViewmodelConfig.BobSpeed
		bob = CFrame.new(
			math.sin(bobClock) * ViewmodelConfig.BobAmount * bobWeight,
			math.abs(math.cos(bobClock)) * ViewmodelConfig.BobAmount * bobWeight,
			0
		)
	end

	local base = camCFrame * swayCFrame * bob
	local fit = ViewmodelConfig.Fit
	local override = ViewmodelConfig.Overrides[tool.Name]
	local anchor = (override and override.Anchor)
		or Vector3.new(
			fit.Base.X + rigRadius * fit.PerStud.X,
			fit.Base.Y - rigRadius * fit.PerStud.Y,
			fit.Base.Z - rigRadius * fit.PerStud.Z
		)
	local armAnchor = (override and override.ArmAnchor) or anchor
	local rotate = (override and override.Rotate) or CFrame.identity

	local activePose = if poseOverrideActive then poseOverrideName else currentPose
	local pose = override and override.Poses and activePose and override.Poses[activePose]
	if pose then
		local framedAnchor, framedRotate = nil, nil
		if pose.Framing then
			framedAnchor, framedRotate = solveFraming(pose.Framing, base)
		end

		if framedAnchor and framedRotate then
			anchor = framedAnchor
			rotate = framedRotate
			armAnchor = framedAnchor + (pose.ArmAnchorOffset or Vector3.zero)
		else
			anchor = pose.Anchor or (anchor + (pose.AnchorOffset or Vector3.zero))
			rotate = pose.Rotate or (rotate * (pose.RotateOffset or CFrame.identity))
			armAnchor = pose.ArmAnchor or (armAnchor + (pose.ArmAnchorOffset or Vector3.zero))
		end
	end

	local poseAlpha = MathService.ExpAlpha((override and override.PoseSpeed) or 10, deltaTime)
	poseAnchor = if poseAnchor then poseAnchor:Lerp(anchor, poseAlpha) else anchor
	poseArmAnchor = if poseArmAnchor then poseArmAnchor:Lerp(armAnchor, poseAlpha) else armAnchor
	poseRotate = if poseRotate then poseRotate:Lerp(rotate, poseAlpha) else rotate

	local centerTarget = (base * CFrame.new(poseAnchor)).Position
	local armTarget = (base * CFrame.new(poseArmAnchor)).Position

	local rotation = (base * ViewmodelConfig.HandOffset * tool.Grip:Inverse() * poseRotate).Rotation

	local gripOffset = if override and override.AnchorAt == "Handle" then Vector3.zero else rigCenterOffset
	local handlePosition = centerTarget - rotation:VectorToWorldSpace(gripOffset)
	rig:PivotTo(CFrame.new(handlePosition) * rotation)

	local sleeve = rig:FindFirstChild("Sleeve")
	if sleeve and sleeve:IsA("BasePart") then
		local shoulder = (base * ViewmodelConfig.Arm.Shoulder).Position
		local mid = shoulder:Lerp(armTarget, 0.45)
		sleeve.CFrame = CFrame.lookAt(mid, armTarget, base.UpVector)
	end
end

function ViewmodelService:SetPose(pose: string?)
	currentPose = pose
end

function ViewmodelService:GetDefaultAnchor(): Vector3?
	if not currentTool or not rig then return nil end
	local fit = ViewmodelConfig.Fit
	return Vector3.new(
		fit.Base.X + rigRadius * fit.PerStud.X,
		fit.Base.Y - rigRadius * fit.PerStud.Y,
		fit.Base.Z - rigRadius * fit.PerStud.Z
	)
end

function ViewmodelService:GetTool(): Tool?
	return currentTool
end

function ViewmodelService:GetPose(): string?
	return if poseOverrideActive then poseOverrideName else currentPose
end

function ViewmodelService:SetPoseOverride(active: boolean, pose: string?)
	poseOverrideActive = active
	poseOverrideName = pose
end

function ViewmodelService:GetRig(): Model?
	return rig
end

function ViewmodelService:Refresh()
	if currentTool then
		buildRig(currentTool)
	end
end

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, step)

return ViewmodelService
