local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local ComputerChipConfig = require(ReplicatedStorage.Configs.ComputerChipConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
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
local completed: { [string]: boolean } = {}
local exitUnlocked = false
local receivedProgress = false

local function refreshAccess(state: ElevatorState)
	if state.Model:GetAttribute(ElevatorConfig.TypeAttribute) ~= ElevatorConfig.ExitType then return end
	local barrier = state.Model:FindFirstChild("AccessBarrier")
	if barrier and barrier:IsA("BasePart") then barrier.CanCollide = not exitUnlocked end
	local panel = state.Model:FindFirstChild("StatusPanel")
	local display = panel and panel:FindFirstChild("ProgressDisplay")
	if not display then return end
	local count = 0
	for _, entry in ComputerChipConfig.Colors do
		local complete = completed[entry.Key] == true
		if complete then count += 1 end
		local row = display:FindFirstChild(entry.Key)
		if not row then continue end
		local color = if complete then Color3.fromRGB(126, 226, 153) else Color3.fromRGB(220, 134, 124)
		local status = row:FindFirstChild("Status")
		if status and status:IsA("TextLabel") then
			status.Text = if complete then "COMPLETE" else "MISSING"
			status.TextColor3 = color
		end
		local indicator = row:FindFirstChild("Indicator")
		local bar1 = indicator and indicator:FindFirstChild("Bar1")
		local bar2 = indicator and indicator:FindFirstChild("Bar2")
		if bar1 and bar1:IsA("Frame") and bar2 and bar2:IsA("Frame") then
			bar1.BackgroundColor3 = color
			bar2.BackgroundColor3 = color
			bar1.Rotation = if complete then 45 else -45
			bar1.Size = UDim2.fromOffset(if complete then 14 else 31, 5)
			bar1.Position = if complete then UDim2.fromScale(0.22, 0.6) else UDim2.fromScale(0.5, 0.5)
			bar2.Rotation = if complete then -45 else 45
			bar2.Position = if complete then UDim2.fromScale(0.64, 0.45) else UDim2.fromScale(0.5, 0.5)
		end
	end
	local summary = display:FindFirstChild("Summary")
	if summary and summary:IsA("TextLabel") then
		summary.Text = if exitUnlocked then "READY - ENTER" else `LOCKED   {count} / 5`
		summary.TextColor3 = if exitUnlocked then Color3.fromRGB(126, 226, 153) else Color3.fromRGB(230, 150, 125)
	end
end



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

	local offset = state.Model:GetAttribute("DoorOffset") or ElevatorConfig.DoorOffset
	local info = TweenInfo.new(ElevatorConfig.DoorTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if state.Part1 and state.Closed1 then
		local target = if open
			then state.Closed1 * CFrame.new(-offset, 0, 0)
			else state.Closed1
		local tween = TweenService:Create(state.Part1, info, { CFrame = target })
		table.insert(state.Tweens, tween)
		tween:Play()
	end
	if state.Part2 and state.Closed2 then
		local target = if open
			then state.Closed2 * CFrame.new(offset, 0, 0)
			else state.Closed2
		local tween = TweenService:Create(state.Part2, info, { CFrame = target })
		table.insert(state.Tweens, tween)
		tween:Play()
	end
end

local function nearestPlayerDistance(position: Vector3, localOnly: boolean): number
	local nearest = math.huge
	for _, player in (if localOnly then { Players.LocalPlayer } else Players:GetPlayers()) do
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
	refreshAccess(state)
	state.DescendantConnection = model.DescendantAdded:Connect(function()
		refreshDoors(state)
		refreshAccess(state)
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
		local kind = model:GetAttribute(ElevatorConfig.TypeAttribute)
		if kind ~= ElevatorConfig.LobbyType and kind ~= ElevatorConfig.StartType and (kind ~= ElevatorConfig.ExitType or not exitUnlocked) then
			setOpen(state, false)
			continue
		end

		local distance = nearestPlayerDistance(model:GetPivot().Position, not isLobbyElevator(state))
		local shouldOpen = if state.Opened
			then distance <= ElevatorConfig.CloseDistance
			else distance <= ElevatorConfig.OpenDistance
		setOpen(state, shouldOpen)
	end
end)

task.spawn(function()
	local sync = CommunicationService.Get(ComputerConfig.Remotes.Folder, ComputerConfig.Remotes.Sync)
	sync.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.Colors) ~= "table" then return end
		receivedProgress = true
		completed = payload.Colors
		exitUnlocked = payload.ExitUnlocked == true
		for _, state in states do refreshAccess(state) end
	end)
	repeat
		sync:FireServer()
		task.wait(2)
	until receivedProgress
end)

return ElevatorDoorService
