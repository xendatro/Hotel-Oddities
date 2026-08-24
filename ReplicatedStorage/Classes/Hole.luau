local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local TagService = require(ReplicatedStorage.Services.TagService)

local Prompts = ReplicatedStorage.Props.Prompts

local LocalPlayer = Players.LocalPlayer

local Controls = nil

local function getControls()
	if not Controls then
		Controls = require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
	end
	return Controls
end

local COOLDOWN = 5
local APPROACH_TIMEOUT = 1.5
local SURFACE_HEIGHT = 3.5

local Hole = {}
Hole.__index = Hole

local Active: { [any]: true } = {}

local function beginCooldown()
	for hole in Active do
		hole.Prompt.Enabled = false
	end

	task.delay(COOLDOWN, function()
		for hole in Active do
			hole.Prompt.Enabled = true
		end
	end)
end

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Triggered = self.Prompt.Triggered:Connect(function()
		self:Crawl()
	end)
end

function Hole.new(hole: Model)
	local self = setmetatable({}, Hole)

	self.Hole = hole
	self.Prompt = Prompts.CrawlPrompt:Clone()
	self.Prompt.Parent = hole.PrimaryPart

	setUpConnections(self)
	Active[self] = true

	return self
end

function Hole:_findTwin(): Model?
	return TagService:GetTaggedOfPredicate("Hole", function(other: Instance)
		return other ~= self.Hole and other:GetAttribute("ID") == self.Hole:GetAttribute("ID")
	end)[1]
end

function Hole:Crawl()
	local twin = self:_findTwin()
	if not twin then return end

	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	beginCooldown()
	local controls = getControls()
	controls:Disable()

	humanoid:MoveTo(self.Hole:GetPivot().Position)
	local thread = coroutine.running()
	local resumed = false
	local function resume()
		if resumed then return end
		resumed = true
		task.spawn(thread)
	end
	task.spawn(function()
		humanoid.MoveToFinished:Wait()
		resume()
	end)
	task.delay(APPROACH_TIMEOUT, resume)
	coroutine.yield()

	character.PrimaryPart.Anchored = true

	local track = humanoid.Animator:LoadAnimation(self.Hole.Animations.Crawl)
	track:Play()
	task.delay(0.3, function()
		AudioService:Play3DSound("HoleIn", character.PrimaryPart, false, "SFX")
	end)

	track:GetMarkerReachedSignal("Change"):Wait()
	character:PivotTo(CFrame.new(twin:GetPivot().Position + Vector3.new(0, SURFACE_HEIGHT, 0)))

	task.delay(0.2, function()
		local vfx = twin:FindFirstChild("VFXPart")
		if not vfx then return end
		for _, instance in vfx:GetDescendants() do
			if instance:IsA("ParticleEmitter") then
				instance:Emit(instance:GetAttribute("EmitCount"))
			end
		end
	end)

	track:GetMarkerReachedSignal("Unanchor"):Wait()
	AudioService:Play3DSound("HoleOut", character.PrimaryPart, false, "SFX")
	character.PrimaryPart.Anchored = false
	Controls:Enable()

	track.Ended:Wait()
end

function Hole:Destroy()
	Active[self] = nil
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Prompt:Destroy()
end

return Hole
