local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HearingConfig = require(ReplicatedStorage.Configs.HearingConfig)

local HearingRenderService = {}

if not RunService:IsClient() then
	return HearingRenderService
end

local PARTICLE = HearingConfig.Particle

local Travel = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Hearing")
	:WaitForChild("Travel") :: RemoteEvent

local container = Instance.new("Folder")
container.Name = "HearingMotes"

local function motesFolder(): Folder
	if container.Parent == nil then
		container.Parent = workspace.CurrentCamera or workspace
	end
	return container
end

local function earPosition(model: Model): Vector3?
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil end
	return root.Position + Vector3.new(0, PARTICLE.EarHeight, 0)
end

local function buildMote(): (Part, ParticleEmitter)
	local mote = Instance.new("Part")
	mote.Name = "Mote"
	mote.Shape = Enum.PartType.Ball
	mote.Size = Vector3.one * PARTICLE.Size
	mote.Color = PARTICLE.Color
	mote.Material = Enum.Material.Neon
	mote.Anchored = true
	mote.CanCollide = false
	mote.CanQuery = false
	mote.CanTouch = false
	mote.CastShadow = false

	if PARTICLE.AlwaysOnTop then
		local highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = PARTICLE.Color
		highlight.FillTransparency = 0.15
		highlight.OutlineTransparency = 1
		highlight.Parent = mote
	end

	local wake = Instance.new("ParticleEmitter")
	wake.Rate = PARTICLE.ParticleRate
	wake.Lifetime = PARTICLE.ParticleLifetime
	wake.Speed = NumberRange.new(0, PARTICLE.ParticleSpread)
	wake.SpreadAngle = Vector2.new(180, 180)
	wake.Drag = PARTICLE.ParticleDrag
	wake.LightEmission = 1
	wake.LightInfluence = 0
	wake.Color = ColorSequence.new(PARTICLE.Color)
	wake.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, PARTICLE.ParticleSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	wake.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	wake.Parent = mote

	return mote, wake
end

local function flash(mote: Part, wake: ParticleEmitter)
	wake.Enabled = false
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		elapsed += deltaTime
		local alpha = math.min(elapsed / PARTICLE.ArrivalFlashTime, 1)
		mote.Size = Vector3.one * PARTICLE.Size * (1 + (PARTICLE.ArrivalFlashScale - 1) * alpha)
		mote.Transparency = alpha
		if alpha >= 1 then
			connection:Disconnect()
			mote.Transparency = 1
			local highlight = mote:FindFirstChildOfClass("Highlight")
			if highlight then
				highlight.Enabled = false
			end
			task.delay(PARTICLE.ParticleLifetime.Max, function()
				mote:Destroy()
			end)
		end
	end)
end

local function send(origin: Vector3, model: any, duration: any)
	if typeof(origin) ~= "Vector3" then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if type(duration) ~= "number" or duration ~= duration or duration <= 0 then return end

	local destination = earPosition(model)
	if not destination then return end

	local mote, trail = buildMote()
	mote.Position = origin
	mote.Parent = motesFolder()

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		elapsed += deltaTime
		local alpha = math.min(elapsed / duration, 1)

		destination = earPosition(model) or destination
		local position = origin:Lerp(destination, alpha)
		local heading = destination - position
		mote.CFrame = if heading.Magnitude > 1e-3
			then CFrame.lookAt(position, position + heading)
			else CFrame.new(position)

		if alpha >= 1 then
			connection:Disconnect()
			flash(mote, trail)
		end
	end)
end

Travel.OnClientEvent:Connect(send)

return HearingRenderService
