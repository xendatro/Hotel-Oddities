local Sightline = {}

type PartCache = {
	Parts: { BasePart },
	Indices: { [BasePart]: number },
	Added: RBXScriptConnection,
	Removing: RBXScriptConnection,
	Destroying: RBXScriptConnection,
}

export type Frustum = {
	TanX: number,
	TanY: number,
	SideX: number,
	SideY: number,
}

local PartCaches: { [Model]: PartCache } = {}
local CachedIgnore: Instance? = nil
local SightParams = RaycastParams.new()
SightParams.FilterType = Enum.RaycastFilterType.Exclude
SightParams.RespectCanCollide = true

local function addPart(cache: PartCache, instance: Instance)
	if not instance:IsA("BasePart") or cache.Indices[instance] then return end
	table.insert(cache.Parts, instance)
	cache.Indices[instance] = #cache.Parts
end

local function removePart(cache: PartCache, instance: Instance)
	if not instance:IsA("BasePart") then return end
	local index = cache.Indices[instance]
	if not index then return end

	local last = cache.Parts[#cache.Parts]
	cache.Parts[index] = last
	cache.Parts[#cache.Parts] = nil
	cache.Indices[instance] = nil
	if last ~= instance then cache.Indices[last] = index end
end

local function partsFor(model: Model): { BasePart }
	local existing = PartCaches[model]
	if existing then return existing.Parts end

	local cache = {
		Parts = {},
		Indices = {},
	} :: any
	for _, descendant in model:GetDescendants() do
		addPart(cache, descendant)
	end
	cache.Added = model.DescendantAdded:Connect(function(instance)
		addPart(cache, instance)
	end)
	cache.Removing = model.DescendantRemoving:Connect(function(instance)
		removePart(cache, instance)
	end)
	cache.Destroying = model.Destroying:Connect(function()
		cache.Added:Disconnect()
		cache.Removing:Disconnect()
		PartCaches[model] = nil
	end)
	PartCaches[model] = cache
	return cache.Parts
end

local function raycastParams(ignore: Instance?): RaycastParams
	if ignore ~= CachedIgnore then
		CachedIgnore = ignore
		SightParams.FilterDescendantsInstances = if ignore then { ignore } else {}
	end
	return SightParams
end

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

	local origin = camera.CFrame.Position
	local params = raycastParams(ignore)
	for _, part in partsFor(model) do
		if Sightline.Intersects(camera, frustum, part.Position, part.Size.Magnitude / 2) then
			local direction = part.Position - origin
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
