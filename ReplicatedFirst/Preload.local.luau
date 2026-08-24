local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Gui = script:WaitForChild("LoadingGui")
local Overlay = Gui:WaitForChild("Overlay")
local LoadingGradient = Overlay:WaitForChild("Loading"):WaitForChild("UIGradient")
local Assets = Overlay:WaitForChild("Assets")
local BarFrame = Overlay:WaitForChild("Bar"):WaitForChild("Frame")

local CONTENT_CLASSES = {
	"MeshPart", "SpecialMesh", "Decal", "Texture",
	"ImageLabel", "ImageButton", "Sound", "Animation",
	"ParticleEmitter", "Beam", "Trail", "Shirt", "Pants", "SurfaceAppearance",
}

local FADE_TIME = 0.5
local POST_LOAD_DELAY = 1
local shimmerTween: Tween? = nil
local shimmerToken = 0

local function carriesContent(instance: Instance): boolean
	for _, className in CONTENT_CLASSES do
		if instance:IsA(className) then return true end
	end
	return false
end

local function stopShimmer()
	shimmerToken += 1
	if shimmerTween then
		shimmerTween:Cancel()
		shimmerTween = nil
	end
	LoadingGradient.Offset = Vector2.new(-1, 0)
end

local function startShimmer()
	stopShimmer()
	local token = shimmerToken

	local function sweep()
		if token ~= shimmerToken or not Gui.Enabled then return end
		LoadingGradient.Offset = Vector2.new(-1, 0)
		shimmerTween = TweenService:Create(
			LoadingGradient,
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

task.defer(function()
	local started = os.clock()
	local assets: { any } = {}
	local amountLoaded = 0

	local function enqueue(item: any)
		table.insert(assets, item)
	end

	local configs = ReplicatedStorage:WaitForChild("Configs")
	local ok, effectsConfig = pcall(require, configs:WaitForChild("EffectsHUDConfig"))
	if ok then
		for _, id in effectsConfig.Icons do
			if id ~= "" then enqueue(id) end
		end
	end

	local okAnimations, animationConfig = pcall(require, configs:WaitForChild("AnimationConfig"))
	if okAnimations then
		for _, id in animationConfig.Animations do
			enqueue(`rbxassetid://{id}`)
		end
	end

	for _, root in { ReplicatedStorage, workspace, StarterGui, SoundService, Lighting } do
		for _, instance in root:GetDescendants() do
			if carriesContent(instance) then
				enqueue(instance)
			end
		end
	end

	local total = #assets
	local function updateProgress()
		local progress = 1
		if total > 0 then
			progress = math.clamp(amountLoaded / total, 0, 1)
		end
		Assets.Text = `{amountLoaded}/{total}`
		BarFrame.Size = UDim2.fromScale(progress, 1)
	end

	updateProgress()
	startShimmer()
	pcall(function()
		ContentProvider:PreloadAsync(assets, function()
			amountLoaded += 1
			total = math.max(total, amountLoaded)
			updateProgress()
		end)
	end)
	if amountLoaded < total then
		amountLoaded = total
		updateProgress()
	end

	task.wait(POST_LOAD_DELAY)
	stopShimmer()
	local fadeInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function fade(instance: Instance): Tween?
		local goal: { [string]: any } = {}
		if instance:IsA("GuiObject") then
			goal.BackgroundTransparency = 1
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			goal.TextTransparency = 1
			goal.TextStrokeTransparency = 1
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			goal.ImageTransparency = 1
		end
		if instance:IsA("UIStroke") then
			goal.Transparency = 1
		end
		if next(goal) == nil then return nil end

		local tween = TweenService:Create(instance, fadeInfo, goal)
		tween:Play()
		return tween
	end

	local overlayTween = fade(Overlay)
	for _, instance in Overlay:GetDescendants() do
		fade(instance)
	end
	if overlayTween then
		overlayTween.Completed:Wait()
	end
	Gui.Enabled = false

	print(`[Preload] warmed {total} assets in {math.floor((os.clock() - started) * 10) / 10}s`)
end)

Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
