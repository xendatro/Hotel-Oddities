local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local StoreConfig = require(ReplicatedStorage.Configs.StoreConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local MathService = require(ReplicatedStorage.Services.MathService)

local ShopUIService = {}

if not RunService:IsClient() then
	return ShopUIService
end

local player = Players.LocalPlayer
local gui = GuiBuilderService.GetPlayerGui():WaitForChild("ShopUI") :: ScreenGui
local grid = gui:WaitForChild("Design"):WaitForChild("ProductGrid") :: Frame
local LEGACY_PASS_NAMES = {
	DoubleSpeed = "UnlimitedStamina",
}

local function wirePass(card: Frame)
	local passName = if MarketplaceService.Gamepasses[card.Name] ~= nil
		then card.Name
		else LEGACY_PASS_NAMES[card.Name]
	local passId = passName and MarketplaceService.Gamepasses[passName]
	local purchase = card:WaitForChild("Purchase") :: ImageButton
	local price = purchase:WaitForChild("Price") :: TextLabel
	local currencyIcon = purchase:WaitForChild("CurrencyIcon") :: ImageLabel
	local attribute = PerkConfig.AttributePrefix .. (passName or card.Name)
	local basePosition = price.Position
	local baseSize = price.Size
	local robuxPrice: number? = nil
	local published = type(passId) == "number" and passId > 0

	local function paint()
		local owned = player:GetAttribute(attribute) == true
		currencyIcon.Visible = not owned
		price.Position = if owned then StoreConfig.OwnedPrice.Position else basePosition
		price.Size = if owned then StoreConfig.OwnedPrice.Size else baseSize
		price.Text = if owned
			then StoreConfig.Text.Owned
			elseif robuxPrice then MathService.Comma(robuxPrice)
			else StoreConfig.Text.Unavailable
	end

	purchase.Activated:Connect(function()
		if not published or player:GetAttribute(attribute) == true then return end
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end)
	player:GetAttributeChangedSignal(attribute):Connect(paint)
	paint()

	if not published then return end
	task.spawn(function()
		local success, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, passId, Enum.InfoType.GamePass)
		if not success or not info or type(info.PriceInRobux) ~= "number" then return end
		robuxPrice = info.PriceInRobux
		paint()
	end)
end

for _, card in grid:GetChildren() do
	if card:IsA("Frame") then
		wirePass(card)
	end
end

return ShopUIService
