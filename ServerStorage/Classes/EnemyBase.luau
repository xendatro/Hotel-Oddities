local EnemyBase = {}
EnemyBase.__index = EnemyBase

EnemyBase.Tags = { "Enemy" }

function EnemyBase.extend(className: string)
	local class = setmetatable({}, { __index = EnemyBase })
	class.__index = class
	class.ClassName = className
	return class
end

function EnemyBase.new(model: Model, config: any, class: any?)
	local self = setmetatable({}, class or EnemyBase)

	self.Model = model
	self.Config = config
	self.Active = false

	return self
end

function EnemyBase:OnStart() end

function EnemyBase:OnDespawn(): number?
	return nil
end

function EnemyBase:DestroyModels()
	self.Model:Destroy()
end

function EnemyBase:Start()
	if self.Active then return end
	self.Active = true

	for _, tag in self.Tags do
		self.Model:AddTag(tag)
	end
	self:OnStart()
	self.StateMachine:Start()
end

function EnemyBase:Despawn()
	if not self.Active then return end
	self.Active = false

	for _, tag in self.Tags do
		self.Model:RemoveTag(tag)
	end
	local linger = self:OnDespawn() or 0

	task.defer(function()
		self.StateMachine:Stop()
		if linger > 0 then
			task.wait(linger)
		end
		self:DestroyModels()
	end)
end

return EnemyBase
