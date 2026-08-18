--- The server's half of the drawers: one boolean per drawer, so everyone in the hotel sees the same
--- desk. The slide itself is drawn on each client from this attribute; nothing here moves a part.
---
--- A request is only honoured for a living player standing in front of the drawer they named, at a
--- rate a hand can actually press. Anything else is dropped without comment.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)

local DrawerService = {}

local REACH = DrawerConfig.Targeting.ServerReach
--- Seconds between one player's toggles. The client's own cooldown is shorter, so a player pressing
--- as fast as they can is never refused by this.
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

--- Opens or shuts `model` for everyone. Also the way anything else on the server -- an oddity, a
--- round reset -- gets at a drawer.
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
