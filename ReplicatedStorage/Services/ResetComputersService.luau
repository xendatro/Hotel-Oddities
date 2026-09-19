local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ResetComputersService = {}

if not RunService:IsClient() then
	return ResetComputersService
end

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local ResetComputersConfig = require(ReplicatedStorage.Configs.ResetComputersConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local PAGE = ResetComputersConfig.Page

local ResetRemote = CommunicationService.Get(
	ResetComputersConfig.Remotes.Folder,
	ResetComputersConfig.Remotes.Reset
) :: RemoteEvent

local gui = GuiBuilderService.GetPlayerGui():WaitForChild(PAGE.Gui) :: ScreenGui
local design = gui:WaitForChild(PAGE.Root) :: Frame
local notice = design:WaitForChild("Notice") :: TextLabel
local yesButton = design:WaitForChild("YesButton") :: GuiButton
local noButton = design:WaitForChild("NoButton") :: GuiButton

local LastReset = 0
local NoticeToken = 0

local function activePage(): string?
	local active = InterfaceService:GetActive()
	return if active ~= nil and active ~= "" then active else nil
end

local function isOpen(): boolean
	return activePage() == PAGE.Id
end

local function close()
	if isOpen() then InterfaceService:Close() end
end

local function showNotice(text: string)
	NoticeToken += 1
	local token = NoticeToken
	notice.Text = text
	task.delay(ResetComputersConfig.NoticeTime, function()
		if NoticeToken == token then notice.Text = "" end
	end)
end

local function register(model: Instance): Model?
	if not model:IsA("Model") then return nil end

	Interaction:Register(model, {
		Prompt = ResetComputersConfig.Prompt,
		TextWidth = ResetComputersConfig.TextWidth,
		Reach = ResetComputersConfig.Reach,
		HoldDuration = ResetComputersConfig.HoldDuration,
		CanSelect = function()
			return activePage() == nil
		end,
		OnActivated = function()
			if activePage() ~= nil then return false end
			notice.Text = ""
			InterfaceService:Open(PAGE.Id)
			return true
		end,
	})
	return model
end

local function unregister(model: Instance)
	if model:IsA("Model") then Interaction:Unregister(model) end
end

InterfaceService.WireMotion(yesButton)
InterfaceService.WireMotion(noButton)

yesButton.Activated:Connect(function()
	if not isOpen() then return end

	local now = os.clock()
	if now - LastReset < ResetComputersConfig.Cooldown then return end
	LastReset = now

	ResetRemote:FireServer()
	showNotice(ResetComputersConfig.Notice)
	task.delay(ResetComputersConfig.CloseDelay, close)
end)

noButton.Activated:Connect(close)

TagService:Listen(ResetComputersConfig.Tag, register, unregister, workspace)

return ResetComputersService
