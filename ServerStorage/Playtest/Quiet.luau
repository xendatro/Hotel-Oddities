-- Silences the map for a playtest: clears every live enemy, cancels pending
-- Chaos warnings, holds an EnemyService spawn block, and keeps sweeping so
-- nothing that slips past the block survives long. A Stalker attack rotates the
-- client camera, which ruins a scripted-camera screenshot, so one clear at the
-- start is not enough for a test that runs for minutes.
--
-- The sweep works off the Enemy tag rather than EnemyService:GetActive(),
-- because an MCP-executed snippet gets its own copy of EnemyService whose
-- ActiveEnemies table is empty while the game's real enemies are walking
-- around. The tag is on the model either way. See PLAYTESTING.md.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local EnemyService = require(ServerStorage.Services.EnemyService)
local ChaosService = require(ServerStorage.Services.ChaosService)

local ENEMY_TAG = "Enemy"
local SWEEP_INTERVAL = 0.5

local Quiet = {}

local release: (() -> ())? = nil
local sweep: RBXScriptConnection? = nil
local cleared = 0
local cancelled = 0

local function isEnemyModel(instance: Instance): boolean
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then return false end
	return Players:GetPlayerFromCharacter(instance) == nil
end

local function purge(): number
	local removed = 0

	-- Ask the service first so its own bookkeeping stays straight; anything it
	-- does not know about (or a duplicated service instance) is destroyed.
	local known: { [Instance]: any } = {}
	for _, enemy in EnemyService:GetActive() do
		if enemy.Model then known[enemy.Model] = enemy end
	end

	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		if not isEnemyModel(model) then continue end

		local enemy = known[model]
		if enemy then
			enemy.SilentDespawn = true
			local ok = pcall(function() enemy:Despawn() end)
			if ok and not model.Parent then
				removed += 1
				continue
			end
		end
		model:Destroy()
		removed += 1
	end

	cancelled += ChaosService:CancelPending()
	cleared += removed
	return removed
end

-- Idempotent. Call it again mid-test to read the running totals.
function Quiet.on()
	if not release then
		release = (EnemyService:AcquireSpawnBlock())
	end

	local first = purge()

	if not sweep then
		local since = 0
		sweep = RunService.Heartbeat:Connect(function(deltaTime: number)
			since += deltaTime
			if since < SWEEP_INTERVAL then return end
			since = 0
			purge()
		end)
	end

	return { clearedNow = first, clearedTotal = cleared, cancelledChaosWarnings = cancelled }
end

function Quiet.off()
	if sweep then
		sweep:Disconnect()
		sweep = nil
	end
	if release then
		release()
		release = nil
	end
	return { clearedTotal = cleared, cancelledChaosWarnings = cancelled }
end

function Quiet.state()
	local tagged = 0
	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		if isEnemyModel(model) then tagged += 1 end
	end
	return {
		active = release ~= nil,
		sweeping = sweep ~= nil,
		tagged = tagged,
		serviceActive = #EnemyService:GetActive(),
		clearedTotal = cleared,
		cancelledChaosWarnings = cancelled,
	}
end

return Quiet
