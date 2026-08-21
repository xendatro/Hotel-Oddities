local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)

local ComputerService = {}

local TAG = ComputerConfig.Tag
local REACH = ComputerConfig.Targeting.ServerReach
local MIN_INTERVAL = 0.5

local LEGACY_ATTRIBUTE = "Hacked"

local function ensureRemotes(): (RemoteEvent, RemoteEvent)
	local communication = ReplicatedStorage:FindFirstChild("Communication")
	if not communication then
		communication = Instance.new("Folder")
		communication.Name = "Communication"
		communication.Parent = ReplicatedStorage
	end

	local folder = communication:FindFirstChild(ComputerConfig.Remotes.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ComputerConfig.Remotes.Folder
		folder.Parent = communication
	end

	local function remote(name: string): RemoteEvent
		local existing = folder:FindFirstChild(name)
		if existing then return existing :: RemoteEvent end

		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = folder
		return created
	end

	return remote(ComputerConfig.Remotes.Complete), remote(ComputerConfig.Remotes.Sync)
end

local Complete, Sync = ensureRemotes()

local Hacked: { [Player]: { [Model]: true } } = {}
local LastComplete: { [Player]: number } = {}

local function setOf(player: Player): { [Model]: true }
	local set = Hacked[player]
	if not set then
		set = (setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: true }
		Hacked[player] = set
	end
	return set
end

local function sync(player: Player)
	local snapshot: { Model } = {}
	for model in pairs(setOf(player)) do
		table.insert(snapshot, model)
	end
	Sync:FireClient(player, snapshot)
end

local function eligible(instance: Instance): boolean
	return instance:IsA("Model")
		and instance.Name == ComputerConfig.ModelName
		and instance.Parent ~= nil
		and instance.Parent ~= workspace
end

local function register(instance: Instance)
	if not eligible(instance) then return end
	local model = instance :: Model

	if not CollectionService:HasTag(model, TAG) then
		CollectionService:AddTag(model, TAG)
	end
	if model:GetAttribute(LEGACY_ATTRIBUTE) ~= nil then
		model:SetAttribute(LEGACY_ATTRIBUTE, nil)
	end
end

function ComputerService:IsHacked(player: Player, model: Model): boolean
	local set = Hacked[player]
	return set ~= nil and set[model] == true
end

function ComputerService:GetProgress(player: Player): (number, number)
	local set = Hacked[player]
	local hacked, total = 0, 0
	for _, model in CollectionService:GetTagged(TAG) do
		if model:IsDescendantOf(workspace) then
			total += 1
			if set and set[model :: Model] then
				hacked += 1
			end
		end
	end
	return hacked, total
end

function ComputerService:SetHacked(player: Player, model: Model, hacked: boolean)
	local set = setOf(player)
	local was = set[model] == true
	if was == hacked then return end

	set[model] = if hacked then true else nil
	sync(player)
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return nil end
	return root.Position
end

Complete.OnServerEvent:Connect(function(player: Player, model: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if not model:IsDescendantOf(workspace) or not CollectionService:HasTag(model, TAG) then return end
	if ComputerService:IsHacked(player, model) then return end

	local now = os.clock()
	if now - (LastComplete[player] or 0) < MIN_INTERVAL then return end

	local position = characterPosition(player)
	if not position or (model:GetPivot().Position - position).Magnitude > REACH then return end

	LastComplete[player] = now
	ComputerService:SetHacked(player, model, true)
end)

Players.PlayerAdded:Connect(sync)

Players.PlayerRemoving:Connect(function(player: Player)
	Hacked[player] = nil
	LastComplete[player] = nil
end)

for _, descendant in workspace:GetDescendants() do
	register(descendant)
end

workspace.DescendantAdded:Connect(register)

for _, player in Players:GetPlayers() do
	sync(player)
end

return ComputerService
