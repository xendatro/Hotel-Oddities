local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local SpeedBoostService = require(ServerStorage.Services.SpeedBoostService)

local SpeedDrink = ServerTool.extend("SpeedDrink")

function SpeedDrink.extend(className: string)
	local class = setmetatable({}, { __index = SpeedDrink })
	class.__index = class
	class.ClassName = className
	return class
end

function SpeedDrink.new(tool: Tool, class: any?)
	return ServerTool.new(tool, class or SpeedDrink)
end

local function findDescendant(tool: Tool, name: string?): Instance?
	if not name then return nil end
	return tool:FindFirstChild(name, true)
end

local function playEmbeddedSound(tool: Tool, name: string?, parent: BasePart?)
	local source = findDescendant(tool, name)
	if not source or not source:IsA("AudioEmitter") or not parent then return end

	local emitter = source:Clone()
	emitter.Parent = parent

	local player = emitter.Player :: AudioPlayer
	player:Play()
	Debris:AddItem(emitter, math.max(player.TimeLength + 1, 5))
end

function SpeedDrink:OnActivated()
	local player = self:GetPlayer()
	local character = self.Character
	local humanoid = self.Humanoid
	local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	if not player or not character or not humanoid or humanoid.WalkSpeed <= 0
		or not root or not root:IsA("BasePart") then return end

	playEmbeddedSound(self.Tool, self.Config.OpenSound, root)
	if self.Config.UseDelay and self.Config.UseDelay > 0 then
		task.wait(self.Config.UseDelay)
	end

	if not self:IsAlive() then return end

	local effectTemplate = findDescendant(self.Tool, self.Config.Visual)
	if effectTemplate and not (effectTemplate:IsA("Fire") or effectTemplate:IsA("ParticleEmitter")) then
		effectTemplate = nil
	end

	local effect = effectTemplate and effectTemplate:Clone() or nil
	playEmbeddedSound(self.Tool, self.Config.DrinkSound, root)
	if not self:Consume(1) then
		if effect then effect:Destroy() end
		return
	end

	SpeedBoostService:Apply(
		player,
		self.Name,
		self.Config.WalkSpeed,
		self.Config.Duration,
		self.Config.FovBoost,
		effect
	)
	if effect then effect:Destroy() end
end

return SpeedDrink
