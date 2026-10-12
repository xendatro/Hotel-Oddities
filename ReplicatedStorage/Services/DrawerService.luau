local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrawerService = {}

if not RunService:IsClient() then
	return DrawerService
end

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local Drawer = require(ReplicatedStorage.Classes.Drawer)
local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local TagService = require(ReplicatedStorage.Services.TagService)

local PREDICTION_TIMEOUT = 1
local TOGGLE_COOLDOWN = 0.15

local ToggleRemote = CommunicationService.Get("Drawer", "Toggle")

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
local contents: { Find: (drawer: Model) -> Model?, Take: (item: Model) -> boolean }? = nil

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

local function takeableItem(state: State): Model?
	if not contents or not state.Drawer:IsOpen() then return nil end
	if Interaction:GetInputMode() == "Keyboard" then return nil end
	return contents.Find(state.Drawer.Model)
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
			return DrawerService:GetPrompt(target)
		end,
		TextWidth = DrawerConfig.UI.TextWidth,
		Reach = DrawerConfig.Targeting.Reach,
		SkipTouch = true,
		OnActivated = function(target: Model)
			return DrawerService:Activate(target)
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

function DrawerService:GetDrawers(): { Model }
	local drawers = {}
	for model in States do
		table.insert(drawers, model)
	end
	return drawers
end

function DrawerService:GetPrompt(model: Model): string?
	local state = States[model]
	if not state then return nil end
	if takeableItem(state) then return DrawerConfig.UI.TakeText end
	return if state.Drawer:IsOpen() then DrawerConfig.UI.CloseText else DrawerConfig.UI.OpenText
end

function DrawerService:Activate(model: Model): boolean
	local state = States[model]
	local item = state and takeableItem(state)
	if item and contents then
		return contents.Take(item)
	end
	return DrawerService:Toggle(model)
end

function DrawerService:IsOpen(model: Model?): boolean
	local target = model or focused
	local state = target and States[target]
	return state ~= nil and state.Drawer:IsOpen()
end

function DrawerService:SetContents(find: (drawer: Model) -> Model?, take: (item: Model) -> boolean)
	contents = { Find = find, Take = take }
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
