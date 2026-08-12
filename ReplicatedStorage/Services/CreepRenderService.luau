--- Client-only presentation for Creep: the pair of lights turning to face whoever is looking, and the
--- black wall behind them that makes the corridor past them look like it stops.
---
--- Both are per viewer and neither replicates. The Creep is one anchored, server-owned part, so the
--- CFrame written on it here goes no further than this screen -- which is the only way two players in
--- the same hallway can both be looked at, and the only way each of them can have the corridor
--- blacked out behind it from where *they* are standing.
---
--- The wall is laid across the hallway the Creep is standing in rather than turned square on to the
--- viewer, and is kept inside that hallway's own length and width. Turned to face the viewer it works
--- from down the corridor and nowhere else: step to one side and the same slab is a black wall
--- standing across the hotel, or worse, standing in the next hallway over where nothing is meant to
--- be dark at all. Its size and its distance are what the corridor allows, not what looks best from
--- one spot.

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
--- How far past the Creep, down the hallway, a viewer must be before the far side of it changes. A
--- viewer standing level with it has no "behind" to speak of, and without this the wall would flip
--- from one side to the other while they shuffled about.
local SIDE_DEADZONE = 4
--- Where the height probes go looking for the top of the corridor: across it, and up and down its
--- length from the Creep. Several of them, and the tallest hit wins.
---
--- A hotel corridor is not a bare box, and one probe is a coin toss in it. Skirting boards and picture
--- rails stand proud of the wall they are nailed to, and the floor is authored wider than the walls
--- standing on it, so a single ray dropped beside a wall misses the wall and lands on trim, or on the
--- floor it started over -- which between them is most of the places a Creep can stand in this hotel.
--- The wall then comes out ankle high and is a black kerb laid across the hallway rather than
--- something the corridor appears to stop at. Nothing hung on a wall reaches higher than the wall does
--- and nothing hangs on every wall at once, which is what makes the tallest of a handful of probes the
--- corridor and everything fixed to it lose.
local WIDTH_PROBES = { -2, -1, 0.5 } -- studs from the corridor's edge, negative being inside it
local LENGTH_PROBES = { 0, 8, -8 } -- and how far along it from the Creep, kept inside its ends

local CreepRenderService = {}

if not FLAGS.Enemies then
	return CreepRenderService
end

local localPlayer = Players.LocalPlayer

type Render = {
	RootPart: BasePart?,
	Backdrop: Part?,
	Hallway: Hallways.Hallway?, -- nil where it is standing somewhere the corridor graph does not know
	Height: number, -- what this stretch of corridor measured, floor to ceiling or floor to wall top
	Side: number, -- which way down that hallway is currently the far side of it, or 0 before one is
	Aimed: boolean, -- whether it has been turned to this camera yet, which the first turn skips ahead
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

--- How tall the wall has to be to close this stretch of corridor off: to the ceiling where there is
--- one, and to the top of the corridor's own walls where the hall is open to the sky. Both come out
--- of the map rather than out of the config, so a wall is never taller than what is around it.
---
--- Measured once, from where the Creep is standing. A corridor is one height for its whole length in
--- this hotel, and a Creep is a few seconds of a player's evening -- there is nothing here worth two
--- dozen raycasts a frame.
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

	-- Straight up for a ceiling where there is one ...
	local floor = Vector3.new(position.X, hallway.FloorY, position.Z)
	consider(workspace:Raycast(floor + Vector3.yAxis, Vector3.yAxis * search, params))

	-- ... and down onto the corridor's own side walls, which is the answer where it is open above and
	-- the correction where that ceiling ray came down on a picture rail. Kept inside the hallway's own
	-- ends, so a Creep standing near a junction measures its corridor and not the one crossing it.
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

	-- Everything the probes found was ankle height or nothing at all: whatever this is, it is not the
	-- corridor, and a wall built to it would be a doorstep. Cover the hallway instead.
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

	-- The tag may replicate one frame before the model's single part. Resolve it off the callback so
	-- one incomplete Creep cannot hold up every other tag listener.
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
		-- Read once, from where the server put it: a Creep never moves, and the rotation written on it
		-- every frame after this would make asking again an answer about this service's own work.
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

--- Lays the wall across the hallway, on the far side of the Creep from `eye`. Long corridors keep
--- the configured end margin; short corridors use the nearest point that still keeps the wall
--- inside their ends.
local function placeInHallway(render: Render, backdrop: Part, creepPosition: Vector3, eye: Vector3): boolean
	local hallway = render.Hallway :: Hallways.Hallway
	local creepAlong = Hallways.Along(hallway, creepPosition)
	local difference = creepAlong - Hallways.Along(hallway, eye)
	if render.Side == 0 or math.abs(difference) > SIDE_DEADZONE then
		render.Side = if difference >= 0 then 1 else -1
	end

	-- Everything past this point is one number: how far down the corridor from its middle the wall
	-- goes. Sizing and squareness follow from the hallway itself.
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

--- What it does with a Creep that is not in any corridor: square on to the viewer, far enough back to
--- sit behind it, and big enough to cover whatever room it has been put in.
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

		-- The two lights sit either side of the part's own centre, so which way it is turned is the
		-- difference between a pair of eyes and one light with another hidden behind it.
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
