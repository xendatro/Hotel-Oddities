local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local Bob = require(ReplicatedStorage.Modules.Bob)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local GhostMotion = require(ReplicatedStorage.Modules.GhostMotion)
local TagService = require(ReplicatedStorage.Services.TagService)

local GHOST_TAG = "Ghost"
local GHOST_TRANSPARENCY = 0.5
local HIDDEN_TRANSPARENCY = 1
local MINIMUM_DIRECTION = 1e-3
local RENDER_BIND_NAME = "GhostRender"

local GhostRenderService = {}

if not FLAGS.Enemies then
	return GhostRenderService
end

local LocalPlayer = Players.LocalPlayer

local FriendUserIds: {number}? = nil
local Descriptions: {[number]: HumanoidDescription} = {}

local function loadFriendUserIds(): {number}
	local success, pages = pcall(
		Players.GetFriendsAsync,
		Players,
		LocalPlayer.UserId
	)
	if not success then return {} end

	local userIds = {}
	while true do
		local pageSuccess, page = pcall(pages.GetCurrentPage, pages)
		if not pageSuccess then break end

		for _, friend in page do
			table.insert(userIds, friend.Id)
		end

		if pages.IsFinished then break end
		local advanced = pcall(pages.AdvanceToNextPageAsync, pages)
		if not advanced then break end
	end

	return userIds
end

task.spawn(function()
	FriendUserIds = loadFriendUserIds()
end)

local function getDescription(userId: number): HumanoidDescription?
	local cached = Descriptions[userId]
	if cached then return cached end

	if userId == LocalPlayer.UserId then
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if humanoid then
			local success, description = pcall(humanoid.GetAppliedDescription, humanoid)
			if success then
				Descriptions[userId] = description
				return description
			end
		end
	end

	local success, description = pcall(
		Players.GetHumanoidDescriptionFromUserIdAsync,
		Players,
		userId
	)
	if not success then return nil end

	Descriptions[userId] = description
	return description
end

