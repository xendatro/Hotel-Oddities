--- Drawers: the ones the player pulls open themselves. Every `Drawer`-tagged model in the hotel is
--- registered here, the one the cursor is resting on is worked out each frame, and the slide is run
--- locally on every machine from the boolean the server keeps on the model.
---
--- Opening is predicted rather than waited on. The drawer starts moving the moment it is asked to,
--- and the server's answer either confirms that or takes it back a moment later -- a drawer that
--- lagged half a second behind the key would feel broken in a way a rare correction does not.

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
--- How long a predicted open waits for the server to agree before it gives up and snaps back.
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
	--- Set while a local press is waiting to be confirmed: what was asked for, and when to give up.
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

--- Registration --------------------------------------------------------------------------------

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
		-- The server has spoken, so whatever was predicted is either confirmed or overruled.
		state.Predicted = nil
		refresh(state)
	end)

	States[model] = state
	-- A drawer already open when the player arrives is simply open, with no slide and no sound.
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

--- Targeting -----------------------------------------------------------------------------------

--- The tagged model a part belongs to, if any.
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

		-- Region markers and other invisible, walk-through parts are not what the player is looking
		-- at. Anything solid or visible is, and stops the ray.
		if result.Instance.CanCollide or result.Instance.Transparency < 1 then return nil end

		table.insert(ignored, result.Instance)
		params.FilterDescendantsInstances = ignored
	end

	return nil
end

local function render(deltaTime: number)
	focused = findFocus()

	-- Moving between two drawers keeps the highlight up rather than blinking it: only having
	-- nothing to point at fades it away.
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

--- Reading the state ---------------------------------------------------------------------------

--- The drawer the cursor is resting on, or nil.
function DrawerService:GetFocused(): Model?
	return focused
end

--- Whether `model` is currently pulled open. Defaults to the focused drawer.
function DrawerService:IsOpen(model: Model?): boolean
	local target = model or focused
	local state = target and States[target]
	return state ~= nil and state.Drawer:IsOpen()
end

--- Asks the server to open or shut the drawer being looked at, and starts the slide here without
--- waiting for it. Answers whether the request went out, which is what the prompt flashes on.
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

--- Stepping ------------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(deltaTime: number)
	local now = os.clock()
	for state in Moving do
		if state.Predicted ~= nil and now >= state.PredictedUntil then
			-- The server never answered. Whatever it thinks is the truth.
			state.Predicted = nil
			state.Drawer:SetOpen(desiredOpen(state))
		end
		if not state.Drawer:Step(deltaTime) then
			Moving[state] = nil
		end
	end
end)

RunService:BindToRenderStep(FOCUS_JOB, Enum.RenderPriority.Camera.Value + 3, render)

TagService:Listen(DrawerConfig.Tag, register, unregister, workspace)

return DrawerService
