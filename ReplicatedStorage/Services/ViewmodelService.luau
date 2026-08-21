local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)

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
local bobWeight = 0

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
end

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
			descendant.Enabled = false
		end
	end
	clone.Parent = model
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

	model.Parent = workspace.CurrentCamera
	rig = model

	local sleeve = model:FindFirstChild("Sleeve")
	if sleeve then sleeve.Parent = nil end
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	if sleeve then sleeve.Parent = model end
	local cloneHandle = clone:FindFirstChild("Handle") :: BasePart
	rigCenterOffset = cloneHandle:GetPivot():ToObjectSpace(boundsCFrame).Position
	rigRadius = boundsSize.Magnitude / 2
end

local function step(deltaTime: number)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")

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

	local camCFrame = camera.CFrame
	if lastCameraCFrame then
		local delta = camCFrame:ToObjectSpace(lastCameraCFrame).Rotation
		local _, deltaYaw = delta:ToEulerAnglesYXZ()
		local target = CFrame.Angles(0, deltaYaw * ViewmodelConfig.SwayAmount, 0)
		swayCFrame = swayCFrame:Lerp(target, 1 - math.exp(-deltaTime * ViewmodelConfig.SwaySpeed))
	end
	lastCameraCFrame = camCFrame

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

	local rotation = (base * ViewmodelConfig.HandOffset * tool.Grip:Inverse()
		* ((override and override.Rotate) or CFrame.identity)).Rotation

	local gripOffset = if override and override.AnchorAt == "Handle" then Vector3.zero else rigCenterOffset
	local handlePosition = centerTarget - rotation:VectorToWorldSpace(gripOffset)
	rig:PivotTo(CFrame.new(handlePosition) * rotation)

	local sleeve = rig:FindFirstChild("Sleeve")
	if sleeve and sleeve:IsA("BasePart") then
		local shoulder = (base * ViewmodelConfig.Arm.Shoulder).Position
		local mid = shoulder:Lerp(centerTarget, 0.45)
		sleeve.CFrame = CFrame.lookAt(mid, centerTarget, base.UpVector)
	end
end

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, step)

return ViewmodelService
