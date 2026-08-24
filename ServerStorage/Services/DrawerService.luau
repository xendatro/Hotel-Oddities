local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local DrawerService = {}

local REACH = DrawerConfig.Targeting.ServerReach
local MIN_INTERVAL = 0.1

local Toggle = CommunicationService.Get("Drawer", "Toggle") :: RemoteEvent

local LastToggle: { [Player]: number } = {}

function DrawerService:SetOpen(model: Model, open: boolean)
	if model:GetAttribute(DrawerConfig.Attribute) == open then
		if open and type(model:GetAttribute(DrawerConfig.OpenedAtAttribute)) ~= "number" then
			model:SetAttribute(DrawerConfig.OpenedAtAttribute, os.time())
		elseif not open and model:GetAttribute(DrawerConfig.OpenedAtAttribute) ~= nil then
			model:SetAttribute(DrawerConfig.OpenedAtAttribute, nil)
		end
		return
	end

	model:SetAttribute(
		DrawerConfig.OpenedAtAttribute,
		if open then os.time() else nil
	)
	model:SetAttribute(DrawerConfig.Attribute, open)

	local sound = DrawerConfig.Sound
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if sound.Enabled and part then
		local template = if open then sound.OpenTemplate else sound.CloseTemplate
		AudioService:Play3DSound(template, part, false, sound.Group, { PlaybackSpeed = sound.PlaybackSpeed })
	end
end

local function closeExpiredDrawers()
	local now = os.time()
	for _, model in CollectionService:GetTagged(DrawerConfig.Tag) do
		if model:GetAttribute(DrawerConfig.Attribute) ~= true then
			if model:GetAttribute(DrawerConfig.OpenedAtAttribute) ~= nil then
				model:SetAttribute(DrawerConfig.OpenedAtAttribute, nil)
			end
			continue
		end

		local openedAt = model:GetAttribute(DrawerConfig.OpenedAtAttribute)
		if type(openedAt) ~= "number" then
			model:SetAttribute(DrawerConfig.OpenedAtAttribute, now)
		elseif now - openedAt >= DrawerConfig.AutoCloseDelay then
			DrawerService:SetOpen(model, false)
		end
	end
end

task.spawn(function()
	while true do
		task.wait(DrawerConfig.AutoCloseCheckInterval)
		closeExpiredDrawers()
	end
end)

Toggle.OnServerEvent:Connect(function(player: Player, model: any, open: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or type(open) ~= "boolean" then return end
	if not model:IsDescendantOf(workspace) or not CollectionService:HasTag(model, DrawerConfig.Tag) then
		return
	end

	local now = os.clock()
	if now - (LastToggle[player] or 0) < MIN_INTERVAL then return end

	local position = CharacterService.GetPosition(player)
	if not position or (model:GetPivot().Position - position).Magnitude > REACH then return end

	LastToggle[player] = now
	DrawerService:SetOpen(model, open)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	LastToggle[player] = nil
end)

return DrawerService
