local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local REPORT_INTERVAL = 0.05
-- Carried by the enemies that react to being seen, and only those: the report costs a raycast per
-- visible part, so an enemy that would ignore the answer is not worth asking about.
local OBSERVABLE_TAG = "Observable"

local EnemyObservationService = {}

if not FLAGS.Enemies then
	return EnemyObservationService
end

local UpdateView = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("UpdateView") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local accumulator = REPORT_INTERVAL

local function intersectsViewport(camera: Camera, part: BasePart): boolean
	local halfSize = part.Size / 2
	local viewportSize = camera.ViewportSize
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local hasPointInFront = false

	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(
					halfSize.X * x,
					halfSize.Y * y,
					halfSize.Z * z
				))
				local screenPoint = camera:WorldToViewportPoint(corner)
				if screenPoint.Z > 0 then
					hasPointInFront = true
					minX = math.min(minX, screenPoint.X)
					minY = math.min(minY, screenPoint.Y)
					maxX = math.max(maxX, screenPoint.X)
					maxY = math.max(maxY, screenPoint.Y)
				end
			end
		end
	end

	return hasPointInFront
		and maxX >= 0
		and maxY >= 0
		and minX <= viewportSize.X
		and minY <= viewportSize.Y
end

local function isObserved(camera: Camera, character: Model, model: Model): boolean
	local boundsCFrame = model:GetBoundingBox()
	local offset = boundsCFrame.Position - camera.CFrame.Position
	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	local lookVector = camera.CFrame.LookVector
	local horizontalLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if horizontalOffset.Magnitude < 1e-3
		or horizontalLook.Magnitude < 1e-3
		or horizontalOffset.Unit:Dot(horizontalLook.Unit) <= 0
	then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true

	local origin = camera.CFrame.Position
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and intersectsViewport(camera, descendant) then
			local direction = descendant.Position - origin
			if direction.Magnitude < 1e-3 then
				return true
			end

			local result = workspace:Raycast(origin, direction, params)
			if result == nil or result.Instance:IsDescendantOf(model) then
				return true
			end
		end
	end
	return false
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	local character = localPlayer.Character
	if not character then return end

	accumulator += deltaTime
	if accumulator < REPORT_INTERVAL then return end
	accumulator = 0

	local camera = workspace.CurrentCamera
	if camera then
		local observed = {}
		for _, model in CollectionService:GetTagged(OBSERVABLE_TAG) do
			if model:IsA("Model") and isObserved(camera, character, model) then
				table.insert(observed, model)
			end
		end
		-- Where this report was taken from and which way it was pointing, so the server can work out
		-- what else this player would see without having to guess at a camera it cannot reach. An enemy
		-- choosing somewhere to hide is asking exactly that question, and answering it off the
		-- character's own head is how you get a thing that hides behind furniture the camera is looking
		-- straight over. The direction is what turns "on screen" into "how far off the middle of the
		-- screen", which is the whole of what an Eyes does with this.
		UpdateView:FireServer(observed, camera.CFrame.Position, camera.CFrame.LookVector)
	end
end)

return EnemyObservationService
