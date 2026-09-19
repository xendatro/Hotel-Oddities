local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.Config)
local Scope = require(script.Parent.Parent.Parent.Core.Scope)

local function prepareCamera(ctx)
	local camera = assert(workspace.CurrentCamera,"No camera")
	local oldType, oldFrame, oldFocus, oldFov = camera.CameraType,camera.CFrame,camera.Focus,camera.FieldOfView
	ctx:Defer(function()
		RunService:UnbindFromRenderStep("ProfilerHotelCamera")
		camera.CameraType = oldType; camera.CFrame = oldFrame; camera.Focus = oldFocus; camera.FieldOfView = oldFov
	end)
	camera.CameraType = Enum.CameraType.Scriptable; camera.FieldOfView = 70
	ctx.State.Camera = camera
	ctx.State.Look = Vector3.xAxis
	ctx.State.Signature = "hotel-route-v" .. Config.Version .. ":fov70"
	local character = assert(ctx.Player.Character,"No character")
	ctx.State.Root = assert(character:FindFirstChild("HumanoidRootPart"),"No root")
	RunService:BindToRenderStep("ProfilerHotelCamera",Enum.RenderPriority.Last.Value+10,function()
		local eye = ctx.State.Root.Position + Vector3.new(0,1.5,0)
		camera.CFrame = CFrame.lookAt(eye,eye+ctx.State.Look)
		camera.Focus = CFrame.new(eye+ctx.State.Look*20)
	end)
end

local function ground(ctx)
	local root = ctx.State.Root
	local filter = RaycastParams.new(); filter.FilterType = Enum.RaycastFilterType.Exclude
	filter.FilterDescendantsInstances = { ctx.Player.Character }
	return workspace:Raycast(root.Position+Vector3.yAxis*2,-Vector3.yAxis*12,filter)
end

local function phaseReady(ctx, phase)
	ctx.State.Look = if phase == "west" then -Vector3.xAxis else Vector3.xAxis
	ctx:WaitFor(function() return ground(ctx) end,15,"streamed floor under subject")
	ctx:Check("floor ready: " .. phase,true)
end

local function validateWorld(ctx)
	ctx:Check("character survived",ctx.Player.Character == ctx.State.Root.Parent
		and ctx.State.Root.Parent:FindFirstChildOfClass("Humanoid").Health > 0)
	ctx:Check("floor present at end",ground(ctx) ~= nil)
end

local function pagePrepare(ctx)
	local services = assert(ReplicatedStorage:FindFirstChild("Services"),"Hotel services absent")
	local interface = require(services.InterfaceService)
	local previous = interface:GetActive()
	ctx.State.Interface = interface
	ctx.State.Signature = "hotel-pages-v1"
	ctx:Defer(function() if previous and previous ~= "" then interface:Open(previous) else interface:Close() end end)
end

local openPage = Scope.Wrap("Hotel.UI.Open",function(interface,name)
	if name == "closed" then interface:Close() else interface:Open(name) end
end)

local function pagePhase(ctx,phase)
	local started = os.clock()
	openPage(ctx.State.Interface,phase)
	local guiNames = { Inventory = "InventoryGui", Index = "IndexGui" }
	if phase == "closed" then
		ctx:WaitFor(function() return (ctx.State.Interface:GetActive() or "") == "" end,5,"menus closed")
	else
		ctx:WaitFor(function()
			local gui = ctx.Player.PlayerGui:FindFirstChild(guiNames[phase])
			local design = gui and gui:FindFirstChild("Design")
			return gui and gui.Enabled and design and design.Visible and ctx.State.Interface:GetActive() == phase
		end,8,"visible " .. phase)
	end
	ctx:Check("page shown: " .. phase,true)
	ctx:Mark("page-ready",string.format("%s: %.3f ms elapsed including visibility wait",phase,(os.clock()-started)*1000))
end

return { Scenarios = {
	{ Id = "hotel.hallway", Name = "Hallway views", Version = 1, Controlled = true, Focus = "render",
		Description = "Fixed east/west hallway views. Resets ambient enemies in an isolated test server.",
		Phases = { "east","west" }, Prepare = prepareCamera, PreparePhase = phaseReady, Validate = validateWorld },
	{ Id = "hotel.streaming", Name = "Streaming traversal", Version = 1, Controlled = true, Focus = "all",
		Description = "Fixed 220-stud kinematic character route; tests streaming, not normal walking physics.",
		Phases = { "traverse" }, Prepare = prepareCamera, PreparePhase = phaseReady, Validate = validateWorld },
	{ Id = "hotel.enemy", Name = "Chaser encounter", Version = 1, Controlled = true, Focus = "all",
		Description = "One Chaser pursuing a fixed subject. Validates movement and pursuit; resets ambient enemies.",
		Phases = { "encounter" }, Prepare = prepareCamera, PreparePhase = phaseReady, Validate = validateWorld },
	{ Id = "hotel.ui", Name = "Inventory and index", Version = 1, Controlled = true, Focus = "memory",
		Description = "Measure visible Inventory, Index and closed pages; repeat to inspect retained memory.",
		Phases = { "Inventory","Index","closed" }, Prepare = pagePrepare, PreparePhase = pagePhase },
	{ Id = "hotel.reentry", Name = "Maze and lobby cycles", Version = 1, Controlled = true, Focus = "memory",
		Description = "Repeat warm-cache maze/lobby transfers; records readiness events and retained memory.",
		Phases = { "maze","lobby" }, Prepare = prepareCamera, PreparePhase = phaseReady, Validate = validateWorld },
} }
