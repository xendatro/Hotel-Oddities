local ServerStorage = game:GetService("ServerStorage")

local FixtureFall = require(ServerStorage.Classes.FixtureFall)
local LightService = require(ServerStorage.Services.LightService)

local LIGHT_TAG = "Floor1Light"

local LanternFall = FixtureFall.extend("LanternFall", FixtureFall)

function LanternFall.new(config: { [string]: any }?)
	local self = FixtureFall.new(config, LanternFall)
	self.LightClaim = nil :: any
	return self
end

function LanternFall:OnFall(model: Model)
	self.LightClaim = LightService:DisableModel(model)
	model:RemoveTag(LIGHT_TAG)
end

function LanternFall:OnRestore(model: Model)
	if model.Parent then
		model:AddTag(LIGHT_TAG)
	end

	if self.LightClaim then
		LightService:Release(self.LightClaim)
		self.LightClaim = nil
	end
end

return LanternFall
