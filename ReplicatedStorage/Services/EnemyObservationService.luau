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

--- The camera's view volume, reduced to what a sphere has to be tested against. Rebuilt per report
--- rather than per part, since it only moves when the viewport resizes or something animates the FOV.
type Frustum = {
	TanX: number, -- tangent of the half horizontal angle, and of the vertical one
	TanY: number,
	SideX: number, -- and the lengths that turn each side plane's equation into a distance
	SideY: number,
}

local function buildFrustum(camera: Camera): Frustum?
	local viewportSize = camera.ViewportSize
	if viewportSize.Y <= 0 then return nil end -- a frame or two at startup, before there is a screen

	local tanY = math.tan(math.rad(camera.FieldOfView / 2)) -- `FieldOfView` is the vertical one
	local tanX = tanY * viewportSize.X / viewportSize.Y
	return {
		TanX = tanX,
		TanY = tanY,
		SideX = math.sqrt(1 + tanX * tanX),
		SideY = math.sqrt(1 + tanY * tanY),
	}
end

--- Whether a sphere overlaps what the camera can see, against the near plane and all four sides.
---
--- Done in camera space rather than by projecting corners to the screen, because projection cannot
--- describe a thing that spans the camera plane: half its corners land behind the eye, where the
--- perspective divide is by a negative depth and the coordinates come back mirrored and enormous.
--- Discard those and the rest of the object is wherever the arithmetic left it -- which is how a rig
--- pressed against your shoulder reads as filling the screen while you look the other way, and how a
--- Weeping Angel ends up frozen by somebody facing away from it. A sphere has no such case: it is
--- either within reach of each plane or it is not, including when it swallows the camera whole.
local function intersectsFrustum(camera: Camera, frustum: Frustum, center: Vector3, radius: number): boolean
	local point = camera.CFrame:PointToObjectSpace(center) -- -Z is forward, so depth is `-point.Z`
	if point.Z > radius then return false end
	if math.abs(point.X) + frustum.TanX * point.Z > radius * frustum.SideX then return false end
	if math.abs(point.Y) + frustum.TanY * point.Z > radius * frustum.SideY then return false end
	return true
end

local function isObserved(camera: Camera, frustum: Frustum, character: Model, model: Model): boolean
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	if not intersectsFrustum(camera, frustum, boundsCFrame.Position, boundsSize.Magnitude / 2) then
		return false -- nothing of it is on screen, so no part of it can be either
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true

	local origin = camera.CFrame.Position
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart")
			and intersectsFrustum(camera, frustum, descendant.Position, descendant.Size.Magnitude / 2)
		then
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
	local frustum = camera and buildFrustum(camera)
	if camera and frustum then
		local observed = {}
		for _, model in CollectionService:GetTagged(OBSERVABLE_TAG) do
			if model:IsA("Model") and isObserved(camera, frustum, character, model) then
				table.insert(observed, model)
			end
		end
		-- Where this report was taken from and which way it was pointing, so the server can work out
		-- what else this player would see without having to guess at a camera it cannot reach. An enemy
		-- choosing somewhere to hide is asking exactly that question, and answering it off the
		-- character's own head is how you get a thing that hides behind furniture the camera is looking
		-- straight over. The direction is what turns "on screen" into "how far off the middle of the
		-- screen", which is the whole of what an Eye does with this.
		UpdateView:FireServer(observed, camera.CFrame.Position, camera.CFrame.LookVector)
	end
end)

return EnemyObservationService
