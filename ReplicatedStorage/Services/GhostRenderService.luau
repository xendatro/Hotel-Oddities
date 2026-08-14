--- Client half of the `Ghost`. The server owns where a ghost truly is and publishes the leg it is
--- travelling; every client replays that same leg on its own frames, so the drift is drawn smoothly
--- instead of stepping forward each time a position replicates.
---
--- Nothing here is trusted with anything: the leg is read, never written, and the CFrames set on the
--- rig are local to this machine -- the root is anchored and server-owned, so these writes go no
--- further than the screen. A client that lied to itself about where a ghost is would see a ghost
--- somewhere it is not, which is the whole extent of the damage available.

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

	-- Keep the Ghost visible if Roblox cannot build the client-only avatar model.
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

		-- Animated here rather than left to the server's animator, which is driving the rig this stands
		-- in front of -- and that rig is invisible from the moment this one exists. Nothing on this
		-- machine's copy moves on its own: the humanoid is anchored, never walks and has had its state
		-- machine turned off, so the clip is simply played and left running for as long as the ghost is.
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
	Phase: number,
	Connection: RBXScriptConnection?,
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
		Phase = Bob.NewPhase(),
		Connection = nil,
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
		end
	end)

	-- Off the tag callback: a rig whose root has not replicated yet must not hold up every other
	-- listener behind it. Until it lands the ghost simply renders where the server put it.
	task.spawn(function()
		local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart
		if Ghosts[model] == render then
			render.RootPart = rootPart
		end
	end)

	task.spawn(function()
		local visual = createVisual(model)
		if Ghosts[model] ~= render then return end

		local rootPart = visual:WaitForChild("HumanoidRootPart") :: BasePart
		local head = visual:WaitForChild("Head") :: BasePart
		local neck = head:WaitForChild("Neck") :: Neck
		if Ghosts[model] ~= render then return end

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
	setLocalTransparency(model :: Model, 0)
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
		attachment0.CFrame = part0.CFrame:ToObjectSpace(desiredHeadCFrame * attachment1.CFrame)
			* neck.Transform:Inverse()
	end
end

RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local character = LocalPlayer.Character
	local playerHead = character and character:FindFirstChild("Head") :: BasePart?

	for _, render in Ghosts do
		local rootPart, leg = render.RootPart, render.Leg
		local rootCFrame = nil :: CFrame?
		if rootPart then
			rootCFrame = rootPart.CFrame
		end
		if rootPart and leg then
			rootCFrame = GhostMotion.Evaluate(leg, now) + GhostMotion.Bob(clock, render.Phase)
			rootPart.CFrame = rootCFrame
		end
		if rootCFrame and render.VisualRootPart then
			render.VisualRootPart.CFrame = rootCFrame
		end
		if playerHead then
			aimHeadAt(render, playerHead.Position)
		end
	end
end)

return GhostRenderService
