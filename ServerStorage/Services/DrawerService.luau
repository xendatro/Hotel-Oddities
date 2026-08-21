local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)

local DrawerService = {}

local REACH = DrawerConfig.Targeting.ServerReach
local MIN_INTERVAL = 0.1

local Toggle = ReplicatedStorage.Communication.Drawer.Toggle :: RemoteEvent

local LastToggle: { [Player]: number } = {}

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return nil end
	return root.Position
end

function DrawerService:SetOpen(model: Model, open: boolean)
	if model:GetAttribute(DrawerConfig.Attribute) == open then return end
	model:SetAttribute(DrawerConfig.Attribute, open)

	local sound = DrawerConfig.Sound
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if sound.Enabled and part then
		local template = if open then sound.OpenTemplate else sound.CloseTemplate
		AudioService:Play3DSound(template, part, false, sound.Group, { PlaybackSpeed = sound.PlaybackSpeed })
	end
end

Toggle.OnServerEvent:Connect(function(player: Player, model: any, open: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or type(open) ~= "boolean" then return end
	if not model:IsDescendantOf(workspace) or not CollectionService:HasTag(model, DrawerConfig.Tag) then
		return
	end

	local now = os.clock()
	if now - (LastToggle[player] or 0) < MIN_INTERVAL then return end

	local position = characterPosition(player)
	if not position or (model:GetPivot().Position - position).Magnitude > REACH then return end

	LastToggle[player] = now
	DrawerService:SetOpen(model, open)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastToggle[player] = nil
end)

return DrawerService
