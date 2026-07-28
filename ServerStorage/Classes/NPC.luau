local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)

local NPC = {}
NPC.__index = NPC

-- Default state shared by every NPC: idle for a random 4-7s, then loop back to itself.
-- A state receives (changeState, npc); re-forward `npc` so it stays available across transitions.
local function basicIdle(_changeState: StateMachine.ChangeState, npc: any)
	task.wait(math.random() * 3 + 4)
	return "BasicIdle", npc
end

function NPC.new(model: Model)
	local self = setmetatable({}, NPC)

	self.StateMachine = StateMachine.new({
		BasicIdle = basicIdle,
	}, {}, {}, "BasicIdle", self)

	return self
end

-- Starts this NPC's state machine. Shared by all NPC subclasses.
function NPC:Start()
	self.StateMachine:Start()
end

-- Stops this NPC's state machine. Shared by all NPC subclasses.
function NPC:Stop()
	self.StateMachine:Stop()
end

return NPC