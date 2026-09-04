local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CameraFovService = {}

if not RunService:IsClient() then
	return CameraFovService
end

local BIND_NAME = "CameraFovOffsets"
local LOCK_BIND_NAME = "CameraFovLock"

local Offsets: { [string]: number } = {}
local total = 0
local bound = false
local lastCamera: Camera? = nil
local lastApplied = 0
local lockedFov: number? = nil

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
	if lockedFov then
		lastApplied = 0
		camera.FieldOfView = lockedFov
		return
	end

	local base = camera.FieldOfView - lastApplied
	local written = math.clamp(base + total, 1, 120)
	lastApplied = written - base
	camera.FieldOfView = written
end

local function renderLock()
	local camera = workspace.CurrentCamera
	if camera ~= lastCamera then
		restoreCamera()
		lastCamera = camera
	end
	if camera and lockedFov then
		camera.FieldOfView = lockedFov
	end
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

function CameraFovService:SetLocked(locked: boolean)
	if locked then
		if lockedFov then return end

		local camera = workspace.CurrentCamera
		if not camera then return end
		if camera ~= lastCamera then
			restoreCamera()
			lastCamera = camera
		end
		lockedFov = math.clamp(camera.FieldOfView - lastApplied, 1, 120)
		camera.FieldOfView = lockedFov
		RunService:BindToRenderStep(LOCK_BIND_NAME, Enum.RenderPriority.Camera.Value + 6, renderLock)
	else
		if not lockedFov then return end

		lockedFov = nil
		RunService:UnbindFromRenderStep(LOCK_BIND_NAME)
		if bound then render() end
	end
end

local ActiveTweens: { [string]: { Tween: Tween, Value: NumberValue, Connection: RBXScriptConnection } } = {}

function CameraFovService:Reset()
	for name, entry in ActiveTweens do
		ActiveTweens[name] = nil
		entry.Tween:Cancel()
		entry.Connection:Disconnect()
		entry.Value:Destroy()
	end

	table.clear(Offsets)
	total = 0

	if lockedFov then
		lockedFov = nil
		RunService:UnbindFromRenderStep(LOCK_BIND_NAME)
	end

	if bound then
		setBound(false)
	else
		restoreCamera()
	end
end

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

local localPlayer = Players.LocalPlayer
local deathConnection: RBXScriptConnection? = nil

local function bindCharacter(character: Model)
	if deathConnection then
		deathConnection:Disconnect()
		deathConnection = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid") :: Humanoid
	end
	deathConnection = humanoid.Died:Connect(function()
		CameraFovService:Reset()
	end)
end

localPlayer.CharacterAdded:Connect(bindCharacter)
localPlayer.CharacterRemoving:Connect(function()
	if deathConnection then
		deathConnection:Disconnect()
		deathConnection = nil
	end
	CameraFovService:Reset()
end)

if localPlayer.Character then
	task.spawn(bindCharacter, localPlayer.Character)
end

return CameraFovService
