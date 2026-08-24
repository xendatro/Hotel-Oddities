local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MathService = require(ReplicatedStorage.Services.MathService)

local ElevatorDoorService = {}

if not RunService:IsClient() then
	return ElevatorDoorService
end

type ElevatorState = {
	Model: Model,
	Part1: BasePart?,
	Part2: BasePart?,
	Closed1: CFrame?,
	Closed2: CFrame?,
	Opened: boolean,
	Tweens: { Tween },
	DescendantConnection: RBXScriptConnection?,
}

local states: { [Model]: ElevatorState } = {}
local sincePoll = 0

local function findBasePart(parent: Instance, names: { string }): BasePart?
	for _, name in names do
		local child = parent:FindFirstChild(name)
		if child and child:IsA("BasePart") then return child end
	end
	return nil
end

local function refreshDoors(state: ElevatorState)
	local doors = state.Model:FindFirstChild(ElevatorConfig.DoorsName)
	if not doors then return end

	local part1 = findBasePart(doors, { "Part1", "Part 1" })
	local part2 = findBasePart(doors, { "Part2", "Part 2" })
	if part1 and part1 ~= state.Part1 then
		state.Part1 = part1
		state.Closed1 = part1.CFrame
	end
	if part2 and part2 ~= state.Part2 then
		state.Part2 = part2
		state.Closed2 = part2.CFrame
	end
end

local function isLobbyElevator(state: ElevatorState): boolean
	return state.Model:GetAttribute(ElevatorConfig.TypeAttribute) == ElevatorConfig.LobbyType
end

local function cancelTweens(state: ElevatorState)
	for _, tween in state.Tweens do tween:Cancel() end
	table.clear(state.Tweens)
end

local function setOpen(state: ElevatorState, open: boolean)
	if state.Opened == open then return end
	state.Opened = open
	cancelTweens(state)

	local soundParent = state.Part1 or state.Part2
	if soundParent then
		AudioService:Play3DSound("Elevator", soundParent, false, "SFX")
	end

	local info = TweenInfo.new(ElevatorConfig.DoorTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if state.Part1 and state.Closed1 then
		local target = if open
			then state.Closed1 * CFrame.new(-ElevatorConfig.DoorOffset, 0, 0)
			else state.Closed1
		local tween = TweenService:Create(state.Part1, info, { CFrame = target })
		table.insert(state.Tweens, tween)
		tween:Play()
	end
	if state.Part2 and state.Closed2 then
		local target = if open
			then state.Closed2 * CFrame.new(ElevatorConfig.DoorOffset, 0, 0)
			else state.Closed2
		local tween = TweenService:Create(state.Part2, info, { CFrame = target })
		table.insert(state.Tweens, tween)
		tween:Play()
	end
end

local function nearestPlayerDistance(position: Vector3): number
	local nearest = math.huge
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root then
			local offset = root.Position - position
			if math.abs(offset.Y) <= ElevatorConfig.MaxHeightDifference then
				nearest = math.min(nearest, MathService.HorizontalMagnitude(offset))
			end
		end
	end
	return nearest
end

local function register(model: Instance)
	if not model:IsA("Model") or states[model] then return end
	local state: ElevatorState = {
		Model = model,
		Part1 = nil,
		Part2 = nil,
		Closed1 = nil,
		Closed2 = nil,
		Opened = false,
		Tweens = {},
		DescendantConnection = nil,
	}
	states[model] = state
	refreshDoors(state)
	state.DescendantConnection = model.DescendantAdded:Connect(function()
		refreshDoors(state)
	end)
end

local function unregister(model: Instance)
	if not model:IsA("Model") then return end
	local state = states[model]
	if not state then return end
	cancelTweens(state)
	if state.DescendantConnection then state.DescendantConnection:Disconnect() end
	states[model] = nil
end

for _, model in CollectionService:GetTagged(ElevatorConfig.Tag) do register(model) end
CollectionService:GetInstanceAddedSignal(ElevatorConfig.Tag):Connect(register)
CollectionService:GetInstanceRemovedSignal(ElevatorConfig.Tag):Connect(unregister)

RunService.Heartbeat:Connect(function(deltaTime)
	sincePoll += deltaTime
	if sincePoll < ElevatorConfig.PollInterval then return end
	sincePoll = 0

	for model, state in states do
		if not model.Parent then
			unregister(model)
			continue
		end
		if not isLobbyElevator(state) then
			setOpen(state, false)
			continue
		end

		local distance = nearestPlayerDistance(model:GetPivot().Position)
		local shouldOpen = if state.Opened
			then distance <= ElevatorConfig.CloseDistance
			else distance <= ElevatorConfig.OpenDistance
		setOpen(state, shouldOpen)
	end
end)

return ElevatorDoorService
