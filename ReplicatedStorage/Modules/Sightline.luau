local Sightline = {}

export type Frustum = {
	TanX: number,
	TanY: number,
	SideX: number,
	SideY: number,
}

function Sightline.Frustum(camera: Camera): Frustum?
	local viewportSize = camera.ViewportSize
	if viewportSize.Y <= 0 then return nil end

	local tanY = math.tan(math.rad(camera.FieldOfView / 2))
	local tanX = tanY * viewportSize.X / viewportSize.Y
	return {
		TanX = tanX,
		TanY = tanY,
		SideX = math.sqrt(1 + tanX * tanX),
		SideY = math.sqrt(1 + tanY * tanY),
	}
end

function Sightline.Intersects(camera: Camera, frustum: Frustum, center: Vector3, radius: number): boolean
	local point = camera.CFrame:PointToObjectSpace(center)
	if point.Z > radius then return false end
	if math.abs(point.X) + frustum.TanX * point.Z > radius * frustum.SideX then return false end
	if math.abs(point.Y) + frustum.TanY * point.Z > radius * frustum.SideY then return false end
	return true
end

function Sightline.CanSee(camera: Camera, frustum: Frustum, ignore: Instance?, model: Model): boolean
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	if not Sightline.Intersects(camera, frustum, boundsCFrame.Position, boundsSize.Magnitude / 2) then
		return false
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

function Sightline.OnScreen(camera: Camera, frustum: Frustum, model: Model): boolean
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	return Sightline.Intersects(camera, frustum, boundsCFrame.Position, boundsSize.Magnitude / 2)
end

return Sightline
