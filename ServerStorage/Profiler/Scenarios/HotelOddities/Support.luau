local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Profiler.Scenarios.HotelOddities.Config)
local Scope = require(ReplicatedStorage.Profiler.Core.Scope)
local Support = {}

function Support.Prepare(ctx)
	local services = assert(ServerStorage:FindFirstChild("Services"),"Hotel services absent")
	local character = ctx:WaitFor(function() return ctx.Player.Character end,10,"character")
	local root = assert(character:FindFirstChild("HumanoidRootPart"),"No root")
	local original, anchored = character:GetPivot(),root.Anchored
	ctx.State.Root = root; ctx.State.Character = character
	ctx.State.Streaming = require(services.HallwayStreamingService)
	ctx:Defer(function()
		if root.Parent then character:PivotTo(original); root.Anchored = anchored; root.AssemblyLinearVelocity = Vector3.zero end
	end)
	root.Anchored = true
	Support.Teleport(ctx,Config.Origin)
	ctx:Sleep(2)
end

function Support.Teleport(ctx,position)
	local started = os.clock()
	assert(ctx.State.Streaming:PrepareTeleport(ctx.Player,position),"Destination did not finish streaming")
	ctx.State.Character:PivotTo(CFrame.lookAt(position,position+Vector3.xAxis))
	ctx:Mark("stream-ready",string.format("%.3fs at %s",os.clock()-started,tostring(position)))
end

Support.Move = Scope.Wrap("Hotel.Route.Pivot",function(ctx,position)
	ctx.State.Character:PivotTo(CFrame.lookAt(position,position+Vector3.xAxis))
end)

function Support.Validate(ctx)
	ctx:Check("subject survived",ctx.Player.Character == ctx.State.Character
		and ctx.State.Character:FindFirstChildOfClass("Humanoid").Health > 0)
end

return Support
