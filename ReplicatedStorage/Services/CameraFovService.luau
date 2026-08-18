--- One place for anything that wants to widen or narrow the camera without owning its field of
--- view. Callers name their contribution and the offsets add up, so a sprint and a speed drink at
--- the same time do not fight over one number.
---
--- The total is removed before it is re-applied every frame, which is what lets this compose with
--- camera scripts and interface tweens that pick their own base field of view: whatever they wrote
--- since the last frame survives, and only this service's own share is replaced.

local RunService = game:GetService("RunService")

local CameraFovService = {}

if not RunService:IsClient() then
	return CameraFovService
end

local BIND_NAME = "CameraFovOffsets"

local Offsets: { [string]: number } = {}
local total = 0
local bound = false
local lastCamera: Camera? = nil
local lastApplied = 0

local function restoreCamera()
	if lastCamera and lastCamera.Parent and lastApplied ~= 0 then
		lastCamera.FieldOfView -= lastApplied
	end
	lastCamera = nil
	lastApplied = 0
end

local function render()
	local camera = workspace.CurrentCamera
	if camera ~= lastCamera then
		restoreCamera()
		lastCamera = camera
	end
	if not camera then return end

	local base = camera.FieldOfView - lastApplied
	lastApplied = total
	camera.FieldOfView = base + lastApplied
end

local function setBound(value: boolean)
	if bound == value then return end
	bound = value
	if value then
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, render)
	else
		RunService:UnbindFromRenderStep(BIND_NAME)
		restoreCamera()
	end
end

--- Sets `name`'s contribution in degrees, replacing whatever it was before. Zero removes it. This
--- is instant: a caller that wants its offset to ease in owns that easing and keeps calling.
function CameraFovService:SetOffset(name: string, degrees: number)
	local value = if math.abs(degrees) < 1e-3 then nil else degrees
	if Offsets[name] == value then return end

	Offsets[name] = value
	total = 0
	for _, offset in Offsets do
		total += offset
	end
	setBound(next(Offsets) ~= nil)
end

--- What every contribution currently adds up to, in degrees.
function CameraFovService:GetOffset(): number
	return total
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if bound then render() end
end)

return CameraFovService
