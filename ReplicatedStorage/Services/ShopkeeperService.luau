local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopkeeperService = {}

if not RunService:IsClient() then
	return ShopkeeperService
end

local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local ShopkeeperConfig = require(ReplicatedStorage.Configs.ShopkeeperConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local TARGETING = ShopkeeperConfig.Targeting
local HIGHLIGHT = ShopkeeperConfig.Highlight
local PAGE_ATTRIBUTE = ShopkeeperConfig.PageAttribute
local FOCUS_JOB = "ShopkeeperFocus"
local OPEN_COOLDOWN = 0.15
local HIGHLIGHT_FADE_SPEED = 16

local player = Players.LocalPlayer

type State = {
	PageId: string,
	AttributeConnection: RBXScriptConnection,
	DescendantConnection: RBXScriptConnection,
	SmileTrack: AnimationTrack?,
}

local States: { [Model]: State } = {}
local focused: Model? = nil
local highlightAlpha = 0
local lastOpen = 0

local smileAnimation = Instance.new("Animation")
smileAnimation.AnimationId = `rbxassetid://{ShopkeeperConfig.SmileAnimationId}`

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

local highlight = Instance.new("Highlight")
highlight.Name = "ShopkeeperHighlight"
highlight.FillColor = HIGHLIGHT.FillColor
highlight.OutlineColor = HIGHLIGHT.OutlineColor
highlight.DepthMode = HIGHLIGHT.DepthMode
highlight.FillTransparency = 1
highlight.OutlineTransparency = 1
highlight.Enabled = false
highlight.Adornee = nil
highlight.Parent = workspace

local function refreshRaycastFilter()
	local models = {}
	for model in States do
		table.insert(models, model)
	end
	raycastParams.FilterDescendantsInstances = models
end

local function resetHighlight()
	focused = nil
	highlightAlpha = 0
	highlight.Enabled = false
	highlight.Adornee = nil
	if highlight.Parent ~= workspace then
		highlight.Parent = workspace
	end
end

local function ensureHighlight()
	if highlight.Parent ~= workspace then
		highlight.Parent = workspace
	end
	if highlight.Adornee and not highlight.Adornee:IsDescendantOf(workspace) then
		highlight.Adornee = nil
		focused = nil
		highlightAlpha = 0
	end
end

local function startSmile(model: Model, state: State)
	if state.SmileTrack then return end
	if not model:FindFirstChild("FaceControls", true) then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	local ok, result = pcall(function()
		return animator:LoadAnimation(smileAnimation)
	end)
	if not ok then return end

	local track = result :: AnimationTrack
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0)
	state.SmileTrack = track
end

local function register(instance: Instance): State?
	if not instance:IsA("Model") then return nil end

	local model = instance :: Model
	local pageId = model:GetAttribute(PAGE_ATTRIBUTE)
	local state: State = {
		PageId = if type(pageId) == "string" then pageId else "",
		AttributeConnection = nil :: any,
		DescendantConnection = nil :: any,
		SmileTrack = nil,
	}

	state.AttributeConnection = model:GetAttributeChangedSignal(PAGE_ATTRIBUTE):Connect(function()
		local currentPageId = model:GetAttribute(PAGE_ATTRIBUTE)
		state.PageId = if type(currentPageId) == "string" then currentPageId else ""
	end)
	state.DescendantConnection = model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant.Name == "FaceControls" or descendant.Name == "Animator" then
			startSmile(model, state)
		end
	end)

	States[model] = state
	refreshRaycastFilter()
	startSmile(model, state)
	return state
end

local function unregister(model: Instance, state: State?)
	if not model:IsA("Model") then return end
	States[model] = nil
	refreshRaycastFilter()

	if state then
		if state.SmileTrack then
			state.SmileTrack:Stop(0)
			state.SmileTrack:Destroy()
		end
		state.AttributeConnection:Disconnect()
		state.DescendantConnection:Disconnect()
	end
	if focused == model then
		focused = nil
	end
end

local function alive(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then character else nil
end

local function shopkeeperOf(instance: Instance): Model?
	while instance and instance ~= workspace do
		if instance:IsA("Model") and States[instance] then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

local function findFocus(): Model?
	local camera = workspace.CurrentCamera
	local character = alive()
	if not camera or not character then return nil end

	local result = workspace:Raycast(
		camera.CFrame.Position,
		camera.CFrame.LookVector * TARGETING.Reach,
		raycastParams
	)
	if not result then return nil end

	local model = shopkeeperOf(result.Instance)
	local state = model and States[model]
	return if model ~= character and state and state.PageId ~= "" then model else nil
end

local function render(deltaTime: number)
	ensureHighlight()
	focused = findFocus()

	if focused then
		highlight.Adornee = focused
		highlight.Enabled = true
	end

	local target = if focused then 1 else 0
	highlightAlpha += (target - highlightAlpha) * (1 - math.exp(-HIGHLIGHT_FADE_SPEED * deltaTime))
	if math.abs(target - highlightAlpha) < 1e-3 then highlightAlpha = target end

	if highlightAlpha <= 0 then
		if highlight.Enabled then
			highlight.Enabled = false
			highlight.Adornee = nil
		end
		return
	end

	highlight.FillTransparency = 1 - (1 - HIGHLIGHT.FillTransparency) * highlightAlpha
	highlight.OutlineTransparency = 1 - (1 - HIGHLIGHT.OutlineTransparency) * highlightAlpha
end

function ShopkeeperService:GetFocused(): Model?
	return focused
end

function ShopkeeperService:GetPageId(model: Model?): string?
	local target = model or focused
	local state = target and States[target]
	return if state and state.PageId ~= "" then state.PageId else nil
end

function ShopkeeperService:Open(): boolean
	local model = focused
	local state = model and States[model]
	if not state or state.PageId == "" then return false end

	local now = os.clock()
	if now - lastOpen < OPEN_COOLDOWN then return false end
	lastOpen = now

	InterfaceService:Open(state.PageId)
	return true
end

RunService:BindToRenderStep(FOCUS_JOB, Enum.RenderPriority.Camera.Value + 3, render)

player.CharacterRemoving:Connect(resetHighlight)
player.CharacterAdded:Connect(resetHighlight)

TagService:Listen(ShopkeeperConfig.Tag, register, unregister, workspace)

return ShopkeeperService
