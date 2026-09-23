local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VfxConfig = require(ReplicatedStorage.Configs.VfxConfig)

local VfxEffect = {}
VfxEffect.__index = VfxEffect

export type Options = {
	Size: Vector3?,
	Duration: number?,
}

export type VfxEffect = typeof(setmetatable({} :: {
	Holder: BasePart,
	Sustained: { ParticleEmitter },
	Threads: { thread },
	Linger: number,
	BurstLength: number,
	Stopped: boolean,
	Destroyed: boolean,
}, VfxEffect))

local function number(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

local function prepareHolder(holder: BasePart)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.CastShadow = false
	holder.Transparency = 1
end

function VfxEffect.new(template: BasePart, cframe: CFrame, parent: Instance, options: Options?): VfxEffect
	local holder = template:Clone()
	prepareHolder(holder)
	if options and options.Size then
		holder.Size = options.Size
	end
	holder.CFrame = cframe

	local self = setmetatable({
		Holder = holder,
		Sustained = {},
		Threads = {},
		Linger = 0,
		BurstLength = 0,
		Stopped = false,
		Destroyed = false,
	}, VfxEffect)

	local length = holder.Size.X
	for _, descendant in holder:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then continue end
		self.Linger = math.max(self.Linger, descendant.Lifetime.Max)
		local perStud = number(descendant, "RatePerStud")
		if perStud then
			descendant.Rate = perStud * length
		end
		if descendant.Enabled then
			table.insert(self.Sustained, descendant)
		end
	end

	holder.Parent = parent
	self:_burst(length)
	self:_flash()

	local duration = (options and options.Duration) or number(holder, "Duration")
	if #self.Sustained == 0 then
		self:Stop()
	elseif duration then
		table.insert(self.Threads, task.delay(duration, function()
			self:Stop()
		end))
	end

	return self
end

function VfxEffect:_burst(length: number)
	for _, descendant in self.Holder:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then continue end

		local count = (number(descendant, "EmitCount") or 0) + (number(descendant, "EmitPerStud") or 0) * length
		count = math.round(count)
		if count <= 0 then continue end

		local delay = number(descendant, "EmitDelay") or 0
		self.BurstLength = math.max(self.BurstLength, delay)
		if delay > 0 then
			table.insert(self.Threads, task.delay(delay, function()
				if descendant.Parent then descendant:Emit(count) end
			end))
		else
			descendant:Emit(count)
		end
	end
end

function VfxEffect:_flash()
	for _, descendant in self.Holder:GetDescendants() do
		if not descendant:IsA("Light") then continue end
		local flashTime = number(descendant, "FlashTime")
		if not flashTime then continue end
		TweenService:Create(
			descendant,
			TweenInfo.new(flashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }
		):Play()
	end
end

function VfxEffect:SetCFrame(cframe: CFrame)
	if self.Destroyed then return end
	self.Holder.CFrame = cframe
end

function VfxEffect:SetSize(size: Vector3)
	if self.Destroyed then return end
	self.Holder.Size = size
end

function VfxEffect:Stop()
	if self.Stopped or self.Destroyed then return end
	self.Stopped = true

	for _, emitter in self.Sustained do
		emitter.Enabled = false
	end
	table.insert(self.Threads, task.delay(self.BurstLength + self.Linger + VfxConfig.CleanupPadding, function()
		self:Destroy()
	end))
end

function VfxEffect:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self.Stopped = true

	for _, thread in self.Threads do
		if coroutine.status(thread) == "suspended" and thread ~= coroutine.running() then
			task.cancel(thread)
		end
	end
	table.clear(self.Threads)
	self.Holder:Destroy()
end

return VfxEffect
