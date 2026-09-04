local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemPreviewConfig = require(ReplicatedStorage.Configs.ItemPreviewConfig)

local ItemPreviewService = {}

local Tools = ReplicatedStorage:WaitForChild("Tools")

type Preview = {
	Item: string,
	Viewport: ViewportFrame,
	World: WorldModel,
	Camera: Camera,
	Center: Vector3,
	Radius: number,
}

local previews: { [ViewportFrame]: Preview } = {}
local focus: string? = nil

local function pick(entry: { [string]: number }?, key: string): number
	local value = entry and entry[key]
	if value ~= nil then return value end
	return (ItemPreviewConfig.Default :: any)[key]
end

function ItemPreviewService:GetFraming(itemName: string): ItemPreviewConfig.Framing
	local entry = ItemPreviewConfig.Items[itemName]
	return {
		Yaw = pick(entry, "Yaw"),
		Pitch = pick(entry, "Pitch"),
		Zoom = pick(entry, "Zoom"),
		Padding = pick(entry, "Padding"),
		OffsetX = pick(entry, "OffsetX"),
		OffsetY = pick(entry, "OffsetY"),
	}
end

function ItemPreviewService:GetOverride(itemName: string): { [string]: number }
	local entry = ItemPreviewConfig.Items[itemName]
	if not entry then
		entry = {}
		ItemPreviewConfig.Items[itemName] = entry
	end
	return entry
end

local function aim(preview: Preview)
	local values = ItemPreviewService:GetFraming(preview.Item)
	local fieldOfView = ItemPreviewConfig.FieldOfView
	local radius = preview.Radius * values.Padding
	local distance = radius / math.tan(math.rad(fieldOfView) * 0.5) * values.Zoom
	local direction = CFrame.Angles(math.rad(values.Pitch), math.rad(values.Yaw), 0).LookVector
	local cframe = CFrame.lookAt(preview.Center + direction * distance, preview.Center)

	preview.Camera.FieldOfView = fieldOfView
	preview.Camera.CFrame = cframe
		+ cframe.RightVector * (values.OffsetX * radius)
		+ cframe.UpVector * (values.OffsetY * radius)
end

function ItemPreviewService:Clear(viewport: ViewportFrame)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then child:Destroy() end
	end
	viewport.CurrentCamera = nil
	previews[viewport] = nil
end

function ItemPreviewService:Render(viewport: ViewportFrame, itemName: string?)
	self:Clear(viewport)
	if not itemName then return end

	local source = Tools:FindFirstChild(itemName)
	if not source or not source:IsA("Tool") then return end

	local world = Instance.new("WorldModel")
	world.Name = "Preview"
	world.Parent = viewport

	local clone = source:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("AudioEmitter") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire") or descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
	clone.Parent = world
	world:PivotTo(CFrame.identity)

	local box, size = world:GetBoundingBox()
	if size.Magnitude < 1e-3 then
		world:Destroy()
		return
	end

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = ItemPreviewConfig.Ambient
	viewport.LightColor = ItemPreviewConfig.LightColor
	viewport.LightDirection = ItemPreviewConfig.LightDirection

	local preview: Preview = {
		Item = itemName,
		Viewport = viewport,
		World = world,
		Camera = camera,
		Center = box.Position,
		Radius = math.max(size.X, size.Y, size.Z) * 0.5,
	}
	previews[viewport] = preview
	aim(preview)
end

function ItemPreviewService:Refresh(itemName: string?)
	for viewport, preview in previews do
		if not viewport.Parent or not preview.Camera.Parent then
			previews[viewport] = nil
			continue
		end
		if itemName and preview.Item ~= itemName then continue end
		aim(preview)
	end
end

function ItemPreviewService:SetFocus(itemName: string?)
	focus = itemName
end

function ItemPreviewService:GetFocus(): string?
	return focus
end

return ItemPreviewService
