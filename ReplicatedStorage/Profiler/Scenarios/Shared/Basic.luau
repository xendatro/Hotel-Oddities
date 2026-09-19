local RunService = game:GetService("RunService")
local function prepare(ctx)
	local camera = assert(workspace.CurrentCamera,"No camera")
	local oldType, oldFrame, oldFocus = camera.CameraType,camera.CFrame,camera.Focus
	ctx.State.Signature = "stationary:" .. tostring(oldFrame) .. ":" .. tostring(camera.FieldOfView)
	ctx:Defer(function()
		RunService:UnbindFromRenderStep("ProfilerCamera")
		camera.CameraType = oldType; camera.CFrame = oldFrame; camera.Focus = oldFocus
	end)
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep("ProfilerCamera",Enum.RenderPriority.Last.Value+10,function()
		camera.CFrame = oldFrame; camera.Focus = oldFocus
	end)
	ctx.State.Camera = camera; ctx.State.Frame = oldFrame
end

return { Scenarios = {
	{ Id = "manual", Name = "Manual recording", Version = 1, Focus = "all", Controlled = false,
		Description = "Observe normal play. No controlled improvement claim.", Phases = { "play" } },
	{ Id = "stationary", Name = "Fixed current view", Version = 1, Focus = "all", Controlled = true,
		Description = "Measure a fixed character and camera view; the configured game lifecycle controls ambient activity.", Phases = { "view" },
		Prepare = prepare, Validate = function(ctx)
			ctx:Check("camera stayed fixed",(ctx.State.Camera.CFrame.Position-ctx.State.Frame.Position).Magnitude < 0.1)
		end },
} }
