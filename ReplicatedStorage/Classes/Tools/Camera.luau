local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local PhotoConfig = require(ReplicatedStorage.Configs.PhotoConfig)

local Camera = ClientTool.extend("Camera")

function Camera.new(tool: Tool)
	return ClientTool.new(tool, Camera)
end

function Camera:_findSpot(): CFrame?
	local character = self.Character
	local camera = workspace.CurrentCamera
	if not character or not camera then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, camera, self.Preview }
	params.RespectCanCollide = true

	local look = camera.CFrame.LookVector
	local result = workspace:Raycast(camera.CFrame.Position, look * PhotoConfig.Place.Range, params)
	if not result then return nil end
	if result.Normal.Y < PhotoConfig.Place.MinFloorNormal then return nil end

	local origin = character:GetPivot().Position
	if (result.Position - origin).Magnitude < PhotoConfig.Place.MinDistance then return nil end

	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 1e-3 then return nil end

	local body = result.Position + Vector3.new(0, PhotoConfig.Place.BodyHeight, 0)
	return CFrame.lookAt(body, body + facing.Unit)
end

function Camera:_buildPreview(): Model?
	local tools = ReplicatedStorage:FindFirstChild("Tools")
	local template = tools and tools:FindFirstChild("Camera")
	if not template then return nil end

	local settings = PhotoConfig.Place.Preview
	local model = Instance.new("Model")
	model.Name = "CameraPreview"

	local body: BasePart? = nil
	for _, child in template:GetChildren() do
		if not child:IsA("BasePart") then continue end

		local clone = child:Clone()
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("JointInstance") or descendant:IsA("Constraint") or descendant:IsA("WeldConstraint") then
				descendant:Destroy()
			end
		end
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CastShadow = false
		clone.Material = settings.Material
		clone.Color = settings.Color
		clone.Transparency = settings.Transparency
		clone.Parent = model
		if child.Name == "Camera" then
			body = clone
		end
	end

	if not body then
		model:Destroy()
		return nil
	end

	model.PrimaryPart = body
	return model
end

function Camera:_setPreviewVisible(visible: boolean)
	local model = self.Preview
	if not model or self.PreviewVisible == visible then return end

	self.PreviewVisible = visible
	model.Parent = if visible then workspace else nil
end

function Camera:OnEquipped()
	if self.Preview then return end

	local model = self:_buildPreview()
	if not model then return end

	self.Preview = model
	self.PreviewVisible = false

	self.Connections.Preview = RunService.RenderStepped:Connect(function()
		if not self.Tool.Parent or not self:IsAlive() then
			self:_setPreviewVisible(false)
			return
		end

		local pivot = self:_findSpot()
		if not pivot then
			self:_setPreviewVisible(false)
			return
		end

		model:PivotTo(pivot * CFrame.Angles(0, PhotoConfig.Place.ModelYaw, 0))
		self:_setPreviewVisible(true)
	end)
end

function Camera:_clearPreview()
	if self.Connections and self.Connections.Preview then
		self.Connections.Preview:Disconnect()
		self.Connections.Preview = nil
	end
	if self.Preview then
		self.Preview:Destroy()
		self.Preview = nil
	end
	self.PreviewVisible = false
end

function Camera:OnUnequipped()
	self:_clearPreview()
end

function Camera:OnDestroy()
	self:_clearPreview()
end

function Camera:OnActivated()
	local pivot = self:_findSpot()
	if not pivot then return end

	self:_clearPreview()
	self:Fire("Place", pivot)
end

return Camera
