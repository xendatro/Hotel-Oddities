local Lifecycle = {Id="hotel-isolated",Version=1}

function Lifecycle.BeforeTrial(ctx)
	local services = game:GetService("ServerStorage").Services
	local director = require(services.EnemyDirectorService)
	local enemies = require(services.EnemyService)
	local chaos = require(services.ChaosService)
	ctx.State.Enemies = enemies
	ctx:Defer(director:AcquirePause())
	ctx:Defer(require(services.ProgrammaticVentService):AcquirePause())
	local vents = require(services.CeilingVentService)
	if vents.AcquirePause then ctx:Defer(vents:AcquirePause()) end
	local release,spawn = enemies:AcquireSpawnBlock()
	ctx:Defer(release)
	ctx.State.SpawnEnemy = spawn
	ctx:Defer(function()
		chaos:CancelPending(); enemies:DespawnAll(true)
		local deadline = os.clock()+8
		while #enemies:GetActive()>0 and os.clock()<deadline do task.wait(0.05) end
		assert(#enemies:GetActive()==0,"Enemy cleanup did not finish")
	end)
	chaos:CancelPending(); enemies:DespawnAll(true); director:Reset()
	ctx:WaitFor(function() return #enemies:GetActive()==0 end,8,"ambient enemy removal")
	ctx:Check("ambient enemies cleared",#enemies:GetActive()==0)
end

function Lifecycle.Validate(ctx)
	ctx:Check("expected enemy workload",#ctx.State.Enemies:GetActive()==(ctx.State.ExpectedEnemies or 0))
	local walkIns = workspace:FindFirstChild("CeilingWalkIns")
	ctx:Check("ceiling walk-ins cleared",not walkIns or #walkIns:GetChildren()==0)
end

function Lifecycle.AfterTrial(ctx)
	ctx:Mark("game cleanup","Enemies cleared; spawn block and director pause released")
end

return Lifecycle
