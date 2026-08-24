local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrawerItemService = {}

if not RunService:IsClient() then
	return DrawerItemService
end

local ItemConfig = require(ReplicatedStorage.Configs.DrawerItemConfig)
local DrawerService = require(ReplicatedStorage.Services.DrawerService)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local TagService = require(ReplicatedStorage.Services.TagService)

local PICKUP_COOLDOWN = 0.15

local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local folder = communication and communication:WaitForChild(ItemConfig.Remotes.Folder, 30)
local PickupRemote = folder and folder:WaitForChild(ItemConfig.Remotes.Pickup, 30)

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

return DrawerItemService
