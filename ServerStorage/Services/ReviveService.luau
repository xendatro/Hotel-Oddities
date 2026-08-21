local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local LoadoutService = require(ServerStorage.Services.LoadoutService)

local REVIVE_PRODUCT_ID = MarketplaceService.Products.Revive
local FORCE_FIELD_DURATION = DeathConfig.Revive.ForceFieldDuration
local CHARACTER_LOAD_TIMEOUT = 10

type DeathSnapshot = {
	Token: number,
	Location: CFrame,
	Items: LoadoutService.Snapshot,
}

local ReviveService = {}
local PendingDeaths: { [Player]: DeathSnapshot } = {}
local NextOfferId: { [Player]: number } = {}

local function loadLivingCharacter(player: Player): Model
	local character = LoadoutService:GetLivingCharacter(player)
	if character then return character end

	player:LoadCharacter()
	local deadline = os.clock() + CHARACTER_LOAD_TIMEOUT
	repeat
		character = LoadoutService:GetLivingCharacter(player)
		if character then return character end
		task.wait()
	until os.clock() >= deadline or player.Parent ~= Players

	error(`ReviveService: failed to load a character for {player.Name}`)
end

function ReviveService:Offer(player: Player, character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart")
	local location = if root and root:IsA("BasePart") then root.CFrame else character:GetPivot()
	local token = (NextOfferId[player] or 0) + 1
	NextOfferId[player] = token

	PendingDeaths[player] = {
		Token = token,
		Location = location,
		Items = LoadoutService:Capture(player),
	}

	return token
end

function ReviveService:Prompt(player: Player, token: number)
	local snapshot = PendingDeaths[player]
	if not snapshot or snapshot.Token ~= token then return end
	MarketplaceService:PromptProductPurchase(player, REVIVE_PRODUCT_ID)
end

function ReviveService:HasPendingDeath(player: Player): boolean
	return PendingDeaths[player] ~= nil
end

function ReviveService:Grant(player: Player)
	local snapshot = PendingDeaths[player]
	PendingDeaths[player] = nil

	local character = loadLivingCharacter(player)

	local forceField = Instance.new("ForceField")
	forceField.Name = "ReviveForceField"
	forceField.Visible = true
	forceField.Parent = character

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.Health = humanoid.MaxHealth

	if snapshot then
		character:PivotTo(snapshot.Location)
		if not LoadoutService:IsEmpty(snapshot.Items) then
			LoadoutService:Restore(player, snapshot.Items)
		end
	end

	task.delay(FORCE_FIELD_DURATION, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
end

assert(
	type(REVIVE_PRODUCT_ID) == "number" and REVIVE_PRODUCT_ID > 0,
	"MarketplaceService.Products.Revive must be a valid developer product ID"
)

MarketplaceService:CreateReceipt(REVIVE_PRODUCT_ID, function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	ReviveService:Grant(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)

Players.PlayerRemoving:Connect(function(player: Player)
	PendingDeaths[player] = nil
	NextOfferId[player] = nil
end)

return ReviveService
