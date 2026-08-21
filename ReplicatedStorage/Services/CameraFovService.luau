local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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
	local written = math.clamp(base + total, 1, 120)
	lastApplied = written - base
	camera.FieldOfView = written
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

function CameraFovService:GetOffset(): number
	return total
end

local ActiveTweens: { [string]: { Tween: Tween, Value: NumberValue, Connection: RBXScriptConnection } } = {}

function CameraFovService:TweenOffset(name: string, degrees: number, tweenInfo: TweenInfo)
	local existing = ActiveTweens[name]
	if existing then
		ActiveTweens[name] = nil
		existing.Tween:Cancel()
		existing.Connection:Disconnect()
		existing.Value:Destroy()
	end

	local value = Instance.new("NumberValue")
	value.Value = Offsets[name] or 0
	local connection = value.Changed:Connect(function(current: number)
		self:SetOffset(name, current)
	end)

	local tween = TweenService:Create(value, tweenInfo, { Value = degrees })
	local entry = { Tween = tween, Value = value, Connection = connection }
	ActiveTweens[name] = entry
	tween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if ActiveTweens[name] == entry then
			ActiveTweens[name] = nil
			connection:Disconnect()
			value:Destroy()
			if playbackState == Enum.PlaybackState.Completed then
				self:SetOffset(name, degrees)
			end
		end
	end)
	tween:Play()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if bound then render() end
end)

return CameraFovService
