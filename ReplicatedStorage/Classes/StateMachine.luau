local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Cancel = (...any) -> ()

export type ChangeState = (nextState: string, ...any) -> ()

export type StateFunction = (changeState: ChangeState, ...any) -> ...any

export type EvaluatorFunction = (cancel: Cancel, machine: StateMachine) -> ()

export type MachineState = "Ready" | "Active" | "Dead"

export type Reasons = { [string]: { string } }

type Vow = {
	Fire: (self: Vow, ...any) -> ...any,
	Cancel: (self: Vow, ...any) -> (),
	Destroy: (self: Vow) -> (),
}
type VowModule = { new: (func: any) -> Vow }
type Packed = { n: number, [number]: any }

local Vow = require(ReplicatedStorage.Classes.Vow) :: VowModule

local RECOVERY_DELAY = 0.5

local StateMachine = {}
StateMachine.__index = StateMachine

export type StateMachine = typeof(setmetatable(
	{} :: {
		State: string,
		Parameters: Packed,
		RecoveryParameters: Packed,
		MachineThread: thread?,
		States: { [string]: StateFunction },
		Reasons: Reasons,
		StateThread: Vow?,
		Evaluators: { [string]: EvaluatorFunction },
		EvaluatorThreads: { [string]: Vow },
		MachineState: MachineState,
		OnStateChanged: ((string) -> ())?,
	},
	StateMachine
	))

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
	self.RecoveryParameters = table.pack(initialState, ...)
	self.MachineThread = nil
	self.States = states
	self.Reasons = reasons
	self.StateThread = nil
	self.Evaluators = evaluators
	self.EvaluatorThreads = {}
	self.MachineState = "Ready"
	return self
end

function StateMachine:_runEvaluator(evaluatorId: string, vow: Vow)
	task.spawn(function()
		while self.MachineState == "Active" and self.EvaluatorThreads[evaluatorId] == vow do
			local ok, err = pcall(function()
				vow:Fire(self)
			end)
			if ok then break end
			warn(`StateMachine: evaluator "{evaluatorId}" failed, restarting -- {err}`)
			task.wait(RECOVERY_DELAY)
		end
	end)
end

function StateMachine:_setState(stateId: string)
	self.State = stateId
	if self.OnStateChanged then
		self.OnStateChanged(stateId)
	end
end

function StateMachine:SetStartState(stateId: string, ...: any)
	if self.MachineState ~= "Ready" then return end
	self.State = stateId
	self.Parameters = table.pack(stateId, ...)
end

function StateMachine:AddState(stateId: string, func: StateFunction)
	assert(self.States[stateId] == nil, `State {stateId} cannot be added; already exists in machine`)
	self.States[stateId] = func
end

function StateMachine:AddEvaluator(evaluatorId: string, func: EvaluatorFunction)
	assert(self.Evaluators[evaluatorId] == nil, `Evaluator {evaluatorId} cannot be added; already exists in machine`)
	self.Evaluators[evaluatorId] = func
	if self.MachineState == "Active" then
		local vow = Vow.new(func)
		self.EvaluatorThreads[evaluatorId] = vow
		self:_runEvaluator(evaluatorId, vow)
	end
end

function StateMachine:SetState(stateId: string, reasonId: string?, ...: any)
	if not self.StateThread then return end
	if reasonId ~= nil and reasonId ~= "root" then
		local overridable = self.Reasons[reasonId]
		if overridable == nil then
			warn(`StateMachine:SetState called with unmapped reason "{reasonId}"; ignoring`)
			return
		end
		if table.find(overridable, self.State) == nil then
			return
		end
	end
	self.StateThread:Cancel(stateId, ...)
end

function StateMachine:Start()
	if self.MachineState ~= "Ready" then return end
	self.MachineState = "Active"
	self.MachineThread = task.spawn(function()
		while self.MachineState == "Active" do
			local stateId = self.Parameters[1]
			local state = self.States[stateId]

			local ok: boolean, result: any
			if state then
				self.StateThread = Vow.new(state)
				ok, result = pcall(function()
					return table.pack(self.StateThread:Fire(table.unpack(self.Parameters, 2, self.Parameters.n)))
				end)
			else
				ok, result = false, `resolved to non-existent state "{tostring(stateId)}"`
			end
			if self.MachineState ~= "Active" then break end

			if ok then
				local resolved = result :: Packed
				self.Parameters = resolved
				if resolved[1] ~= nil then
					self:_setState(resolved[1])
				end
			else
				warn(`StateMachine: state "{tostring(stateId)}" failed, recovering to "{self.RecoveryParameters[1]}" -- {result}`)
				task.wait(RECOVERY_DELAY)
				if self.MachineState ~= "Active" then break end
				self.Parameters = self.RecoveryParameters
				self:_setState(self.RecoveryParameters[1])
			end
		end
	end)
	for evaluatorId, func in self.Evaluators do
		self.EvaluatorThreads[evaluatorId] = Vow.new(func)
	end
	for evaluatorId, vow in self.EvaluatorThreads do
		self:_runEvaluator(evaluatorId, vow)
	end
end

function StateMachine:Stop()
	if self.MachineState ~= "Active" then return end
	self.MachineState = "Ready"
	self.StateThread:Destroy()
	for _, vow in self.EvaluatorThreads do
		vow:Destroy()
	end
end

function StateMachine:Destroy()
	if self.MachineState == "Dead" then return end
	self.MachineState = "Dead"
	if self.StateThread then
		self.StateThread:Destroy()
	end
	for _, vow in self.EvaluatorThreads do
		vow:Destroy()
	end
	table.clear(self.EvaluatorThreads)
end

return StateMachine
