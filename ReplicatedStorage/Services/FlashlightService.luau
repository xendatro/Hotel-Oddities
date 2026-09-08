local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FlashlightConfig = require(ReplicatedStorage.Configs.FlashlightConfig)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local FlashlightService = {}

if not RunService:IsClient() then
	return FlashlightService
end

type Rig = {
	Tool: Tool,
	IsLocal: boolean,
	Part: BasePart?,
	Lights: { SpotLight },
}

local TAG = ToolConfigs.Flashlight.Tag
local BIND_NAME = "FlashlightBeam"
local PART_NAME = "FlashlightBeamOrigin"

local player = Players.LocalPlayer

local tracked: { [Tool]: { RBXScriptConnection } } = {}
local rigs: { [Tool]: Rig } = {}
local localRig: Rig? = nil

local function applyCone(light: SpotLight, cone: FlashlightConfig.Cone)
	light.Angle = cone.Angle
	light.Range = cone.Range
	light.Brightness = cone.Brightness * FlashlightConfig.Master
	light.Shadows = cone.Shadows
	light.Color = FlashlightConfig.Color
end

local function buildLights(parent: Instance, face: Enum.NormalId): { SpotLight }
	local lights = {}
	for index, cone in FlashlightConfig.Cones do
		local light = Instance.new("SpotLight")
		light.Name = `FlashlightCone{index}`
		light.Face = face
		light.Enabled = true
		applyCone(light, cone)
		light.Parent = parent
		table.insert(lights, light)
	end
	return lights
end

local function handleOf(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	return (handle and handle:IsA("BasePart")) and handle or nil
end

local function faceOf(tool: Tool): Enum.NormalId
	local handle = handleOf(tool)
	local authored = handle and handle:FindFirstChildWhichIsA("SpotLight")
	return authored and authored.Face or Enum.NormalId.Front
end

local function characterOf(tool: Tool): Model?
	local parent = tool.Parent
	if not parent or not parent:IsA("Model") then return nil end
	if not parent:FindFirstChildOfClass("Humanoid") then return nil end
	return parent
end

local function shouldLight(tool: Tool): boolean
	if tool:GetAttribute(FlashlightConfig.Attribute) ~= true then return false end
	return characterOf(tool) ~= nil
end

local function stepLocal()
	local rig = localRig
	local part = rig and rig.Part
	local camera = Workspace.CurrentCamera
	if not part or not camera then return end

	part.CFrame = camera.CFrame * CFrame.new(FlashlightConfig.CameraOffset)
end

local function setStepping(active: boolean)
	if active then
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, stepLocal)
	else
		RunService:UnbindFromRenderStep(BIND_NAME)
	end
end

local function destroyRig(tool: Tool)
	local rig = rigs[tool]
	if not rig then return end

	rigs[tool] = nil
	for _, light in rig.Lights do
		light:Destroy()
	end
	if rig.Part then
		rig.Part:Destroy()
	end
	if rig == localRig then
		localRig = nil
		setStepping(false)
	end
end

local function createLocalRig(tool: Tool): Rig
	local part = Instance.new("Part")
	part.Name = PART_NAME
	part.Size = Vector3.one * 0.05
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Locked = true
	part.CFrame = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or CFrame.identity
	part.Parent = Workspace

	local rig: Rig = {
		Tool = tool,
		IsLocal = true,
		Part = part,
		Lights = buildLights(part, Enum.NormalId.Front),
	}
	localRig = rig
	setStepping(true)
	stepLocal()
	return rig
end

local function createRig(tool: Tool): Rig?
	if Players:GetPlayerFromCharacter(tool.Parent) == player then
		return createLocalRig(tool)
	end

	local handle = handleOf(tool)
	if not handle then return nil end

	return {
		Tool = tool,
		IsLocal = false,
		Part = nil,
		Lights = buildLights(handle, faceOf(tool)),
	}
end

local function refresh(tool: Tool)
	if not shouldLight(tool) then
		destroyRig(tool)
		return
	end
	if rigs[tool] then return end

	local rig = createRig(tool)
	if rig then
		rigs[tool] = rig
	end
end

local function untrack(tool: Tool)
	local connections = tracked[tool]
	if not connections then return end

	tracked[tool] = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	destroyRig(tool)
end

local function track(instance: Instance)
	if not instance:IsA("Tool") or tracked[instance] then return end

	local tool = instance :: Tool
	local authored = handleOf(tool) and (handleOf(tool) :: BasePart):FindFirstChildWhichIsA("SpotLight")
	if authored then
		authored.Enabled = false
	end

	tracked[tool] = {
		tool:GetAttributeChangedSignal(FlashlightConfig.Attribute):Connect(function()
			refresh(tool)
		end),
		tool.AncestryChanged:Connect(function()
			refresh(tool)
		end),
	}
	refresh(tool)
end

function FlashlightService:Refresh()
	for tool, rig in rigs do
		if rig.IsLocal then
			stepLocal()
		end
		for index, light in rig.Lights do
			local cone = FlashlightConfig.Cones[index]
			if cone then
				applyCone(light, cone)
			end
		end
		if #rig.Lights ~= #FlashlightConfig.Cones then
			destroyRig(tool)
			refresh(tool)
		end
	end
end

function FlashlightService:IsLocalLit(): boolean
	return localRig ~= nil
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
	if instance:IsA("Tool") then
		untrack(instance :: Tool)
	end
end)

for _, instance in CollectionService:GetTagged(TAG) do
	track(instance)
end

return FlashlightService
