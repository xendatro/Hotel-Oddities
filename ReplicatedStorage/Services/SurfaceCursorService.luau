local RunService = game:GetService("RunService")

local SurfaceCursorService = {}

if not RunService:IsClient() then
	return SurfaceCursorService
end

local FACES: { [Enum.NormalId]: { Right: Vector3, Up: Vector3, Normal: Vector3 } } = {
	[Enum.NormalId.Front] = { Right = Vector3.new(-1, 0, 0), Up = Vector3.new(0, 1, 0), Normal = Vector3.new(0, 0, -1) },
	[Enum.NormalId.Back] = { Right = Vector3.new(1, 0, 0), Up = Vector3.new(0, 1, 0), Normal = Vector3.new(0, 0, 1) },
	[Enum.NormalId.Right] = { Right = Vector3.new(0, 0, -1), Up = Vector3.new(0, 1, 0), Normal = Vector3.new(1, 0, 0) },
	[Enum.NormalId.Left] = { Right = Vector3.new(0, 0, 1), Up = Vector3.new(0, 1, 0), Normal = Vector3.new(-1, 0, 0) },
	[Enum.NormalId.Top] = { Right = Vector3.new(1, 0, 0), Up = Vector3.new(0, 0, -1), Normal = Vector3.new(0, 1, 0) },
	[Enum.NormalId.Bottom] = { Right = Vector3.new(1, 0, 0), Up = Vector3.new(0, 0, 1), Normal = Vector3.new(0, -1, 0) },
}

local function axisExtent(size: Vector3, axis: Vector3): number
	return math.abs(size.X * axis.X) + math.abs(size.Y * axis.Y) + math.abs(size.Z * axis.Z)
end

function SurfaceCursorService:GetFaceSize(part: BasePart, face: Enum.NormalId): Vector2
	local basis = FACES[face] or FACES[Enum.NormalId.Front]
	return Vector2.new(axisExtent(part.Size, basis.Right), axisExtent(part.Size, basis.Up))
end

function SurfaceCursorService:Project(
	part: BasePart,
	face: Enum.NormalId,
	viewportPoint: Vector2,
	canvasSize: Vector2
): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local basis = FACES[face] or FACES[Enum.NormalId.Front]
	local cframe = part.CFrame
	local normal = cframe:VectorToWorldSpace(basis.Normal)
	local width = axisExtent(part.Size, basis.Right)
	local height = axisExtent(part.Size, basis.Up)
	local depth = axisExtent(part.Size, basis.Normal)
	local origin = (cframe * CFrame.new(basis.Normal * (depth / 2))).Position

	local ray = camera:ViewportPointToRay(viewportPoint.X, viewportPoint.Y)
	local denominator = ray.Direction:Dot(normal)
	if math.abs(denominator) < 1e-6 then return nil end

	local distance = (origin - ray.Origin):Dot(normal) / denominator
	if distance <= 0 then return nil end

	local hit = cframe:PointToObjectSpace(ray.Origin + ray.Direction * distance)
	local u = hit:Dot(basis.Right) / width + 0.5
	local v = 0.5 - hit:Dot(basis.Up) / height
	if u < 0 or u > 1 or v < 0 or v > 1 then return nil end

	return Vector2.new(u * canvasSize.X, v * canvasSize.Y)
end

function SurfaceCursorService:Contains(element: GuiObject, point: Vector2, padding: number?): boolean
	local slack = padding or 0
	local position = element.AbsolutePosition
	local size = element.AbsoluteSize
	return point.X >= position.X - slack
		and point.X <= position.X + size.X + slack
		and point.Y >= position.Y - slack
		and point.Y <= position.Y + size.Y + slack
end

function SurfaceCursorService:GetAlpha(element: GuiObject, point: Vector2): number
	local size = element.AbsoluteSize
	if size.X <= 0 then return 0 end
	return math.clamp((point.X - element.AbsolutePosition.X) / size.X, 0, 1)
end

return SurfaceCursorService
