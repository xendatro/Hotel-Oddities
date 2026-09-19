local function hold(ctx)
	local character = ctx:WaitFor(function() return ctx.Player.Character end,10,"character")
	local root = ctx:WaitFor(function() return character:FindFirstChild("HumanoidRootPart") end,10,"root part")
	local anchored, pivot = root.Anchored,character:GetPivot()
	ctx:Defer(function() if root.Parent then root.Anchored = anchored end end)
	root.Anchored = true
	ctx.State.Root = root; ctx.State.Origin = pivot.Position
end

return { Scenarios = {
	{ Id = "manual", Name = "Manual recording", Version = 1, Focus = "all", Controlled = false,
		Description = "Observe normal play. No controlled improvement claim.", Phases = { "play" } },
	{ Id = "stationary", Name = "Fixed current view", Version = 1, Focus = "all", Controlled = true,
		Description = "Measure a fixed character and camera view; the configured game lifecycle controls ambient activity.", Phases = { "view" },
		Prepare = hold, Validate = function(ctx)
			ctx:Check("character stayed fixed",ctx.State.Root.Parent ~= nil and (ctx.State.Root.Position-ctx.State.Origin).Magnitude < 0.1)
		end },
} }
