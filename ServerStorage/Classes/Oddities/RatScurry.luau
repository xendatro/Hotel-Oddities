local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local Oddity = require(ServerStorage.Classes.Oddity)

local FOLDER_NAME = "Oddities"

local RatScurry = Oddity.extend("RatScurry")

RatScurry.Scope = "Prop"
RatScurry.ConfigName = "PropOddityConfig"
RatScurry.Ambient = false

local function oddityFolder(): Instance
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then return existing end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	return folder
end

function RatScurry.new(config: { [string]: any }?)
	local self = Oddity.new(config, RatScurry)
	self.Site = nil :: any
	self.Rat = nil :: Model?
	self.Connection = nil :: RBXScriptConnection?
	return self
end

function RatScurry:_template(): Model?
	local name = if type(self.Config.RatModel) == "string" then self.Config.RatModel else "Rat"
	local props = ReplicatedStorage:FindFirstChild("Props")
	local other = props and props:FindFirstChild("Other")
	local template = other and other:FindFirstChild(name)
	return if template and template:IsA("Model") then template else nil
end

function RatScurry:_span(site: any): number
	return site.HalfWidth + self:Setting("EdgeMargin", 2.5)
end

function RatScurry:CanStart(site: any): (boolean, string?)
	if type(site) ~= "table" or typeof(site.Point) ~= "Vector3" or typeof(site.Across) ~= "Vector3" then
		return false, "no hallway crossing was given"
	end
	if not self:_template() then return false, "the rat model is missing" end
	return true, nil
end

function RatScurry:Start(site: any, duration: number?): boolean
	self.Site = site
	local travel = (self:_span(site) * 2) / math.max(self:Setting("Speed", 26), 1)
	return Oddity.Start(self, site, duration or travel + self:Setting("Linger", 0.35))
end

function RatScurry:OnStart(): boolean
	local site = self.Site
	local template = self:_template()
	if not template then return false end

	local span = self:_span(site)
	local distance = span * 2
	local travel = distance / math.max(self:Setting("Speed", 26), 1)
	local direction = site.Across * (if math.random() < 0.5 then 1 else -1)
	local from = site.Point - direction * span
	local to = site.Point + direction * span

	local rat = template:Clone()
	rat.Name = "Rat"
	for _, descendant in rat:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	rat:PivotTo(CFrame.lookAt(from, from + direction))
	rat.Parent = oddityFolder()
	self.Rat = rat

	local root = rat.PrimaryPart
	local sound = self.Config.Sound
	if root and type(sound) == "string" and sound ~= "" and AudioService:FindTemplate(sound) then
		AudioService:Play3DSound(sound, root, false, "SFX")
	end

	local bobHeight = self:Setting("BobHeight", 0.12)
	local bobRate = self:Setting("BobRate", 6)
	local wiggleAngle = math.rad(self:Setting("WiggleAngle", 9))
	local wiggleRate = self:Setting("WiggleRate", 2.5)
	local startedAt = os.clock()

	self.Connection = RunService.Heartbeat:Connect(function()
		if not self.Active or not rat.Parent then return end

		local alpha = math.clamp((os.clock() - startedAt) / travel, 0, 1)
		local travelled = alpha * distance
		local lift = Vector3.yAxis * (math.abs(math.sin(travelled * bobRate)) * bobHeight)
		local position = from:Lerp(to, alpha) + lift

		rat:PivotTo(
			CFrame.lookAt(position, position + direction)
				* CFrame.Angles(0, math.sin(travelled * wiggleRate) * wiggleAngle, 0)
		)

		if alpha >= 1 then self:Stop() end
	end)

	return true
end

function RatScurry:OnStop()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	if self.Rat then
		self.Rat:Destroy()
		self.Rat = nil
	end
	self.Site = nil
end

return RatScurry
