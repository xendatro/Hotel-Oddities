local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Aim = require(ReplicatedStorage.Modules.Aim)
local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local Hallways = require(ReplicatedStorage.Modules.Hallways)
local TagService = require(ReplicatedStorage.Services.TagService)

local CREEP_TAG = "Creep"
local MINIMUM_DIRECTION = 1e-3
local SIDE_DEADZONE = 4
local WIDTH_PROBES = { -2, -1, 0.5 }
local LENGTH_PROBES = { 0, 8, -8 }

local CreepRenderService = {}

if not FLAGS.Enemies then
	return CreepRenderService
end

local localPlayer = Players.LocalPlayer

type Render = {
	RootPart: BasePart?,
	Backdrop: Part?,
	Hallway: Hallways.Hallway?,
	Height: number,
	Side: number,
	Aimed: boolean,
}

local Creeps: { [Model]: Render } = {}

local function newBackdrop(): Part
	local backdrop = Instance.new("Part")
	backdrop.Name = "CreepBackdrop"
	backdrop.Size = CreepConfig.BackdropFallbackSize
	backdrop.Color = Color3.new(0, 0, 0)
	backdrop.Material = Enum.Material.Neon
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanQuery = false
	backdrop.CanTouch = false
	backdrop.CastShadow = false
	backdrop.Transparency = 1
	return backdrop
end

local function measureHeight(hallway: Hallways.Hallway, position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true

	local search = CreepConfig.BackdropCeilingSearch
	local tallest = 0

	local function consider(result: RaycastResult?)
		local height = if result then result.Position.Y - hallway.FloorY else 0
		if height > tallest then
			tallest = height
		end
	end

	local floor = Vector3.new(position.X, hallway.FloorY, position.Z)
	consider(workspace:Raycast(floor + Vector3.yAxis, Vector3.yAxis * search, params))

	local creepAlong = Hallways.Along(hallway, position)
	for _, side in { 1, -1 } do
		for _, width in WIDTH_PROBES do
			for _, length in LENGTH_PROBES do
				local along = math.clamp(creepAlong + length, -hallway.HalfLength, hallway.HalfLength)
				local edge = Hallways.PointAt(hallway, along)
					+ hallway.Across * side * (hallway.HalfWidth + width)
					+ Vector3.yAxis * search
				consider(workspace:Raycast(edge, Vector3.yAxis * -search * 2, params))
			end
		end
	end

	if tallest < CreepConfig.BackdropMinimumHeight then
		return CreepConfig.BackdropHeight
	end
	return tallest + CreepConfig.BackdropHeightOverlap
end

local function track(model: Model): Render
	local render: Render = {
		RootPart = nil,
		Backdrop = nil,
		Hallway = nil,
		Height = CreepConfig.BackdropHeight,
		Side = 0,
		Aimed = false,
	}
	Creeps[model] = render

	task.spawn(function()
		local rootPart = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
		while not rootPart and Creeps[model] == render do
			task.wait()
			rootPart = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
		end
		if Creeps[model] ~= render then return end

		local backdrop = newBackdrop()
		backdrop.Parent = workspace
		render.RootPart = rootPart
		render.Backdrop = backdrop
		local hallway = Hallways.At((rootPart :: BasePart).Position)
		render.Hallway = hallway
		if hallway then
			render.Height = measureHeight(hallway, (rootPart :: BasePart).Position, { model, backdrop })
		end
	end)

	return render
end

TagService:Listen(CREEP_TAG, track, function(model: Instance, render: Render)
	if render.Backdrop then
		render.Backdrop:Destroy()
	end
	Creeps[model :: Model] = nil
end, workspace)

local function placeInHallway(render: Render, backdrop: Part, creepPosition: Vector3, eye: Vector3): boolean
	local hallway = render.Hallway :: Hallways.Hallway
	local creepAlong = Hallways.Along(hallway, creepPosition)
	local difference = creepAlong - Hallways.Along(hallway, eye)
	if render.Side == 0 or math.abs(difference) > SIDE_DEADZONE then
		render.Side = if difference >= 0 then 1 else -1
	end

	local safeLimit = hallway.HalfLength - CreepConfig.BackdropThickness / 2
	if safeLimit <= 0 then return false end
	local preferredLimit = math.min(
		hallway.HalfLength - CreepConfig.BackdropEndMargin,
		safeLimit
	)
	local limit = math.max(preferredLimit, 0)

	local along = math.clamp(creepAlong + render.Side * CreepConfig.BackdropDistance, -limit, limit)
	if (along - creepAlong) * render.Side < CreepConfig.BackdropMinimumDistance then
		along = math.clamp(
			creepAlong + render.Side * CreepConfig.BackdropMinimumDistance,
			-safeLimit,
			safeLimit
		)
	end
	if (along - creepAlong) * render.Side <= 0 then return false end

	local position = Hallways.PointAt(hallway, along) + Vector3.yAxis * render.Height / 2
	backdrop.Size = Vector3.new(
		hallway.HalfWidth * 2,
		render.Height,
		CreepConfig.BackdropThickness
	)
	backdrop.CFrame = CFrame.lookAt(position, position - hallway.Axis * render.Side)
	return true
end

local function placeFacingViewer(backdrop: Part, creepPosition: Vector3, eye: Vector3): boolean
	local offset = creepPosition - eye
	local direction = Vector3.new(offset.X, 0, offset.Z)
	if direction.Magnitude < MINIMUM_DIRECTION then return false end
	direction = direction.Unit

	local position = creepPosition + direction * CreepConfig.BackdropDistance
	backdrop.Size = CreepConfig.BackdropFallbackSize
	backdrop.CFrame = CFrame.lookAt(position, position - direction)
	return true
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local eye = camera.CFrame.Position

	for _, render in Creeps do
		local rootPart, backdrop = render.RootPart, render.Backdrop
		if not rootPart or not backdrop then continue end

		local position = rootPart.Position
		local offset = eye - position
		if offset.Magnitude < MINIMUM_DIRECTION then continue end

		local goal = Aim.Toward(position, eye)
		local rotation = if render.Aimed
			then Aim.Ease(rootPart.CFrame.Rotation, goal, CreepConfig.TurnRate, deltaTime)
			else goal
		render.Aimed = true
		rootPart.CFrame = rotation + position

		local placed = if render.Hallway
			then placeInHallway(render, backdrop, position, eye)
			else placeFacingViewer(backdrop, position, eye)
		backdrop.Transparency = if placed then 0 else 1
	end
end)

return CreepRenderService
