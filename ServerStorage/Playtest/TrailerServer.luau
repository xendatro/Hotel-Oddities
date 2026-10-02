-- Server side of the trailer shoot, called through ServerBridge. Prepare()
-- makes the map hold still for a take: no enemies, no ambient oddities, no
-- vent drops, an invincible subject who is out of the spawn safe zone's
-- reach. Release() hands everything back.
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Quiet = require(ServerStorage.Playtest.Quiet)
local Subject = require(ServerStorage.Playtest.Subject)

local TrailerServer = {}

local releases: { () -> () } = {}
local sweep: RBXScriptConnection? = nil
local stoppedOddities = 0

local function service(name: string): any?
	local module = ServerStorage.Services:FindFirstChild(name)
	if not module then return nil end
	local ok, loaded = pcall(require, module)
	return if ok then loaded else nil
end

function TrailerServer.Prepare(player: Player?)
	if sweep then
		return TrailerServer.State()
	end

	local quiet = Quiet.on()
	table.insert(releases, Quiet.off)

	if player then
		table.insert(releases, (Subject.invincible(player)))
	end

	for _, name in { "EnemyDirectorService", "ProgrammaticVentService", "CeilingVentService" } do
		local loaded = service(name)
		if loaded and loaded.AcquirePause then
			local ok, release = pcall(loaded.AcquirePause, loaded)
			if ok and type(release) == "function" then
				table.insert(releases, release)
			end
		end
	end

	local oddities = service("OddityService")
	local since = 0
	sweep = RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 0.2 or not oddities then return end
		since = 0
		if workspace:GetAttribute("TrailerAllowOddities") then return end
		if next(oddities:GetActive()) then
			stoppedOddities += oddities:StopAll()
		end
	end)

	return { Quiet = quiet, Releases = #releases }
end

function TrailerServer.Release()
	if sweep then
		sweep:Disconnect()
		sweep = nil
	end
	for index = #releases, 1, -1 do
		pcall(releases[index])
	end
	table.clear(releases)
	return "released"
end

function TrailerServer.State()
	return { Active = sweep ~= nil, StoppedOddities = stoppedOddities, Quiet = Quiet.state() }
end

function TrailerServer.Place(player: Player, x: number, y: number, z: number)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(x, y, z))
	end
	return "placed"
end

return TrailerServer
