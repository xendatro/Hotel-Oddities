local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrawerService = {}

if not RunService:IsClient() then
	return DrawerService
end

local Drawer = require(ReplicatedStorage.Classes.Drawer)
local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local TARGETING = DrawerConfig.Targeting
local HIGHLIGHT = DrawerConfig.Highlight
local FOCUS_JOB = "DrawerFocus"
local PREDICTION_TIMEOUT = 1
local HIGHLIGHT_FADE_SPEED = 16
local TOGGLE_COOLDOWN = 0.15

local player = Players.LocalPlayer

local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local folder = communication and communication:WaitForChild("Drawer", 30)
local ToggleRemote = folder and folder:WaitForChild("Toggle", 30)

type State = {
	Drawer: any,
	Connection: RBXScriptConnection,
	Predicted: boolean?,
	PredictedUntil: number,
}

local States: { [Model]: State } = {}
local Moving: { [State]: true } = {}
local focused: Model? = nil
local highlightAlpha = 0
local lastToggle = 0

local highlight = Instance.new("Highlight")
highlight.Name = "DrawerHighlight"
highlight.FillColor = HIGHLIGHT.FillColor
highlight.OutlineColor = HIGHLIGHT.OutlineColor
highlight.DepthMode = HIGHLIGHT.DepthMode
highlight.FillTransparency = 1
highlight.OutlineTransparency = 1
highlight.Enabled = false
highlight.Adornee = nil
highlight.Parent = workspace

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

local function desiredOpen(state: State): boolean
	if state.Predicted ~= nil then return state.Predicted end
	return state.Drawer.Model:GetAttribute(DrawerConfig.Attribute) == true
end

local function refresh(state: State, immediate: boolean?)
	state.Drawer:SetOpen(desiredOpen(state), immediate)
	if not immediate then
		Moving[state] = true
	end
end

local function register(model: Model): State?
	if not model:IsA("Model") then return nil end

	local state: State = {
		Drawer = Drawer.new(model),
		Connection = nil :: any,
		Predicted = nil,
		PredictedUntil = 0,
	}

	state.Connection = model:GetAttributeChangedSignal(DrawerConfig.Attribute):Connect(function()
		state.Predicted = nil
		refresh(state)
	end)

	States[model] = state
	refresh(state, true)
	return state
end

local function unregister(model: Model, state: State?)
	States[model] = nil
	if not state then return end

	Moving[state] = nil
	state.Connection:Disconnect()
	state.Drawer:Destroy()
	if focused == model then
		focused = nil
	end
end

local function drawerOf(part: BasePart): Model?
	local instance: Instance? = part
	while instance and instance ~= workspace do
		if instance:IsA("Model") and States[instance] then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

local function alive(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then character else nil
end

local function findFocus(): Model?
	local camera = workspace.CurrentCamera
	local character = alive()
	if not camera or not character then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = { character }
	params.FilterDescendantsInstances = ignored

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * TARGETING.Reach

	for _ = 1, TARGETING.MaxPassthrough + 1 do
		local result = workspace:Raycast(origin, direction, params)
		if not result then return nil end

		local model = drawerOf(result.Instance)
		if model then return model end

		if result.Instance.CanCollide or result.Instance.Transparency < 1 then return nil end

		table.insert(ignored, result.Instance)
		params.FilterDescendantsInstances = ignored
	end

	return nil
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

function DrawerService:GetFocused(): Model?
	return focused
end

function DrawerService:IsOpen(model: Model?): boolean
	local target = model or focused
	local state = target and States[target]
	return state ~= nil and state.Drawer:IsOpen()
end

function DrawerService:Toggle(): boolean
	local model = focused
	local state = model and States[model]
	if not state or not ToggleRemote then return false end

	local now = os.clock()
	if now - lastToggle < TOGGLE_COOLDOWN then return false end
	lastToggle = now

	local open = not state.Drawer:IsOpen()
	state.Predicted = open
	state.PredictedUntil = now + PREDICTION_TIMEOUT
	refresh(state)
	;(ToggleRemote :: RemoteEvent):FireServer(model, open)
	return true
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	local now = os.clock()
	for state in Moving do
		if state.Predicted ~= nil and now >= state.PredictedUntil then
			state.Predicted = nil
			state.Drawer:SetOpen(desiredOpen(state))
		end
		if not state.Drawer:Step(deltaTime) then
			Moving[state] = nil
		end
	end
end)

RunService:BindToRenderStep(FOCUS_JOB, Enum.RenderPriority.Camera.Value + 3, render)

player.CharacterRemoving:Connect(resetHighlight)
player.CharacterAdded:Connect(resetHighlight)

TagService:Listen(DrawerConfig.Tag, register, unregister, workspace)

return DrawerService
