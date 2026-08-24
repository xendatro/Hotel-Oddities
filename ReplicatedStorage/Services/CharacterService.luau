local Players = game:GetService("Players")

local CharacterService = {}

function CharacterService.GetHumanoid(character: Model?): Humanoid?
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

function CharacterService.IsAlive(character: Model?): boolean
	local humanoid = CharacterService.GetHumanoid(character)
	return humanoid ~= nil and humanoid.Health > 0
end

function CharacterService.GetAliveRootFromCharacter(character: Model?): BasePart?
	if not character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	return root :: BasePart
end

function CharacterService.GetAliveRoot(player: Player): BasePart?
	return CharacterService.GetAliveRootFromCharacter(player.Character)
end

function CharacterService.GetAliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end
	return humanoid
end

function CharacterService.GetPosition(player: Player): Vector3?
	local root = CharacterService.GetAliveRoot(player)
	return if root then root.Position else nil
end

function CharacterService.ForEachPlayer(callback: (player: Player) -> ()): RBXScriptConnection
	local connection = Players.PlayerAdded:Connect(callback)
	for _, player in Players:GetPlayers() do
		task.spawn(callback, player)
	end
	return connection
end

function CharacterService.CleanupOnLeave(map: { [Player]: any }): RBXScriptConnection
	return Players.PlayerRemoving:Connect(function(player)
		map[player] = nil
	end)
end

return CharacterService
