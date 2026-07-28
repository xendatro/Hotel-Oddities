local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- A `Vow`'s cancel closure: resolves the Vow and freezes its function at the call site.
export type Cancel = (...any) -> ()

--- Transition closure passed to states. First arg is the next state id; the rest are variant values.
export type ChangeState = (nextState: string, ...any) -> ()

--- A state's behavior: receives `(changeState, ...variant)`; resolve by returning, or calling
--- `changeState`, with `(nextStateId, ...variant)`.
export type StateFunction = (changeState: ChangeState, ...any) -> ...any

--- A perpetual watcher: receives `(cancel, machine)`; typically loops and calls `machine:SetState(...)`.
export type EvaluatorFunction = (cancel: Cancel, machine: StateMachine) -> ()

--- `Ready` = startable, `Active` = running, `Dead` = terminal.
export type MachineState = "Ready" | "Active" | "Dead"

--- Maps a reason id to the set of state ids that reason is allowed to override (interrupt). Gates
--- external `:SetState` — a `nil`/omitted reason or the reserved `"root"` reason overrides any state.
--- There are no state priorities; all authority lives in the reason.
export type Reasons = { [string]: { string } }

-- Minimal Vow interface used here.
type Vow = {
	Fire: (self: Vow, ...any) -> ...any,
	Cancel: (self: Vow, ...any) -> (),
	Destroy: (self: Vow) -> (),
}
type VowModule = { new: (func: any) -> Vow }
type Packed = { n: number, [number]: any }

local Vow = require(ReplicatedStorage.Classes.Vow) :: VowModule

local StateMachine = {}
StateMachine.__index = StateMachine

export type StateMachine = typeof(setmetatable(
	{} :: {
		State: string,
		Parameters: Packed,
		MachineThread: thread?,
		States: { [string]: StateFunction },
		Reasons: Reasons,
		StateThread: Vow?,
		Evaluators: { [string]: EvaluatorFunction },
		EvaluatorThreads: { [string]: Vow },
		MachineState: MachineState,
	},
	StateMachine
	))

--- Creates a new (unstarted) state machine.
--- @param states { [string]: StateFunction }
--- @param reasons Reasons -- {reasonId = {overridableStateId, ...}}; gates external `:SetState`
--- @param evaluators { [string]: EvaluatorFunction }
--- @param initialState string
--- @param ... any -- variant values forwarded to the initial state
--- @return StateMachine
function StateMachine.new(
	states: { [string]: StateFunction },
	reasons: Reasons,
	evaluators: { [string]: EvaluatorFunction },
	initialState: string,
	...: any
): StateMachine
	local self = setmetatable({}, StateMachine)
	self.State = initialState
	self.Parameters = table.pack(initialState, ...)
	self.MachineThread = nil
	self.States = states
	self.Reasons = reasons
	self.StateThread = nil
	self.Evaluators = evaluators
	self.EvaluatorThreads = {}
	self.MachineState = "Ready"
	return self
end

--- Adds a state. Errors if the id already exists.
--- @param stateId string
--- @param func StateFunction
function StateMachine:AddState(stateId: string, func: StateFunction)
	assert(self.States[stateId] == nil, `State {stateId} cannot be added; already exists in machine`)
	self.States[stateId] = func
end

--- Adds an evaluator. If the machine is running it starts now; otherwise on the next `Start`.
--- Errors if the id already exists.
--- @param evaluatorId string
--- @param func EvaluatorFunction
function StateMachine:AddEvaluator(evaluatorId: string, func: EvaluatorFunction)
	assert(self.Evaluators[evaluatorId] == nil, `Evaluator {evaluatorId} cannot be added; already exists in machine`)
	self.Evaluators[evaluatorId] = func
	if self.MachineState == "Active" then
		local vow = Vow.new(func)
		self.EvaluatorThreads[evaluatorId] = vow
		task.spawn(function()
			vow:Fire(self)
		end)
	end
end

--- Forces a transition from outside the current state, gated by `reasonId`. No-op if no state is running.
--- A `nil`/omitted reason or the reserved `"root"` reason overrides any state. Any other reason must be a
--- key in `Reasons` and only overrides when the current state is listed under it; an unmapped reason warns
--- and is ignored. Internal transitions (a state resolving) are never gated and always take priority.
--- @param stateId string
--- @param reasonId string? -- nil/"root" override anything; otherwise must be a mapped reason
--- @param ... any -- variant values forwarded to that state
function StateMachine:SetState(stateId: string, reasonId: string?, ...: any)
	if not self.StateThread then return end
	if reasonId ~= nil and reasonId ~= "root" then
		local overridable = self.Reasons[reasonId]
		if overridable == nil then
			warn(`StateMachine:SetState called with unmapped reason "{reasonId}"; ignoring`)
			return
		end
		if table.find(overridable, self.State) == nil then
			return -- this reason is not permitted to override the current state
		end
	end
	self.StateThread:Cancel(stateId, ...)
end

--- Starts the machine and fires every evaluator on its own thread. No-op unless `Ready`.
function StateMachine:Start()
	if self.MachineState ~= "Ready" then return end
	self.MachineState = "Active"
	self.MachineThread = task.spawn(function()
		while self.MachineState == "Active" do
			assert(self.States[self.Parameters[1]] ~= nil, `Attempted to call non-existent state {self.Parameters[1]}`)
			self.StateThread = Vow.new(self.States[self.Parameters[1]])
			local result = table.pack(self.StateThread:Fire(table.unpack(self.Parameters, 2, self.Parameters.n)))
			if self.MachineState ~= "Active" then break end
			self.Parameters = result
			self.State = result[1]
		end
	end)
	for evaluatorId, func in self.Evaluators do
		self.EvaluatorThreads[evaluatorId] = Vow.new(func)
	end
	for _, vow in self.EvaluatorThreads do
		task.spawn(function()
			vow:Fire(self)
		end)
	end
end

--- Pauses the machine; tears down the current state and evaluators, leaving it `Ready`. No-op unless `Active`.
function StateMachine:Stop()
	if self.MachineState ~= "Active" then return end
	self.MachineState = "Ready"
	self.StateThread:Destroy()
	for _, vow in self.EvaluatorThreads do
		vow:Destroy()
	end
end

--- Permanently destroys the machine; marks it `Dead`. No-op unless `Active`.
function StateMachine:Destroy()
	if self.MachineState ~= "Active" then return end
	self.MachineState = "Dead"
	self.StateThread:Destroy()
	for _, vow in self.EvaluatorThreads do
		vow:Destroy()
	end
end

return StateMachine
