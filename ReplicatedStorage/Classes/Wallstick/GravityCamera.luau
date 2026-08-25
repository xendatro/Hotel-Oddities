--!strict

local Players = game:GetService("Players")

local playerModuleScript = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
local playerModuleObject = require(playerModuleScript) :: any
local cameraModuleObject = playerModuleObject:GetCameras() :: any
local controlModuleObject = playerModuleObject:GetControls() :: any

if not cameraModuleObject.GetUpVector then
	local applyModifier = require(script.Parent:WaitForChild("GravityCameraModifier")) :: (any) -> ()
	local ok, err = pcall(applyModifier, playerModuleScript)
	if not ok then
		warn(`Wallstick GravityCamera: failed to patch the live PlayerModule ({err}); camera tilt/spin disabled`)
	end
end

local GravityCamera = {}

function GravityCamera.getUpVector(): Vector3
	if cameraModuleObject.GetUpVector then
		return cameraModuleObject:GetUpVector()
	end
	return Vector3.yAxis
end

function GravityCamera.setUpVector(target: Vector3)
	if cameraModuleObject.SetTargetUpVector then
		cameraModuleObject:SetTargetUpVector(target)
	end
end

function GravityCamera.getSpinPart(): BasePart
	if cameraModuleObject.GetSpinPart then
		return cameraModuleObject:GetSpinPart()
	end
	return workspace.Terrain
end

function GravityCamera.setSpinPart(part: BasePart)
	if cameraModuleObject.SetSpinPart then
		cameraModuleObject:SetSpinPart(part)
	end
end

function GravityCamera.getRotationType(): Enum.RotationType
	if cameraModuleObject.GetRotationType then
		return cameraModuleObject:GetRotationType()
	end
	return UserSettings():GetService("UserGameSettings").RotationType
end

function GravityCamera.getMoveVector(cameraCF: CFrame, inputMove: Vector3?): Vector3
	local move = inputMove or controlModuleObject:GetMoveVector() :: Vector3
	local _, _, _, r00, r01, r02, _, r11, r12, _, _, r22 = cameraCF:GetComponents()

	local c, s
	local q = math.sign(r11)

	if r12 < 1 and r12 > -1 then
		c = r22
		s = r02
	else
		c = r00
		s = -r01 * math.sign(r12)
	end

	local norm = math.sqrt(c * c + s * s)
	local x = (c * move.X * q + s * move.Z) / norm
	local z = (c * move.Z - s * move.X * q) / norm

	return Vector3.new(x, 0, z)
end

return GravityCamera
