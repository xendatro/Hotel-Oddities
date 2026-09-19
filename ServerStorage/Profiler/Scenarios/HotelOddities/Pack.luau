local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Profiler.Scenarios.HotelOddities.Config)
local Scope = require(ReplicatedStorage.Profiler.Core.Scope)
local Support = require(script.Parent.Support)

local function spawnEnemy(ctx)
	Support.Prepare(ctx)
	local enemy = assert(ctx.State.SpawnEnemy("Chaser",CFrame.new(Config.EnemyOrigin)),"Chaser did not spawn")
	ctx.State.Enemy = enemy; ctx.State.ExpectedEnemies = 1
	ctx.State.StartPosition = enemy.RootPart.Position; ctx.State.Distance = 0; ctx.State.Pursuit = false
	ctx:Defer(function() if enemy.Active then enemy.SilentDespawn = true; enemy:Despawn() end end)
	-- Harmless suppresses contact death without making the subject invisible to AI.
	enemy.Model:SetAttribute("Harmless",true)
	ctx:WaitFor(function() return enemy.Model:GetAttribute("ChaseTargetUserId") == ctx.Player.UserId end,20,"Chaser pursuit")
end

local function enemyStep(ctx,_,_,dt)
	local enemy = ctx.State.Enemy
	assert(enemy.Active and enemy.RootPart.Parent,"Chaser stopped running")
	local position = enemy.RootPart.Position
	ctx.State.Distance += (position-ctx.State.StartPosition).Magnitude
	ctx.State.StartPosition = position
	ctx.State.Pursuit = ctx.State.Pursuit or enemy.Model:GetAttribute("ChaseTargetUserId") == ctx.Player.UserId
	Scope.Count("Hotel.Enemy.ObservedTicks")
	Scope.Count("Hotel.Enemy.ObservedSeconds",dt)
end

return { Scenarios = {
	{ Id = "hotel.hallway", Name = "Hallway views", Version = 1, Controlled = true, Focus = "render",
		Description = "Fixed east/west hallway views. Resets ambient enemies in an isolated test server.",
		Phases = { "east","west" }, Prepare = Support.Prepare, Validate = Support.Validate },
	{ Id = "hotel.streaming", Name = "Streaming traversal", Version = 1, Controlled = true, Focus = "all",
		Description = "Fixed 220-stud kinematic character route; tests streaming, not normal walking physics.",
		Phases = { "traverse" }, Prepare = Support.Prepare,
		Step = function(ctx,_,elapsed)
			Support.Move(ctx,Config.Origin:Lerp(Config.RouteEnd,math.clamp(elapsed/ctx.Options.duration,0,1)))
		end,
		Validate = function(ctx)
			Support.Validate(ctx)
			ctx:Check("route completed",(ctx.State.Root.Position-Config.RouteEnd).Magnitude < 3,tostring(ctx.State.Root.Position))
		end },
	{ Id = "hotel.enemy", Name = "Chaser encounter", Version = 1, Controlled = true, Focus = "all",
		Description = "One Chaser pursuing a fixed subject. Validates movement and pursuit; resets ambient enemies.",
		Phases = { "encounter" }, Prepare = spawnEnemy, Step = enemyStep,
		Validate = function(ctx)
			Support.Validate(ctx)
			ctx:Check("Chaser actually pursued",ctx.State.Pursuit)
			ctx:Check("Chaser actually moved",ctx.State.Distance > 2,string.format("%.2f studs",ctx.State.Distance))
		end },
	{ Id = "hotel.ui", Name = "Inventory and index", Version = 1, Controlled = true, Focus = "memory",
		Description = "Measure visible Inventory, Index and closed pages; repeat to inspect retained memory.",
		Phases = { "Inventory","Index","closed" }, Prepare = function(ctx)
			local root = assert(ctx.Player.Character and ctx.Player.Character:FindFirstChild("HumanoidRootPart"),"No character")
			local anchored = root.Anchored
			ctx:Defer(function() if root.Parent then root.Anchored = anchored end end)
			root.Anchored = true
		end },
	{ Id = "hotel.reentry", Name = "Maze and lobby cycles", Version = 1, Controlled = true, Focus = "memory",
		Description = "Repeat warm-cache maze/lobby transfers; records readiness events and retained memory.",
		Phases = { "maze","lobby" }, Prepare = Support.Prepare,
		PreparePhase = function(ctx,phase) Support.Teleport(ctx,if phase == "maze" then Config.Origin else Config.Lobby) end,
		Validate = Support.Validate },
} }
