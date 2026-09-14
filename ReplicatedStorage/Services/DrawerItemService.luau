local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrawerItemService = {}

if not RunService:IsClient() then
	return DrawerItemService
end

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local ItemConfig = require(ReplicatedStorage.Configs.DrawerItemConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local DrawerService = require(ReplicatedStorage.Services.DrawerService)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local MathService = require(ReplicatedStorage.Services.MathService)
local NotificationService = require(ReplicatedStorage.Services.NotificationService)
local TagService = require(ReplicatedStorage.Services.TagService)

local PICKUP_COOLDOWN = 0.15

local PickupRemote = CommunicationService.Get(ItemConfig.Remotes.Folder, ItemConfig.Remotes.Pickup)
local PickupResultRemote = CommunicationService.Get(ItemConfig.Remotes.Folder, ItemConfig.Remotes.Result) :: RemoteEvent

local States: { [Model]: true } = {}
local focused: Model? = nil
local lastPickup = 0

local function register(model: Model): Model?
	if not model:IsA("Model") then return nil end

	States[model] = true
	Interaction:Register(model, {
		Prompt = ItemConfig.UI.PickupText,
		TextWidth = ItemConfig.UI.TextWidth,
		Reach = ItemConfig.Targeting.Reach,
		OnActivated = function(target: Model)
			return DrawerItemService:Pickup(target)
		end,
	})

	local drawer = model.Parent
	if drawer and drawer:IsA("Model") then
		DrawerService:Sync(drawer)
	end
	return model
end

local function unregister(model: Model)
	States[model] = nil
	Interaction:Unregister(model)
end

function DrawerItemService:GetFocused(): Model?
	return focused
end

function DrawerItemService:Pickup(model: Model?): boolean
	local item = model or focused
	if not item or not States[item] or not PickupRemote then return false end

	local now = os.clock()
	if now - lastPickup < PICKUP_COOLDOWN then return false end
	lastPickup = now

	;(PickupRemote :: RemoteEvent):FireServer(item)
	return true
end

Interaction.Selected:Connect(function(model: Model?)
	focused = if model and States[model] then model else nil
end)

TagService:Listen(ItemConfig.Tag, register, unregister, workspace)

PickupResultRemote.OnClientEvent:Connect(function(currency: any, amount: any)
	if type(currency) ~= "string" or type(amount) ~= "number" or amount <= 0 then return end

	local label = ItemConfig.Feedback.Labels[currency]
	if type(label) ~= "string" then return end

	NotificationService:Show(`+{MathService.Comma(amount)} {label}`)

	local sound = ItemConfig.Feedback.Sounds[currency]
	if type(sound) == "string" and AudioService:FindTemplate(sound) then
		AudioService:Play2DSound(sound, false, "SFX")
	end
end)

return DrawerItemService
