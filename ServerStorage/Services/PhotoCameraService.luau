local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PhotoConfig = require(ReplicatedStorage.Configs.PhotoConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GazeService = require(ServerStorage.Services.GazeService)

local Snap = CommunicationService.Ensure("Photo", "Snap")

local PhotoCameraService = {}

local Active: { [Model]: boolean } = {}

PhotoCameraService.ForceFigure = false
PhotoCameraService.FigureName = PhotoConfig.Figure.Name

local function template(): Tool?
	local tools = ReplicatedStorage:FindFirstChild("Tools")
	local tool = tools and tools:FindFirstChild("Camera")
	return if tool and tool:IsA("Tool") then tool else nil
end

local function build(pivot: CFrame): Model?
	local tool = template()
	if not tool then
		warn("PhotoCameraService: no Camera tool in ReplicatedStorage.Tools")
		return nil
	end

	local model = Instance.new("Model")
	model.Name = PhotoConfig.ModelName

	local body: BasePart? = nil
	for _, child in tool:GetChildren() do
		if not child:IsA("BasePart") then continue end

		local clone = child:Clone()
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("JointInstance") or descendant:IsA("Constraint") or descendant:IsA("WeldConstraint") or descendant:IsA("BaseScript") then
				descendant:Destroy()
			end
		end
		clone.Anchored = true
		clone.CanCollide = true
		clone.Massless = false
		clone.Parent = model
		if child.Name == "Camera" then
			body = clone
		end
	end

	if not body then
		model:Destroy()
		warn("PhotoCameraService: Camera tool has no part named Camera")
		return nil
	end

	model.PrimaryPart = body
	model:PivotTo(pivot * CFrame.Angles(0, PhotoConfig.Place.ModelYaw, 0))
	return model
end

local function characterFilter(extra: Instance?): { Instance }
	local filter: { Instance } = {}
	if extra then
		table.insert(filter, extra)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	return filter
end

function PhotoCameraService:GetSubjects(model: Model, lens: CFrame): { Player }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter(model)
	params.RespectCanCollide = true

	local limit = math.cos(math.rad(PhotoConfig.Lens.Cone / 2))
	local subjects = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or not CharacterService.IsAlive(character) then continue end

		local head = character:FindFirstChild("Head") :: BasePart?
		local point = if head then head.Position else character:GetPivot().Position
		local offset = point - lens.Position
		local distance = offset.Magnitude
		if distance < 1e-3 or distance > PhotoConfig.Lens.MaxDistance then continue end
		if offset.Unit:Dot(lens.LookVector) < limit then continue end
		if workspace:Raycast(lens.Position, offset, params) then continue end

		table.insert(subjects, player)
	end

	return subjects
end

local function floorAt(point: Vector3, model: Model): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter(model)
	params.RespectCanCollide = true

	local result = workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -PhotoConfig.Figure.FloorDrop, 0), params)
	return if result then result.Position else nil
end

function PhotoCameraService:GetFigureCFrame(model: Model, lens: CFrame, subjects: { Player }): CFrame?
	local settings = PhotoConfig.Figure

	local forward = Vector3.new(lens.LookVector.X, 0, lens.LookVector.Z)
	if forward.Magnitude < 1e-3 then return nil end
	forward = forward.Unit

	local right = Vector3.new(-forward.Z, 0, forward.X)

	local depth = settings.MinDepth
	if self.ForceFigure then
		depth = settings.ForcedDepth
	elseif #subjects > 0 then
		local total = 0
		for _, player in subjects do
			local position = CharacterService.GetPosition(player)
			if position then
				total += (position - lens.Position):Dot(forward)
			end
		end
		depth = math.max(depth, total / #subjects + settings.BehindSubjects)
	end
	depth = math.min(depth, settings.MaxDepth)

	local spread = if self.ForceFigure then settings.ForcedSide else settings.SideOffset
	local side = if math.random() < 0.5 then -spread else spread
	local base = lens.Position

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter(model)
	params.RespectCanCollide = true

	local target = base + forward * depth + right * side
	local blocked = workspace:Raycast(base, target - base, params)
	if blocked then
		local pulled = blocked.Position - base
		if pulled.Magnitude > settings.Clearance then
			target = base + pulled.Unit * (pulled.Magnitude - settings.Clearance)
		elseif self.ForceFigure then
			target = base + forward * math.max(pulled.Magnitude * 0.5, 2)
		else
			return nil
		end
	end

	if not self.ForceFigure and (target - base).Magnitude < settings.MinStandoff then return nil end

	local groundY = model:GetPivot().Position.Y - PhotoConfig.Place.BodyHeight
	local floor = floorAt(target, model)
	if not floor or math.abs(floor.Y - groundY) > settings.MaxFloorRise then
		floor = Vector3.new(target.X, groundY, target.Z)
	end

	local stand = floor + Vector3.new(0, settings.PivotHeight, 0)
	return CFrame.lookAt(stand, Vector3.new(lens.Position.X, stand.Y, lens.Position.Z))
end

local function watch(model: Model)
	local tracker = GazeService.new(model, {
		Cone = PhotoConfig.Despawn.Cone,
		MaxDistance = PhotoConfig.Despawn.MaxDistance,
		Samples = 2,
	})

	local born = os.clock()
	task.spawn(function()
		while model.Parent do
			task.wait(PhotoConfig.Despawn.PollInterval)
			if not model.Parent then break end

			tracker:Update()
			local age = os.clock() - born
			if age > PhotoConfig.Despawn.MaxLifetime then break end
			if age > PhotoConfig.Despawn.MinLifetime and tracker.UnseenFor >= PhotoConfig.Despawn.UnseenFor then break end
		end

		Active[model] = nil
		model:Destroy()
	end)
end

function PhotoCameraService:Snap(model: Model)
	if not model.Parent then return end
	if model:GetAttribute(PhotoConfig.Attributes.Snapped) then return end

	local lens = model:GetPivot() * PhotoConfig.Lens.Offset
	local subjects = self:GetSubjects(model, lens)
	local figure = self:GetFigureCFrame(model, lens, subjects)

	local owner = Players:GetPlayerByUserId(model:GetAttribute(PhotoConfig.Attributes.Owner) or 0)
	if owner and not table.find(subjects, owner) then
		table.insert(subjects, owner)
	end

	model:SetAttribute(PhotoConfig.Attributes.Snapped, true)

	for _, player in subjects do
		Snap:FireClient(player, lens, PhotoConfig.Lens.FieldOfView, figure, self.FigureName)
	end

	watch(model)
end

function PhotoCameraService:Place(player: Player, pivot: CFrame): Model?
	local root = CharacterService.GetAliveRoot(player)
	if not root then return nil end
	if (root.Position - pivot.Position).Magnitude > PhotoConfig.Place.Range + PhotoConfig.Place.BodyHeight then return nil end

	local model = build(pivot)
	if not model then return nil end

	model:SetAttribute(PhotoConfig.Attributes.Owner, player.UserId)
	model:SetAttribute(PhotoConfig.Attributes.SnapAt, workspace:GetServerTimeNow() + PhotoConfig.Countdown)
	model:SetAttribute(PhotoConfig.Attributes.Snapped, false)
	model.Parent = workspace
	CollectionService:AddTag(model, PhotoConfig.Tag)

	Active[model] = true

	task.delay(PhotoConfig.Countdown, function()
		if not Active[model] then return end
		self:Snap(model)
	end)

	return model
end

function PhotoCameraService:GetActive(): { Model }
	local models = {}
	for model in Active do
		if model.Parent then
			table.insert(models, model)
		end
	end
	return models
end

return PhotoCameraService
