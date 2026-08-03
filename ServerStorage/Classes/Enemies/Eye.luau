--- @class Eye
--- A stationary ambient enemy that punishes the one thing every other enemy in the hotel is about:
--- looking. It never moves, never targets and never closes the distance. It stands where it was put
--- and burns anybody with it on screen -- hardest when it is dead center, tapering to a nag out at
--- the edges. Walking past it is free if you keep your eyes down the corridor; stopping to work out
--- what it is costs you most of your health.
---
--- It has no Humanoid and no rig. There is nothing for a state machine to drive because there is
--- nothing to drive, so the machine here is one perpetual state that does the burning and one
--- evaluator counting down its `Lifetime` -- it leaves on a clock rather than on anything a player
--- does, since nothing a player does can affect it.
---
--- Which way it is pointing is not decided here, and not decided once: every client turns it to stare
--- back at its own camera and floats it gently where it stands, in
--- `ReplicatedStorage.Services.EyeRenderService`. None of that reaches the server, and none of it
--- needs to -- what this charges for is being on your screen, which does not depend on where it is
--- looking or on the few inches it drifts. The stare is only what tells you it noticed.
---
--- Whether it is on somebody's screen is the client's answer, through `EnemyObservationService`, on
--- exactly the terms every other observed enemy uses: the client owns visibility and occlusion, the
--- server owns range. How far off the middle of that screen it sits comes from the camera direction
--- in the same report, so a look reported at all is a look this can price.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local DeathService = require(ServerStorage.Services.DeathService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local RoomService = require(ServerStorage.Services.RoomService)

local ENEMY_TAG = "Enemy"
local EYE_TAG = "Eye" -- what each client's renderer watches for, to turn it towards that camera
local OBSERVABLE_TAG = "Observable" -- makes a client's view report about this model legal
local IGNORE_TAG = "Ignore" -- on a character: enemies cannot target or see them (the spell book)
local DAMAGE_INTERVAL = 0.05 -- seconds between damage ticks; the report itself refreshes at 0.05

local Eye = {}
Eye.__index = Eye
Eye.ClassName = "Eye"

-- Damage per second earned by having it `angle` degrees off the middle of your screen. Full rate at
-- dead center, falling to `EdgeDamage` by `FalloffAngle` and staying there however wide it gets --
-- something on screen at all is never quite free.
local function damageRate(config, angle: number): number
	local nearness = math.clamp(1 - angle / config.FalloffAngle, 0, 1) ^ config.FalloffExponent
	return config.EdgeDamage + (config.CenterDamage - config.EdgeDamage) * nearness
end

-- The living character `player` can be hurt through, or nil while they are dead, hidden by the spell
-- book, or standing in a safe room.
local function getVulnerable(player: Player, config): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not (character and humanoid and humanoid.Health > 0) then return nil end
	if character:HasTag(IGNORE_TAG) then return nil end
	if config.RespectsSafeRooms and RoomService:IsInRoom(player) then return nil end
	return character
end

--- How far off the middle of `player`'s screen this sits, in degrees, or nil while they are not
--- looking at it. Range is checked here rather than taken from the report: a client decides what it
--- can see, but not from how far away it is allowed to see it.
function Eye:GetViewAngle(player: Player): number?
	local character = getVulnerable(player, self.Config)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local boundsCFrame, boundsSize = self.Model:GetBoundingBox()
	local radius = boundsSize.Magnitude / 2
	if (boundsCFrame.Position - root.Position).Magnitude - radius > self.Config.ObservationRange then
		return nil
	end
	return EnemyObservationService:GetViewAngle(player, self.Model)
end

-- Bills everybody currently looking at it for `deltaTime` seconds of having done so.
function Eye:_burnWatchers(deltaTime: number)
	for _, player in Players:GetPlayers() do
		local angle = self:GetViewAngle(player)
		if not angle then continue end

		local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
		DeathService:RecordCause(player, self.EnemyId)
		humanoid:TakeDamage(damageRate(self.Config, angle) * deltaTime)
	end
end

--- Stands there. Damage is charged by the second rather than in hits, so looking away part way
--- through a tick costs exactly the part of it you spent looking.
local function stare(_changeState: StateMachine.ChangeState, eye: any)
	while true do
		local deltaTime = task.wait(DAMAGE_INTERVAL)
		eye:_burnWatchers(deltaTime)
	end
end

function Eye.new(model: Model, config)
	local self = setmetatable({}, Eye)

	self.Model = model
	self.Config = config
	self.Active = false
	self.StateMachine = StateMachine.new({
		Stare = stare,
	}, {}, {
		Lifetime = function()
			task.wait(self.Config.Lifetime)
			self:Despawn()
		end,
	}, "Stare", self)

	return self
end

function Eye:Start()
	if self.Active then return end
	self.Active = true

	-- Every part, not just a primary one: it is a prop rather than a rig, and one loose part sagging
	-- out of the model would be the only thing in it that ever moves. Anchored is also what buys the
	-- turning below cost: an anchored, server-owned part takes a local CFrame and replicates nothing
	-- back, so every viewer can be stared at without any two of them having to agree about it.
	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	self.Model:AddTag(ENEMY_TAG)
	self.Model:AddTag(EYE_TAG)
	self.Model:AddTag(OBSERVABLE_TAG)
	self.StateMachine:Start()
end

function Eye:Despawn()
	if not self.Active then return end
	self.Active = false

	self.Model:RemoveTag(ENEMY_TAG)
	self.Model:RemoveTag(EYE_TAG)
	self.Model:RemoveTag(OBSERVABLE_TAG)

	task.defer(function()
		self.StateMachine:Stop()
		self.Model:Destroy()
	end)
end

return Eye