local function setLocalTransparency(model: Model, transparency: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = transparency
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = transparency
		end
	end
end

local function createVisual(model: Model): Model?
	while FriendUserIds == nil do
		task.wait()
	end

	local userIds = FriendUserIds :: {number}
	local userId = if #userIds > 0 then userIds[math.random(#userIds)] else LocalPlayer.UserId
	local description = getDescription(userId)
	if not description and userId ~= LocalPlayer.UserId then
		description = getDescription(LocalPlayer.UserId)
	end

	local visual: Model?
	if description then
		local success, result = pcall(
			Players.CreateHumanoidModelFromDescriptionAsync,
			Players,
			description,
			Enum.HumanoidRigType.R15,
			Enum.AssetTypeVerification.Always
		)
		if success then
			visual = result
		end
	end

	if not visual then
		visual = model:Clone()
		visual:RemoveTag(GHOST_TAG)
	end
	for _, child in visual:GetChildren() do
		if child:IsA("Accessory") then
			child:Destroy()
		end
	end

	visual.Name = `{model.Name}ClientVisual`
	visual:PivotTo(model:GetPivot())
	visual.Parent = model.Parent

	local humanoid = visual:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.AutoRotate = false

		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{AnimationConfig.Sets.Ghost.Idle}`
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Core
		track.Looped = true
		track:Play()
	end

	local animate = visual:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Disabled = true
	end

	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = GHOST_TRANSPARENCY
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = GHOST_TRANSPARENCY
		end
	end

	local rootPart = visual:WaitForChild("HumanoidRootPart") :: BasePart
	rootPart.Anchored = true
	return visual
end

type Neck = Motor6D | AnimationConstraint

type Render = {
	RootPart: BasePart?,
	VisualModel: Model?,
	VisualRootPart: BasePart?,
	VisualHead: BasePart?,
	VisualNeck: Neck?,
	Leg: GhostMotion.Leg?,
	FadeStartedAt: number?,
	Phase: number,
	Connection: RBXScriptConnection?,
	RootConnection: RBXScriptConnection?,
	TransparencyConnection: RBXScriptConnection?,
	VisualTransparencyConnection: RBXScriptConnection?,
}

local Ghosts: { [Model]: Render } = {}

local function track(model: Model): Render
	local render: Render = {
		RootPart = nil,
		VisualModel = nil,
		VisualRootPart = nil,
		VisualHead = nil,
		VisualNeck = nil,
		Leg = GhostMotion.Read(model),
		FadeStartedAt = GhostMotion.ReadFade(model),
		Phase = Bob.NewPhase(),
		Connection = nil,
		RootConnection = nil,
		TransparencyConnection = nil,
		VisualTransparencyConnection = nil,
	}
	Ghosts[model] = render
	setLocalTransparency(model, GHOST_TRANSPARENCY)
	render.TransparencyConnection = model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = if render.VisualModel
				then HIDDEN_TRANSPARENCY
				else GHOST_TRANSPARENCY
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = if render.VisualModel
				then HIDDEN_TRANSPARENCY
				else GHOST_TRANSPARENCY
		end
	end)

	render.Connection = model.AttributeChanged:Connect(function(attribute: string)
		if attribute == GhostMotion.LegAttribute then
			render.Leg = GhostMotion.Read(model)
		elseif attribute == GhostMotion.FadeAttribute then
			render.FadeStartedAt = GhostMotion.ReadFade(model)
		end
	end)

	local existingRoot = model:FindFirstChild("HumanoidRootPart")
	if existingRoot and existingRoot:IsA("BasePart") then
		render.RootPart = existingRoot
	else
		render.RootConnection = model.ChildAdded:Connect(function(child: Instance)
			if child.Name ~= "HumanoidRootPart" or not child:IsA("BasePart") then return end
			local connection = render.RootConnection
			if connection then
				connection:Disconnect()
			end
			render.RootConnection = nil
			if Ghosts[model] == render then
				render.RootPart = child
			end
		end)
	end

	task.spawn(function()
		local visual = createVisual(model)
		if Ghosts[model] ~= render then
			visual:Destroy()
			return
		end

		local rootPart = visual:WaitForChild("HumanoidRootPart") :: BasePart
		local head = visual:WaitForChild("Head") :: BasePart
		local neck = head:WaitForChild("Neck") :: Neck
		if Ghosts[model] ~= render then
			visual:Destroy()
			return
		end

		render.VisualModel = visual
		render.VisualRootPart = rootPart
		render.VisualHead = head
		render.VisualNeck = neck
		render.VisualTransparencyConnection = visual.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = GHOST_TRANSPARENCY
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				descendant.Transparency = GHOST_TRANSPARENCY
			end
		end)
		setLocalTransparency(model, HIDDEN_TRANSPARENCY)
	end)

	return render
end

TagService:Listen(GHOST_TAG, track, function(model: Instance, render: Render)
	local connection = render.Connection :: RBXScriptConnection
	connection:Disconnect()
	local rootConnection = render.RootConnection
	if rootConnection then
		rootConnection:Disconnect()
	end
	local transparencyConnection = render.TransparencyConnection
	if transparencyConnection then
		transparencyConnection:Disconnect()
	end
	local visualTransparencyConnection = render.VisualTransparencyConnection
	if visualTransparencyConnection then
		visualTransparencyConnection:Disconnect()
	end
	if render.VisualModel then
		render.VisualModel:Destroy()
	end
	Ghosts[model :: Model] = nil
end, workspace)

local function aimHeadAt(render: Render, targetPosition: Vector3)
	local head, neck = render.VisualHead, render.VisualNeck
	if not head or not neck then return end

	local direction = targetPosition - head.Position
	if direction.Magnitude < MINIMUM_DIRECTION then return end

	local desiredHeadCFrame = CFrame.lookAt(head.Position, targetPosition, Vector3.yAxis)
	if neck:IsA("Motor6D") then
		local part0 = neck.Part0 :: BasePart
		neck.Transform = neck.C0:Inverse()
			* part0.CFrame:ToObjectSpace(desiredHeadCFrame)
			* neck.C1
	else
		local attachment0 = neck.Attachment0
		local attachment1 = neck.Attachment1
		local part0 = attachment0.Parent :: BasePart
		neck.Transform = (part0.CFrame * attachment0.CFrame):ToObjectSpace(
			desiredHeadCFrame * attachment1.CFrame
		)
	end
end

RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local character = LocalPlayer.Character
	local playerHead = character and character:FindFirstChild("Head") :: BasePart?

	for model, render in Ghosts do
		local rootPart, leg = render.RootPart, render.Leg
		local rootCFrame = if leg
			then GhostMotion.Evaluate(leg, now) + GhostMotion.Bob(clock, render.Phase)
			else rootPart and rootPart.CFrame
		if rootCFrame then
			if rootPart then
				rootPart.CFrame = rootCFrame
			end
			if render.VisualRootPart then
				render.VisualRootPart.CFrame = rootCFrame
			end
		end
		if playerHead then
			aimHeadAt(render, playerHead.Position)
		end

		local fadeStartedAt = render.FadeStartedAt
		if fadeStartedAt then
			local alpha = GhostMotion.FadeAlpha(fadeStartedAt, now)
			setLocalTransparency(
				render.VisualModel or model,
				GHOST_TRANSPARENCY + (HIDDEN_TRANSPARENCY - GHOST_TRANSPARENCY) * alpha
			)
		end
	end
end)

return GhostRenderService
