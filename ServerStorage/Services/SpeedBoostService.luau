local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SprintConfig = require(ReplicatedStorage.Configs.SprintConfig)

local SpeedBoostService = {}

type Source = {
	Speed: number,
	Fov: number,
	ExpiresAt: number,
	Token: number,
	Effect: Instance?,
}

type State = {
	Character: Model,
	Humanoid: Humanoid,
	BaseSpeed: number,
	Sources: { [string]: Source },
	LastApplied: number,
	Suppressed: boolean,
	Writing: boolean,
	Changed: RBXScriptConnection?,
	Died: RBXScriptConnection?,
}

type BaseState = {
	Character: Model,
	Humanoid: Humanoid,
	Speed: number,
	Changed: RBXScriptConnection?,
}

local States: { [Player]: State } = {}
local BaseStates: { [Player]: BaseState } = {}
local Multipliers: { [Player]: number } = {}
local nextToken = 0

local function isClose(left: number, right: number): boolean
	return math.abs(left - right) <= 0.01
end

local function clearAttributes(player: Player)
	player:SetAttribute("SpeedBoostFov", nil)
	player:SetAttribute("SpeedBoostSpeed", nil)
	player:SetAttribute("SpeedBoostBaseSpeed", nil)
	player:SetAttribute("SpeedBoostEndsAt", nil)
	player:SetAttribute("SpeedBoostName", nil)
end

local function disconnectBaseState(player: Player)
	local state = BaseStates[player]
	if not state then return end

	BaseStates[player] = nil
	if state.Changed then state.Changed:Disconnect() end
end

local function bindBaseState(player: Player, character: Model)
	disconnectBaseState(player)

	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then return end
		if player.Character ~= character then return end

		local state: BaseState = {
			Character = character,
			Humanoid = humanoid,
			Speed = humanoid.WalkSpeed,
			Changed = nil,
		}
		BaseStates[player] = state

		state.Changed = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if BaseStates[player] ~= state or States[player] then return end

			local speed = humanoid.WalkSpeed
			if speed <= 0 or isClose(speed, state.Speed * SprintConfig.SpeedMultiplier) then return end
			state.Speed = speed
		end)
	end)
end

local function getBaseSpeed(player: Player, character: Model, humanoid: Humanoid): number
	local state = BaseStates[player]
	if state and state.Character == character and state.Humanoid == humanoid then
		return state.Speed
	end
	return humanoid.WalkSpeed
end

local function destroySource(source: Source)
	if source.Effect then
		source.Effect:Destroy()
		source.Effect = nil
	end
end

local function disconnectState(player: Player, restoreSpeed: boolean?)
	local state = States[player]
	if not state then return end

	States[player] = nil
	if state.Changed then state.Changed:Disconnect() end
	if state.Died then state.Died:Disconnect() end
	for _, source in state.Sources do
		destroySource(source)
	end

	if restoreSpeed and state.Humanoid.Parent and state.Humanoid.Health > 0 then
		state.Humanoid.WalkSpeed = state.BaseSpeed
	end
	clearAttributes(player)
end

local function getEffective(state: State): (string?, Source?)
	local bestName: string? = nil
	local best: Source? = nil
	for name, source in state.Sources do
		if not best or source.Speed > best.Speed then
			bestName = name
			best = source
		end
	end
	return bestName, best
end

local function writeSpeed(state: State, speed: number)
	state.Writing = true
	state.Humanoid.WalkSpeed = speed
	state.Writing = false
	state.LastApplied = speed
end

local function refresh(player: Player)
	local state = States[player]
	if not state then return end

	local name, source = getEffective(state)
	local boosted = source and source.Speed * (Multipliers[player] or 1)
	local desired = boosted and math.max(state.BaseSpeed, boosted) or state.BaseSpeed

	if source then
		player:SetAttribute("SpeedBoostBaseSpeed", state.BaseSpeed)
		player:SetAttribute("SpeedBoostSpeed", desired)
		player:SetAttribute("SpeedBoostFov", source.Fov)
		player:SetAttribute("SpeedBoostEndsAt", source.ExpiresAt)
		player:SetAttribute("SpeedBoostName", name)
	end

	if not source and not state.Suppressed then
		writeSpeed(state, desired)
	end

	if not source then
		clearAttributes(player)
		if not state.Suppressed then
			disconnectState(player, false)
		end
	end
end

local function createState(player: Player, character: Model, humanoid: Humanoid): State
	local state: State = {
		Character = character,
		Humanoid = humanoid,
		BaseSpeed = getBaseSpeed(player, character, humanoid),
		Sources = {},
		LastApplied = humanoid.WalkSpeed,
		Suppressed = false,
		Writing = false,
		Changed = nil,
		Died = nil,
	}
	States[player] = state

	state.Changed = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if state.Writing or States[player] ~= state then return end

		local speed = humanoid.WalkSpeed
		if speed <= 0 then
			state.Suppressed = true
			return
		end

		if next(state.Sources) then
			if state.Suppressed then
				state.Suppressed = false
				refresh(player)
			end
			return
		end

		if state.Suppressed then
			state.Suppressed = false
			if math.abs(speed - state.LastApplied) > 0.01 then
				state.BaseSpeed = speed
			end
		elseif math.abs(speed - state.LastApplied) <= 0.01 then
			return
		else
			state.BaseSpeed = speed
		end

		refresh(player)
	end)

	state.Died = humanoid.Died:Connect(function()
		disconnectState(player, false)
	end)

	return state
end

function SpeedBoostService:SetMultiplier(player: Player, multiplier: number)
	Multipliers[player] = if multiplier == 1 then nil else multiplier
	refresh(player)
end

function SpeedBoostService:GetMultiplier(player: Player): number
	return Multipliers[player] or 1
end

function SpeedBoostService:Apply(
	player: Player,
	name: string,
	speed: number,
	duration: number,
	fov: number,
	effectTemplate: Instance?
): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or humanoid.WalkSpeed <= 0 then return false end

	local state = States[player]
	if state and (state.Character ~= character or state.Humanoid ~= humanoid) then
		disconnectState(player, false)
		state = nil
	end
	if not state then
		state = createState(player, character, humanoid)
	end

	local old = state.Sources[name]
	if old then destroySource(old) end

	nextToken += 1
	local source: Source = {
		Speed = speed,
		Fov = fov,
		ExpiresAt = workspace:GetServerTimeNow() + duration,
		Token = nextToken,
		Effect = nil,
	}
	state.Sources[name] = source

	if effectTemplate then
		local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local effect = effectTemplate:Clone()
			effect.Enabled = true
			effect.Parent = root
			source.Effect = effect
		end
	end

	refresh(player)

	task.delay(duration, function()
		local currentState = States[player]
		local current = currentState and currentState.Sources[name]
		if not current or current.Token ~= source.Token then return end

		destroySource(current)
		currentState.Sources[name] = nil
		refresh(player)
	end)

	return true
end

Players.PlayerRemoving:Connect(function(player)
	disconnectBaseState(player)
	disconnectState(player, false)
	Multipliers[player] = nil
end)

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		bindBaseState(player, character)
	end)
	if player.Character then
		bindBaseState(player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)

return SpeedBoostService
