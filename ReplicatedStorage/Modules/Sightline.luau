--- Whether a camera can see a model, answered against the geometry as it stands right now. Pure in
--- the sense that matters: it reads the world and writes nothing to it, so the same question can be
--- asked several times a frame by callers that disagree about what to do with the answer.
---
--- Lifted out of the client's view reporting once a second caller appeared. Two things ask this and
--- they must not disagree: the report that tells the server what this player can see, and the local
--- freeze that holds an enemy still the instant they can see it. An enemy frozen by one test and
--- reported by a different one is an enemy that stands still while the server walks it at you.

local Sightline = {}

--- The camera's view volume, reduced to what a sphere has to be tested against. Rebuilt per sweep
--- rather than per part, since it only moves when the viewport resizes or something animates the FOV.
export type Frustum = {
	TanX: number, -- tangent of the half horizontal angle, and of the vertical one
	TanY: number,
	SideX: number, -- and the lengths that turn each side plane's equation into a distance
	SideY: number,
}

function Sightline.Frustum(camera: Camera): Frustum?
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
function Sightline.Intersects(camera: Camera, frustum: Frustum, center: Vector3, radius: number): boolean
	local point = camera.CFrame:PointToObjectSpace(center) -- -Z is forward, so depth is `-point.Z`
	if point.Z > radius then return false end
	if math.abs(point.X) + frustum.TanX * point.Z > radius * frustum.SideX then return false end
	if math.abs(point.Y) + frustum.TanY * point.Z > radius * frustum.SideY then return false end
	return true
end

--- Whether any part of `model` is both on screen and unoccluded. `ignore` is excluded from the
--- occlusion raycasts, and is the viewer's own character in every caller so far -- a first person
--- camera sits inside a head, and a head counts as a wall unless it is taken out of the way.
function Sightline.CanSee(camera: Camera, frustum: Frustum, ignore: Instance?, model: Model): boolean
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	if not Sightline.Intersects(camera, frustum, boundsCFrame.Position, boundsSize.Magnitude / 2) then
		return false -- nothing of it is on screen, so no part of it can be either
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if ignore then { ignore } else {}
	params.RespectCanCollide = true

	local origin = camera.CFrame.Position
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart")
			and Sightline.Intersects(camera, frustum, descendant.Position, descendant.Size.Magnitude / 2)
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

--- Whether the model is anywhere within the view volume at all, occlusion aside. What decides
--- whether a correction to where it is drawn can be made without anybody seeing it happen.
function Sightline.OnScreen(camera: Camera, frustum: Frustum, model: Model): boolean
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	return Sightline.Intersects(camera, frustum, boundsCFrame.Position, boundsSize.Magnitude / 2)
end

return Sightline
