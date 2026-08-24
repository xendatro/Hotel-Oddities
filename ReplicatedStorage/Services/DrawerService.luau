local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrawerService = {}

if not RunService:IsClient() then
	return DrawerService
end

local Drawer = require(ReplicatedStorage.Classes.Drawer)
local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local TagService = require(ReplicatedStorage.Services.TagService)

local PREDICTION_TIMEOUT = 1
local TOGGLE_COOLDOWN = 0.15

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
local lastToggle = 0

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
	Interaction:Register(model, {
		Prompt = function(target: Model): string?
			local current = States[target]
			if not current then return nil end
			return if current.Drawer:IsOpen() then DrawerConfig.UI.CloseText else DrawerConfig.UI.OpenText
		end,
		TextWidth = DrawerConfig.UI.TextWidth,
		Reach = DrawerConfig.Targeting.Reach,
		OnActivated = function(target: Model)
			return DrawerService:Toggle(target)
		end,
	})
	refresh(state, true)
	return state
end

local function unregister(model: Model, state: State?)
	States[model] = nil
	Interaction:Unregister(model)
	if not state then return end

	Moving[state] = nil
	state.Connection:Disconnect()
	state.Drawer:Destroy()
end

function DrawerService:GetFocused(): Model?
	return focused
end

function DrawerService:IsOpen(model: Model?): boolean
	local target = model or focused
	local state = target and States[target]
	return state ~= nil and state.Drawer:IsOpen()
end

function DrawerService:Sync(model: Model)
	local state = States[model]
	if state then
		state.Drawer:_apply()
	end
end

function DrawerService:Toggle(model: Model?): boolean
	local target = model or focused
	local state = target and States[target]
	if not state or not ToggleRemote then return false end

	local now = os.clock()
	if now - lastToggle < TOGGLE_COOLDOWN then return false end
	lastToggle = now

	local open = not state.Drawer:IsOpen()
	state.Predicted = open
	state.PredictedUntil = now + PREDICTION_TIMEOUT
	refresh(state)
	;(ToggleRemote :: RemoteEvent):FireServer(target, open)
	return true
end

Interaction.Selected:Connect(function(model: Model?)
	focused = if model and States[model] then model else nil
end)

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

TagService:Listen(DrawerConfig.Tag, register, unregister, workspace)

return DrawerService
