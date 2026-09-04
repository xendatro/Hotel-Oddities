local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PhotoTimerService = {}

if not RunService:IsClient() then
	return PhotoTimerService
end

local PhotoConfig = require(ReplicatedStorage.Configs.PhotoConfig)
local TagService = require(ReplicatedStorage.Services.TagService)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local templates = playerGui:WaitForChild("CaptureTemplates", 20)
local timerTemplate = templates and templates:WaitForChild("PhotoTimer", 10) :: BillboardGui?

if not timerTemplate then
	warn("PhotoTimerService: CaptureTemplates.PhotoTimer did not replicate")
	return PhotoTimerService
end

local function anchorPart(model: Model): BasePart?
	local body = model:FindFirstChild("Camera")
	if body and body:IsA("BasePart") then return body end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

local function buildBillboard(part: BasePart): (BillboardGui, TextLabel)
	local billboard = timerTemplate:Clone()
	billboard.Enabled = true
	billboard.Parent = part
	local label = billboard:FindFirstChild("Label") :: TextLabel

	return billboard, label
end

local function pulse(label: TextLabel)
	local settings = PhotoConfig.Timer
	label.Size = UDim2.fromScale(settings.PulseScale, settings.PulseScale)
	TweenService:Create(label, TweenInfo.new(settings.PulseTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
	}):Play()
end

local function attach(model: Instance)
	if not model:IsA("Model") then return nil end

	local settings = PhotoConfig.Timer
	local data = { Billboard = nil :: BillboardGui?, Connection = nil :: RBXScriptConnection?, Cancelled = false }

	task.spawn(function()
		local part = anchorPart(model)
		local deadline = os.clock() + 5
		while not part and not data.Cancelled and model.Parent and os.clock() < deadline do
			task.wait(0.1)
			part = anchorPart(model)
		end
		if not part or data.Cancelled or not model.Parent then return end

		local billboard, label = buildBillboard(part)
		local normalColor = label:GetAttribute("NormalColor")
		if typeof(normalColor) ~= "Color3" then normalColor = label.TextColor3 end
		local warnColor = label:GetAttribute("WarnColor")
		if typeof(warnColor) ~= "Color3" then warnColor = label.TextColor3 end
		local shown = -1
		data.Billboard = billboard

		data.Connection = RunService.Heartbeat:Connect(function()
			if not model.Parent then return end

			if model:GetAttribute(PhotoConfig.Attributes.Snapped) then
				if label.Text ~= settings.SnapText then
					label.Text = settings.SnapText
					label.TextColor3 = warnColor
					pulse(label)
					task.delay(settings.SnapHold, function()
						if billboard.Parent then
							billboard.Enabled = false
						end
					end)
				end
				return
			end

			local snapAt = model:GetAttribute(PhotoConfig.Attributes.SnapAt)
			if type(snapAt) ~= "number" then return end

			local remaining = math.max(math.ceil(snapAt - workspace:GetServerTimeNow()), 0)
			if remaining == shown then return end

			shown = remaining
			label.Text = tostring(remaining)
			label.TextColor3 = if remaining <= settings.WarnAt then warnColor else normalColor
			pulse(label)
		end)
	end)

	return data
end

local function detach(_model: Instance, data: any)
	if not data then return end

	data.Cancelled = true
	if data.Connection then
		data.Connection:Disconnect()
	end
	if data.Billboard then
		data.Billboard:Destroy()
	end
end

TagService:Listen(PhotoConfig.Tag, attach, detach)

return PhotoTimerService
