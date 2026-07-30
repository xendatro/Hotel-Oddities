--- Client-only presentation for Creep. Each viewer gets their own black wall behind every Creep,
--- positioned relative to that viewer so the hallway beyond it appears to have been consumed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)

local CREEP_TAG = "Creep"
local MINIMUM_DIRECTION = 1e-3

local CreepRenderService = {}

if not FLAGS.Enemies then
	return CreepRenderService
end

local localPlayer = Players.LocalPlayer

type Render = {
	RootPart: BasePart?,
	Backdrop: Part?,
}

local Creeps: { [Model]: Render } = {}

local function newBackdrop(): Part
	local backdrop = Instance.new("Part")
	backdrop.Name = "CreepBackdrop"
	backdrop.Size = CreepConfig.BackdropSize
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

local function track(model: Model): Render
	local render: Render = {
		RootPart = nil,
		Backdrop = nil,
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
	end)

	return render
end

TagService:Listen(CREEP_TAG, track, function(model: Instance, render: Render)
	if render.Backdrop then
		render.Backdrop:Destroy()
	end
	Creeps[model :: Model] = nil
end, workspace)

RunService.RenderStepped:Connect(function()
	local character = localPlayer.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not playerRoot then return end

	for _, render in Creeps do
		local rootPart, backdrop = render.RootPart, render.Backdrop
		if not rootPart or not backdrop then continue end

		local offset = rootPart.Position - playerRoot.Position
		local direction = Vector3.new(offset.X, 0, offset.Z)
		if direction.Magnitude < MINIMUM_DIRECTION then continue end
		direction = direction.Unit

		local position = rootPart.Position
			+ direction * CreepConfig.LightRange * CreepConfig.BackdropDistanceScale
		backdrop.CFrame = CFrame.lookAt(position, position - direction)
		backdrop.Transparency = 0
	end
end)

return CreepRenderService
