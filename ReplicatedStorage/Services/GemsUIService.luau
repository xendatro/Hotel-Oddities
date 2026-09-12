local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local StoreConfig = require(ReplicatedStorage.Configs.StoreConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local KitStateService = require(ReplicatedStorage.Services.KitStateService)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local MathService = require(ReplicatedStorage.Services.MathService)

local GemsUIService = {}

if not RunService:IsClient() then
	return GemsUIService
end

local FLASH = StoreConfig.Flash

local player = Players.LocalPlayer
local gui = GuiBuilderService.GetPlayerGui():WaitForChild("GemsUI") :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local balance = design:WaitForChild("Gems"):WaitForChild("Balance") :: TextLabel
local balanceColor = balance.TextColor3
local flashTween: Tween? = nil

local function flashBalance(success: boolean)
	if flashTween then flashTween:Cancel() end
	balance.TextColor3 = if success then FLASH.Success else FLASH.Failure
	flashTween = TweenService:Create(balance, TweenInfo.new(FLASH.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextColor3 = balanceColor,
	})
	flashTween:Play()
end

local function refreshBalance(result: string?)
	balance.Text = MathService.Comma(KitStateService:GetGems())
	if result == StoreConfig.GemPurchaseResult then flashBalance(true) end
end

local function wirePack(pack)
	local main = design:WaitForChild(pack.Frame):WaitForChild("Main")
	local purchase = main:WaitForChild("Purchase") :: GuiButton
	local price = purchase:WaitForChild("Price") :: TextLabel
	local productId = MarketplaceService.Products.Gems[pack.Amount]
	local published = type(productId) == "number" and productId > 0

	main:WaitForChild("Amount").Text = `{MathService.Comma(pack.Amount)}{StoreConfig.Text.GemsSuffix}`
	price.Text = StoreConfig.Text.Unavailable

	purchase.Activated:Connect(function()
		if not published then
			flashBalance(false)
			return
		end
		MarketplaceService:PromptProductPurchase(player, productId)
	end)

	if not published then return end
	task.spawn(function()
		local success, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		if not success or not info or type(info.PriceInRobux) ~= "number" then return end
		price.Text = MathService.Comma(info.PriceInRobux)
	end)
end

for _, pack in StoreConfig.GemPacks do
	wirePack(pack)
end

KitStateService.GemsChanged:Connect(refreshBalance)
refreshBalance()

return GemsUIService
