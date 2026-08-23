local ServerStorage = game:GetService("ServerStorage")

local Oddity = require(ServerStorage.Classes.Oddity)

local PropOddity = Oddity.extend("PropOddity")

PropOddity.Scope = "Prop"
PropOddity.ConfigName = "PropOddityConfig"
PropOddity.Ambient = false

function PropOddity.new(config: { [string]: any }?, class: any?)
	local self = Oddity.new(config, class or PropOddity)
	self.Model = nil :: Model?
	return self
end

function PropOddity:CanStart(model: Model?): (boolean, string?)
	if not model or not model:IsA("Model") then return false, "no prop was given" end
	if not model:IsDescendantOf(workspace) then return false, "that prop is not in the world" end
	return true, nil
end

function PropOddity:Start(model: Model, duration: number?): boolean
	self.Model = model
	return Oddity.Start(self, model, duration or 0)
end

return PropOddity
