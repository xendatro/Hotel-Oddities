local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopkeeperService = {}

if not RunService:IsClient() then
	return ShopkeeperService
end

local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local ShopkeeperConfig = require(ReplicatedStorage.Configs.ShopkeeperConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local PAGE_ATTRIBUTE = ShopkeeperConfig.PageAttribute
local OPEN_COOLDOWN = 0.15

type State = {
	PageId: string,
	AttributeConnection: RBXScriptConnection,
	DescendantConnection: RBXScriptConnection,
	SmileTrack: AnimationTrack?,
}

local States: { [Model]: State } = {}
local focused: Model? = nil
local lastOpen = 0

local smileAnimation = Instance.new("Animation")
smileAnimation.AnimationId = `rbxassetid://{ShopkeeperConfig.SmileAnimationId}`

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
	Interaction:Register(model, {
		Prompt = function(target: Model): string?
			local current = States[target]
			return if current and current.PageId ~= "" then `Open {current.PageId}` else nil
		end,
		TextWidth = ShopkeeperConfig.UI.TextWidth,
		Reach = ShopkeeperConfig.Targeting.Reach,
		IgnoreOcclusion = true,
		OnActivated = function(target: Model)
			return ShopkeeperService:Open(target)
		end,
	})
	startSmile(model, state)
	return state
end

local function unregister(model: Model, state: State?)
	States[model] = nil
	Interaction:Unregister(model)
	if not state then return end

	if state.SmileTrack then
		state.SmileTrack:Stop(0)
		state.SmileTrack:Destroy()
	end
	state.AttributeConnection:Disconnect()
	state.DescendantConnection:Disconnect()
end

function ShopkeeperService:GetFocused(): Model?
	return focused
end

function ShopkeeperService:GetPageId(model: Model?): string?
	local target = model or focused
	local state = target and States[target]
	return if state and state.PageId ~= "" then state.PageId else nil
end

function ShopkeeperService:Open(model: Model?): boolean
	local target = model or focused
	local state = target and States[target]
	if not state or state.PageId == "" then return false end

	local now = os.clock()
	if now - lastOpen < OPEN_COOLDOWN then return false end
	lastOpen = now

	InterfaceService:Open(state.PageId)
	return true
end

Interaction.Selected:Connect(function(model: Model?)
	focused = if model and States[model] then model else nil
end)

TagService:Listen(ShopkeeperConfig.Tag, register, unregister, workspace)

return ShopkeeperService
