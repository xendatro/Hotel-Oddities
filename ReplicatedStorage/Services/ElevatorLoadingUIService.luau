local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local ElevatorLoadingUIService = {}

if not RunService:IsClient() then
	return ElevatorLoadingUIService
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("ElevatorLoadingGui", 30) :: ScreenGui?
local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local elevator = communication and communication:WaitForChild("Elevator", 30)
local loading = elevator and elevator:WaitForChild("Loading", 30)
local fadeComplete = elevator and elevator:WaitForChild("FadeComplete", 30)

if not gui or not loading or not loading:IsA("RemoteEvent") then
	warn("[ElevatorLoadingUIService] loading UI or remote is missing")
	return ElevatorLoadingUIService
end

local overlay = gui:FindFirstChild("Overlay")
local hero = overlay and overlay:FindFirstChild("Hero")
local title = overlay and overlay:FindFirstChild("Title")
local loadingLabel = overlay and overlay:FindFirstChild("Loading")
local loadingGradientInstance = loadingLabel and loadingLabel:FindFirstChild("UIGradient")

if not (
	overlay
		and hero
		and title
		and loadingLabel
		and loadingGradientInstance
		and overlay:IsA("Frame")
		and hero:IsA("ImageLabel")
		and title:IsA("TextLabel")
		and loadingLabel:IsA("TextLabel")
		and loadingGradientInstance:IsA("UIGradient")
	) then
	warn("[ElevatorLoadingUIService] revised loading UI is missing Overlay, Hero, Title, Loading, or Loading.UIGradient")
	return ElevatorLoadingUIService
end

local overlayFrame = overlay :: Frame
local heroImage = hero :: ImageLabel
local titleLabel = title :: TextLabel
local loadingText = loadingLabel :: TextLabel
local loadingGradient = loadingGradientInstance :: UIGradient
local baseOverlayTransparency = overlayFrame.BackgroundTransparency
local baseHeroTransparency = heroImage.ImageTransparency
local baseTitleTransparency = titleLabel.TextTransparency
local baseLoadingTransparency = loadingText.TextTransparency
local random = Random.new()
local panTween: Tween? = nil
local shimmerTween: Tween? = nil
local fadeTweens: { Tween } = {}
local panToken = 0
local shimmerToken = 0
local activeToken: number? = nil

local function stopShimmer()
	shimmerToken += 1
	if shimmerTween then
		shimmerTween:Cancel()
		shimmerTween = nil
	end
	loadingGradient.Offset = Vector2.new(-1, 0)
end

local function startShimmer()
	stopShimmer()
	local token = shimmerToken

	local function sweep()
		if token ~= shimmerToken or not gui.Enabled then return end
		loadingGradient.Offset = Vector2.new(-1, 0)
		shimmerTween = TweenService:Create(
			loadingGradient,
			TweenInfo.new(0.8, Enum.EasingStyle.Linear),
			{ Offset = Vector2.new(1, 0) }
		)
		shimmerTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and token == shimmerToken then
				task.delay(0.8, sweep)
			end
		end)
		shimmerTween:Play()
	end

	sweep()
end

local function randomPanPoint(): Vector2
	local extraX = math.max(heroImage.Size.X.Scale - 1, 0)
	local extraY = math.max(heroImage.Size.Y.Scale - 1, 0)
	return Vector2.new(-random:NextNumber(0, extraX), -random:NextNumber(0, extraY))
end

local function stopPan()
	panToken += 1
	if panTween then
		panTween:Cancel()
		panTween = nil
	end
end

local function startPan()
	stopPan()
	local token = panToken
	local start = randomPanPoint()
	heroImage.Position = UDim2.fromScale(start.X, start.Y)

	local function moveToNextPoint()
		if token ~= panToken or not gui.Enabled then return end
		local target = randomPanPoint()
		panTween = TweenService:Create(
			heroImage,
			TweenInfo.new(random:NextNumber(5.5, 8), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Position = UDim2.fromScale(target.X, target.Y) }
		)
		panTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then moveToNextPoint() end
		end)
		panTween:Play()
	end

	moveToNextPoint()
end

local function cancelFade()
	for _, tween in fadeTweens do tween:Cancel() end
	table.clear(fadeTweens)
end

local function fadeIn(token: number)
	cancelFade()
	overlayFrame.BackgroundTransparency = 1
	heroImage.ImageTransparency = 1
	titleLabel.TextTransparency = 1
	loadingText.TextTransparency = 1
	gui.Enabled = true
	activeToken = token
	startPan()
	startShimmer()

	local info = TweenInfo.new(ElevatorConfig.FadeInTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local overlayTween = TweenService:Create(overlayFrame, info, { BackgroundTransparency = baseOverlayTransparency })
	local heroTween = TweenService:Create(heroImage, info, { ImageTransparency = baseHeroTransparency })
	local titleTween = TweenService:Create(titleLabel, info, { TextTransparency = baseTitleTransparency })
	local loadingTween = TweenService:Create(loadingText, info, { TextTransparency = baseLoadingTransparency })
	table.insert(fadeTweens, overlayTween)
	table.insert(fadeTweens, heroTween)
	table.insert(fadeTweens, titleTween)
	table.insert(fadeTweens, loadingTween)
	overlayTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed
			and activeToken == token
			and fadeComplete
			and fadeComplete:IsA("RemoteEvent")
		then
			(fadeComplete :: RemoteEvent):FireServer(token)
		end
	end)
	overlayTween:Play()
	heroTween:Play()
	titleTween:Play()
	loadingTween:Play()
end

local function fadeOut(token: number)
	if activeToken ~= token then return end
	cancelFade()
	stopPan()
	stopShimmer()

	local info = TweenInfo.new(ElevatorConfig.FadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local overlayTween = TweenService:Create(overlayFrame, info, { BackgroundTransparency = 1 })
	local heroTween = TweenService:Create(heroImage, info, { ImageTransparency = 1 })
	local titleTween = TweenService:Create(titleLabel, info, { TextTransparency = 1 })
	local loadingTween = TweenService:Create(loadingText, info, { TextTransparency = 1 })
	table.insert(fadeTweens, overlayTween)
	table.insert(fadeTweens, heroTween)
	table.insert(fadeTweens, titleTween)
	table.insert(fadeTweens, loadingTween)
	overlayTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed and activeToken == token then
			gui.Enabled = false
			activeToken = nil
		end
	end)
	overlayTween:Play()
	heroTween:Play()
	titleTween:Play()
	loadingTween:Play()
end

task.spawn(function()
	pcall(function() ContentProvider:PreloadAsync({ heroImage }) end)
end)

loading.OnClientEvent:Connect(function(show: any, token: any)
	if typeof(token) ~= "number" then return end
	if show == true then
		fadeIn(token)
	elseif show == false then
		fadeOut(token)
	end
end)

return ElevatorLoadingUIService
