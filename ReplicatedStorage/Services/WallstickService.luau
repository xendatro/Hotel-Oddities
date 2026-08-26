local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WallstickService = {}

if not RunService:IsClient() then
	return WallstickService
end

local Replication = require(ReplicatedStorage.Classes.Wallstick.Replication)
local GravityCamera = require(ReplicatedStorage.Classes.Wallstick.GravityCamera)

local FALL_RESET_DISTANCE = -50

type Session = {
	Wallstick: any,
	Connections: { RBXScriptConnection },
}

type EnableOptions = {
	tilt: boolean?,
	spin: boolean?,
	surfaceNormal: Vector3?,
}

local ActiveSession: Session? = nil

local function ignoreCharacterParts(result: RaycastResult): boolean
	local hit = result.Instance :: BasePart
	local accessory = hit:FindFirstAncestorWhichIsA("Accessory")

	local character = (accessory or hit).Parent
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if character and humanoid then
		return not (accessory or humanoid:GetLimb(hit) ~= Enum.Limb.Unknown)
	end

	return true
end

function WallstickService.IsEnabled(): boolean
	return ActiveSession ~= nil
end

function WallstickService.Get(): any
	return ActiveSession and ActiveSession.Wallstick
end

function WallstickService.SetCameraUpVector(upVector: Vector3)
	GravityCamera.setUpVector(upVector)
end

function WallstickService.Disable()
	local session = ActiveSession
	if not session then return end
	ActiveSession = nil

	for _, connection in session.Connections do
		connection:Disconnect()
	end
	session.Wallstick:Destroy()
end

function WallstickService.Enable(options: EnableOptions?): any
	if ActiveSession then
		return ActiveSession.Wallstick
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end

	local wallstickModel = workspace:WaitForChild("Wallstick") :: Model
	local wallstickOrigin = wallstickModel:WaitForChild("Origin") :: BasePart

	local Wallstick = require(ReplicatedStorage.Classes.Wallstick) :: any
	local RaycastHelper = require(ReplicatedStorage.Classes.Wallstick.RaycastHelper) :: any

	local wallstick = Wallstick.new({
		parent = wallstickModel,
		origin = wallstickOrigin.CFrame,
		retainWorldVelocity = true,
		camera = {
			tilt = if options and options.tilt ~= nil then options.tilt else true,
			spin = if options and options.spin ~= nil then options.spin else true,
		},
	})

	local rayParams = RaycastHelper.params({
		filterType = Enum.RaycastFilterType.Exclude,
		instances = { character :: Instance },
	})
	local surfaceNormal = options and options.surfaceNormal
	if surfaceNormal and surfaceNormal.Magnitude > 0 then
		surfaceNormal = surfaceNormal.Unit
	else
		surfaceNormal = nil
	end

	local session: Session = {
		Wallstick = wallstick,
		Connections = {},
	}

	table.insert(session.Connections, RunService.PreSimulation:Connect(function(_dt)
		if wallstick:getFallDistance() < FALL_RESET_DISTANCE then
			wallstick:set(workspace.Terrain, Vector3.yAxis)
			return
		end

		local hipHeight = humanoid.HipHeight
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			hipHeight = 2
		end

		local rootCF = root.CFrame
		local result = RaycastHelper.raycast({
			origin = rootCF.Position,
			direction = -(hipHeight + root.Size.Y / 2 + 0.1) * rootCF.YVector,
			filter = ignoreCharacterParts,
			rayParams = rayParams,
		})

		if result then
			if surfaceNormal and result.Normal:Dot(surfaceNormal) < 0.9 then
				return
			end

			local stickPart = (result.Instance :: BasePart).AssemblyRootPart
			local stickNormal = stickPart.CFrame:VectorToObjectSpace(surfaceNormal or result.Normal)

			wallstick:setAndPivot(stickPart, stickNormal, result.Position)
		end
	end))

	table.insert(session.Connections, humanoid.Died:Connect(function()
		WallstickService.Disable()
	end))

	table.insert(session.Connections, Players.LocalPlayer.CharacterRemoving:Connect(function()
		WallstickService.Disable()
	end))

	ActiveSession = session
	return wallstick
end

Replication.listenClient()

return WallstickService
