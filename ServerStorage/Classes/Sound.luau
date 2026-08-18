local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Templates = ReplicatedStorage:WaitForChild("Sounds")

--- @class Sound
--- Attaches a named AudioEmitter template to a tagged world object.
local Sound = {}
Sound.__index = Sound

local function getParentPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end
		return instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function findTemplate(name: string): AudioEmitter?
	local template = Templates:FindFirstChild(name, true)
	if template and template:IsA("AudioEmitter") then
		return template
	end
	return nil
end

function Sound.new(instance: Instance)
	local self = setmetatable({}, Sound)
	self.Instance = instance

	local name = instance:GetAttribute("Sound")
	local parent = getParentPart(instance)
	if typeof(name) ~= "string" or name == "" or not parent then
		return self
	end

	local template = findTemplate(name)
	if not template then
		warn(("Sound tag on %s could not find AudioEmitter %q"):format(instance:GetFullName(), name))
		return self
	end

	self.Emitter = template:Clone()
	self.Emitter.Parent = parent
	return self
end

function Sound:Destroy()
	if self.Emitter then
		self.Emitter:Destroy()
		self.Emitter = nil
	end
end

return Sound
