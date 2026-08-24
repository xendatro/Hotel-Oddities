local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShakeService = {}
ShakeService.SustainedShakes = {}

if not RunService:IsClient() then
	return ShakeService
end

local CameraShaker = require(ReplicatedStorage.Classes.CameraShaker)
local PerfLog = require(ReplicatedStorage.Modules.PerfLog)

local function ShakeCamera(shakeCf)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CFrame = camera.CFrame * shakeCf
	end
end

local renderPriority = Enum.RenderPriority.Camera.Value + 1
local camShake = CameraShaker.new(renderPriority, ShakeCamera)

local Preset = {
	Scare = function()
		local scare do
			scare = CameraShaker.CameraShakeInstance.new(3, 20, 0, 1.5)
			scare.PositionInfluence = Vector3.new(1, 1, 1)
			scare.RotationInfluence = Vector3.new(1, 1, 1)
		end
		return scare
	end,
	Small = function()
		local small do
			small = CameraShaker.CameraShakeInstance.new(1, 5, 0, 1.5)
			small.PositionInfluence = Vector3.new(0.1, 0.1, 0.1)
			small.RotationInfluence = Vector3.new(1, 1, 1)
		end
		return small
	end,
	Jumpscare = function()
		local scare do
			scare = CameraShaker.CameraShakeInstance.new(2, 50, 0, 1.5)
			scare.PositionInfluence = Vector3.new(0.3, 0.3, 0)
			scare.RotationInfluence = Vector3.new(0.5, 0.5, 0.5)
		end
		return scare
	end,
	Slam = function()
		local slam do
			slam = CameraShaker.CameraShakeInstance.new(6, 45, 0, 0.7)
			slam.PositionInfluence = Vector3.new(0.6, 0.6, 0.3)
			slam.RotationInfluence = Vector3.new(1.6, 1.6, 0.8)
		end
		return slam
	end,
	Jolt = function()
		local jolt do
			jolt = CameraShaker.CameraShakeInstance.new(3.2, 32, 0, 0.5)
			jolt.PositionInfluence = Vector3.new(0.35, 0.35, 0.15)
			jolt.RotationInfluence = Vector3.new(1, 1, 0.5)
		end
		return jolt
	end,
}

camShake:Start()

type ShakeData = {
	ID: string,
	ShakeType: "Once" | "Sustained",
	Preset: string
}

export type RumbleParams = {
	Roughness: number?,
	MagnitudeScale: number?,
	PositionInfluence: Vector3?,
	RotationInfluence: Vector3?,
}

local Rumble = {}
Rumble.__index = Rumble

function Rumble.new(start: number, params: RumbleParams?)
	local self = setmetatable({}, Rumble)

	self.Value = start
	self.MagnitudeScale = (params and params.MagnitudeScale) or 5
	self.FixedInfluence = params ~= nil
	local rumble do
		rumble = CameraShaker.CameraShakeInstance.new(start * self.MagnitudeScale, (params and params.Roughness) or 20, 0, 1.5)
		rumble.PositionInfluence = (params and params.PositionInfluence) or Vector3.new(0.1, 0.1, 0.1)
		rumble.RotationInfluence = (params and params.RotationInfluence) or Vector3.new(0.1, 0.1, 0.1)
	end
	self.Shake = rumble

	self:Start()

	return self
end

function Rumble:Start()
	camShake:ShakeSustain(self.Shake)
end

function Rumble:AdjustValue(newValue: number)
	self.Value = newValue
	self.Shake.Magnitude = newValue * self.MagnitudeScale
	if not self.FixedInfluence then
		self.Shake.PositionInfluence = Vector3.new(newValue / 2, newValue / 2, newValue / 2)
	end
end

function Rumble:Stop(fadeOutTime: number?)
	self.Shake:StartFadeOut(fadeOutTime or 0)
end

local function shakeOnce(preset: string)
	camShake:Shake(Preset[preset]())
end

local function shakeSustained(id: string, preset: string)
	ShakeService.SustainedShakes[id] = camShake:ShakeSustain(Preset[preset]())
end

function ShakeService:Create(shakeData: ShakeData)
	PerfLog.Log("Shake", `{shakeData.Preset} {shakeData.ShakeType}`)
	if shakeData.ShakeType == "Once" then
		shakeOnce(shakeData.Preset)
	elseif shakeData.ShakeType == "Sustained" then
		shakeSustained(shakeData.ID, shakeData.Preset)
	end
end

function ShakeService:Delete(ID: string)
	local instance = ShakeService.SustainedShakes[ID]
	if instance then
		instance:StartFadeOut(0)
		ShakeService.SustainedShakes[ID] = nil
		PerfLog.Log("Shake", `sustained {ID} stop`)
	end
end

function ShakeService:CreateDynamicRumble(startValue: number, params: RumbleParams?)
	PerfLog.Log("Shake", "rumble start")
	return Rumble.new(startValue, params)
end

return ShakeService
