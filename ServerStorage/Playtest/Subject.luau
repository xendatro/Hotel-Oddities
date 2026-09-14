local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Subject = {}

local Holds: { [Player]: any } = {}
local Guards: { [Player]: any } = {}

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Chaos and most enemies set Health straight to 0, so MaxHealth alone will not
-- save the subject. Without this a run ends with a respawn in the lobby and
-- every sample after that point is measuring the wrong place.
function Subject.invincible(player: Player)
	Subject.mortal(player)

	local guard = { connections = {} }
	Guards[player] = guard

	local function protect(humanoid: Humanoid)
		humanoid.MaxHealth = 1e6
		humanoid.Health = 1e6
		table.insert(guard.connections, humanoid:GetPropertyChangedSignal("Health"):Connect(function()
			if humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = humanoid.MaxHealth
			end
		end))
	end

	local humanoid = humanoidOf(player)
	if humanoid then protect(humanoid) end

	table.insert(guard.connections, player.CharacterAdded:Connect(function(character)
		local added = character:WaitForChild("Humanoid", 10)
		if added then protect(added :: Humanoid) end
	end))

	return function()
		Subject.mortal(player)
	end
end

function Subject.mortal(player: Player)
	local guard = Guards[player]
	if not guard then return end

	for _, connection in guard.connections do
		connection:Disconnect()
	end
	Guards[player] = nil

	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	end
end

-- Pins the subject so physics, knockback or a stray enemy cannot drift them out
-- of the area under test. Re-applies on a loop rather than anchoring, so normal
-- character behaviour still runs.
function Subject.hold(player: Player, position: Vector3, interval: number?)
	Subject.release(player)

	local hold = { running = true }
	Holds[player] = hold

	task.spawn(function()
		while hold.running do
			local character = player.Character
			if character then
				character:PivotTo(CFrame.new(position))
			end
			task.wait(interval or 0.2)
		end
	end)

	return function()
		Subject.release(player)
	end
end

function Subject.release(player: Player)
	local hold = Holds[player]
	if hold then
		hold.running = false
		Holds[player] = nil
	end
end

-- Ambient enemies wandering through the area under test will corrupt a
-- measurement. This clears what is alive right now; it does NOT stop the
-- director spawning more. To stop respawns, set FLAGS.Director = false before
-- starting the play session, because EnemyDirectorService reads that flag once
-- at require time and returns early.
function Subject.clearEnemies()
	local EnemyService = require(ServerStorage.Services.EnemyService)
	local ChaosService = require(ServerStorage.Services.ChaosService)

	local alive = #EnemyService:GetActive()
	local pending = ChaosService:CancelPending()
	EnemyService:DespawnAll()
	return { despawned = alive, cancelledChaosWarnings = pending }
end

function Subject.setup(player: Player, position: Vector3?)
	local restoreHealth = Subject.invincible(player)
	local releaseHold = if position then Subject.hold(player, position) else nil
	local cleared = Subject.clearEnemies()

	return function()
		if releaseHold then releaseHold() end
		restoreHealth()
	end, cleared
end

function Subject.first(): Player?
	return Players:GetPlayers()[1]
end

return Subject
