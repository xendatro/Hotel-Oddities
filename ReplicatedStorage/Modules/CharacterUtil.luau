local Players = game:GetService("Players")

local CharacterUtil = {}

function CharacterUtil.GetHumanoid(character: Model?): Humanoid?
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

function CharacterUtil.IsAlive(character: Model?): boolean
	local humanoid = CharacterUtil.GetHumanoid(character)
	return humanoid ~= nil and humanoid.Health > 0
end

function CharacterUtil.GetAliveRootFromCharacter(character: Model?): BasePart?
	if not character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	return root :: BasePart
end

function CharacterUtil.GetAliveRoot(player: Player): BasePart?
	return CharacterUtil.GetAliveRootFromCharacter(player.Character)
end

function CharacterUtil.GetAliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end
	return humanoid
end

function CharacterUtil.GetPosition(player: Player): Vector3?
	local root = CharacterUtil.GetAliveRoot(player)
	return if root then root.Position else nil
end

function CharacterUtil.ForEachPlayer(callback: (player: Player) -> ()): RBXScriptConnection
	local connection = Players.PlayerAdded:Connect(callback)
	for _, player in Players:GetPlayers() do
		task.spawn(callback, player)
	end
	return connection
end

function CharacterUtil.CleanupOnLeave(map: { [Player]: any }): RBXScriptConnection
	return Players.PlayerRemoving:Connect(function(player)
		map[player] = nil
	end)
end

return CharacterUtil
