--- Client half of the `Ghost`. The server owns where a ghost truly is and publishes the leg it is
--- travelling; every client replays that same leg on its own frames, so the drift is drawn smoothly
--- instead of stepping forward each time a position replicates.
---
--- Nothing here is trusted with anything: the leg is read, never written, and the CFrames set on the
--- rig are local to this machine -- the root is anchored and server-owned, so these writes go no
--- further than the screen. A client that lied to itself about where a ghost is would see a ghost
--- somewhere it is not, which is the whole extent of the damage available.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local GhostMotion = require(ReplicatedStorage.Modules.GhostMotion)
local TagService = require(ReplicatedStorage.Services.TagService)

local GHOST_TAG = "Ghost"
local TAU = math.pi * 2

local GhostRenderService = {}

if not FLAGS.Enemies then
	return GhostRenderService
end

type Render = {
	RootPart: BasePart?,
	Leg: GhostMotion.Leg?,
	Phase: number,
	Connection: RBXScriptConnection?,
}

local Ghosts: { [Model]: Render } = {}

local function track(model: Model): Render
	local render: Render = {
		RootPart = nil,
		Leg = GhostMotion.Read(model),
		Phase = math.random() * TAU,
		Connection = nil,
	}
	Ghosts[model] = render

	render.Connection = model.AttributeChanged:Connect(function(attribute: string)
		if attribute == GhostMotion.LegAttribute then
			render.Leg = GhostMotion.Read(model)
		end
	end)

	-- Off the tag callback: a rig whose root has not replicated yet must not hold up every other
	-- listener behind it. Until it lands the ghost simply renders where the server put it.
	task.spawn(function()
		local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart
		if Ghosts[model] == render then
			render.RootPart = rootPart
		end
	end)

	return render
end

TagService:Listen(GHOST_TAG, track, function(model: Instance, render: Render)
	local connection = render.Connection :: RBXScriptConnection
	connection:Disconnect()
	Ghosts[model :: Model] = nil
end, workspace)

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()

	for _, render in Ghosts do
		local rootPart, leg = render.RootPart, render.Leg
		if rootPart and leg then
			rootPart.CFrame = GhostMotion.Evaluate(leg, now) + GhostMotion.Bob(clock, render.Phase)
		end
	end
end)

return GhostRenderService
