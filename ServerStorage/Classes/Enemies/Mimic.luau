--- @class Mimic
--- Wears a player. It takes the name and avatar of someone already in the server when it spawns, and
--- of whoever it kills after that, so the copy is always of a face you have seen.
---
--- Its tell is meant to be behavioural rather than visual, which is why it does not charge on sight
--- like a `Chaser`. It locks on and copies you: your keys, played back a beat late, and nothing else.
--- Wiggling to test it produces a wiggle, walking at it walks it at you, and standing still leaves it
--- standing still -- because that is what someone mirroring you would do, and it is what makes the
--- test inconclusive. That mirroring runs on your own client (`MimicService`) with the rig handed to
--- you, because a server-driven humanoid reaches your screen as stepped motion and no amount of
--- smoothing on this side fixes that. This half owns the act instead: who it is, when to lock on, and
--- when to stop pretending.
---
--- Since it never moves on its own, it only closes the gap when you do. The act ends at
--- `StrikeRange`, when you have opened up `RetreatSlack` of real ground, when you turn your back
--- after having looked right at it, or when it finally runs out of patience. Then the rig comes back
--- to the server and it runs you down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)
local MimicMotion = require(ReplicatedStorage.Modules.MimicMotion)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local NPC = require(ServerStorage.Classes.NPC)

local PERCEPTION_INTERVAL = 0.25
local SUPERVISE_INTERVAL = 0.1 -- how often the act is re-examined while the client does the moving
local LOOK_AROUND_DISTANCE = 10
local SIGHT_GRACE = 1.5 -- seconds it will keep mirroring a target it can no longer see
local NOTICED_ANGLE = 65 -- degrees within which a target counts as having looked at the mimic

local Mirror = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("Mirror") :: RemoteEvent

local Mimic = NPC.extend("Mimic")

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Degrees between two directions, ignoring height.
local function angleBetween(from: Vector3, to: Vector3): number
	local a, b = flatten(from), flatten(to)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then return 0 end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

--- Stands around the way a player does between decisions: turning to look at something, hopping for
--- no reason. A humanoid holding perfectly still is the fastest way to read as an NPC.
local function loiter(_changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc.Animator:Resume()
	npc:StopMirroring()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:StopMoving()

	local config = npc.Config
	local until_ = os.clock() + randomRange(config.IdleTimeMin, config.IdleTimeMax)
	local lookAt = npc.RootPart.Position + npc.RootPart.CFrame.LookVector * LOOK_AROUND_DISTANCE
	local nextGlanceAt = 0

	local deltaTime = RunService.Heartbeat:Wait()
	while os.clock() < until_ do
		local now = os.clock()
		if now >= nextGlanceAt then
			local angle = math.rad(randomRange(-config.GlanceAngle, config.GlanceAngle) * 2)
			local look = CFrame.Angles(0, angle, 0) * npc.RootPart.CFrame.LookVector
			lookAt = npc.RootPart.Position + look * LOOK_AROUND_DISTANCE
			nextGlanceAt = now + randomRange(config.GlanceInterval, config.GlanceInterval * 2)

			if math.random() < config.IdleJumpChance then
				npc.Humanoid.Jump = true
			end
		end

		npc.RootPart.CFrame = MimicMotion.Turn(npc.RootPart.CFrame, lookAt - npc.RootPart.Position, deltaTime)
		deltaTime = RunService.Heartbeat:Wait()
	end

	return config.IdleNextState, npc
end

--- Watches `target` while their own client does the moving. Locked on, the mimic has no will of its
--- own -- it copies their keys a beat late and does nothing else, so it closes the gap only when they
--- close it. Everything here is a reason to stop pretending; the mirroring is not this side's business.
local function stalk(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:StopMoving()
	npc:StartMirroring(target)

	local config = npc.Config
	local giveUpAt = os.clock() + randomRange(config.StalkTimeMin, config.StalkTimeMax)
	local closest = math.huge
	local lastKnown = npc.RootPart.Position
	local lostSightAt = nil :: number?
	local turnedAwayAt = nil :: number?
	local noticed = false

	while os.clock() < giveUpAt do
		local position = npc:GetTargetPosition(target)
		if not position then return "Idle", npc end

		local now = os.clock()
		local toMimic = npc.RootPart.Position - position
		local distance = flatten(toMimic).Magnitude
		if distance <= config.StrikeRange then return "Chase", npc, target end

		-- Backing away is allowed, and mirrored -- but only so far. `RetreatSlack` is measured from
		-- the closest it has managed to get, so the grace is a head start rather than a fixed range.
		closest = math.min(closest, distance)
		if distance - closest >= config.RetreatSlack then return "Chase", npc, target end

		-- Stalking is line-of-sight work: it only ever moves straight at you. Round a corner and it
		-- walks over to where you were like anyone else would, rather than mirroring through a wall.
		if npc:HasLineOfSightToPlayer(target) then
			lastKnown, lostSightAt = position, nil
		else
			lostSightAt = lostSightAt or now
			if now - lostSightAt >= SIGHT_GRACE then
				return "Search", npc, lastKnown
			end
		end

		-- Facing, not camera: the server only knows which way a character is turned. Turning your back
		-- counts only once you have squarely faced it, so someone who never noticed it standing across
		-- the room is not charged at out of nowhere.
		local root = (target.Character :: Model).HumanoidRootPart :: BasePart
		local away = angleBetween(root.CFrame.LookVector, toMimic)
		if away <= NOTICED_ANGLE then
			noticed, turnedAwayAt = true, nil
		elseif noticed and away >= config.TurnAwayAngle then
			turnedAwayAt = turnedAwayAt or now
			if now - turnedAwayAt >= config.TurnAwayGrace then return "Chase", npc, target end
		else
			turnedAwayAt = nil
		end

		task.wait(SUPERVISE_INTERVAL)
	end

	return "Chase", npc, target
end

--- The act is over. Runs `target` down until it is caught, reaches a safe room, or outruns `GiveUpRange`.
local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Animator:Resume()
	npc:StopMirroring()
	npc:SetSpeed(npc.Config.ChaseSpeed)

	-- The only moment a player can be said to have met a Mimic. Everything before this looked like
	-- another guest, which is why `DiscoveryConfig` gives this one no sighting rule at all: unlocking
	-- its card for having looked at it would print the word "Mimic" in the index before the disguise
	-- had ever worked on anybody. It is discovered by dropping the act, or by killing you, and by
	-- nothing else.
	EnemyDiscoveryService:GrantEvent(target, npc.EnemyId)

	local lastKnown = npc.RootPart.Position
	local result = npc:Pursue(function()
		local position = npc:GetTargetPosition(target)
		if position then
			lastKnown = position
		end
		return position
	end, npc.Config.AttackRange, function()
		return npc:IsTouchingPlayer(target)
	end, function()
		return npc:HasLineOfSightToPlayer(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	return "Search", npc, lastKnown
end

--- Lands the killing blow and puts on the victim, or drops back to chasing if they slipped out of reach.
local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc:StopMirroring()
	npc:StopMoving()

	local position = npc:GetTargetPosition(target)
	if not position then
		return "Search", npc, npc.RootPart.Position
	end

	npc:FaceTowards(position)
	-- Reach, not contact. Two humanoids that run into each other shove each other apart, so a strict
	-- touch test flickers off the moment it lands -- which sends this straight back to `Chase` to
	-- re-path from a standstill, and reads as the mimic pulling up next to you and hesitating.
	if (npc.RootPart.Position - position).Magnitude > npc.Config.AttackRange
		and not npc:IsTouchingPlayer(target)
	then
		return "Chase", npc, target
	end

	npc:Attack(target)
	npc:AssumeIdentity(target)
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

--- Sweeps to where the target was last seen and loiters there before the mask goes back on.
local function search(_changeState: StateMachine.ChangeState, npc: any, lastKnown: Vector3)
	npc.Target = nil
	npc.Animator:Resume()
	npc:StopMirroring()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:WalkTo(lastKnown)
	npc:StopMoving()

	local until_ = os.clock() + npc.Config.LoseInterestTime
	while os.clock() < until_ do
		local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * LOOK_AROUND_DISTANCE
		npc:FaceTowards(npc.RootPart.Position + offset)
		task.wait(npc.Config.SearchLookInterval)
	end

	return "Idle", npc
end

--- Held still by a trap or a paper ball. Takes the rig back first: a stunned mimic that a client is
--- still driving would keep swivelling on the spot.
local function stunned(changeState: StateMachine.ChangeState, npc: any, duration: number)
	npc:StopMirroring()
	return NPC.SharedStates.Stunned(changeState, npc, duration)
end

function Mimic.new(model: Model, config)
	local self = NPC.new(model, config, Mimic)

	self.Identity = nil :: Player?
	self.Mirroring = nil :: Player?
	self._appliedIdentity = nil :: Player?
	self._swapping = false

	return self
end

--- Movement -------------------------------------------------------------------------------------

--- Hands `target`'s own client the job of moving this mimic, and the rig to simulate it with. Their
--- machine knows their input on the frame they make it and renders the answer on the frame it
--- simulates it, which is the only way the mirroring arrives smooth on the screen that matters.
---
--- Only the act is delegated. Damage, the decision to charge, and the chase itself stay here, so the
--- worst a client that refuses to play along gets is a mimic that stands there until it charges.
function Mimic:StartMirroring(target: Player)
	if self.Mirroring == target then return end

	self:StopMirroring()
	self.Mirroring = target
	self.Humanoid.AutoRotate = false -- the client aims it by hand, at the person it is copying
	self.Animator:Stop() -- and animates it there too, where the rig's speed is known the frame it changes
	self:SetNetworkOwner(target)
	Mirror:FireClient(target, self.Model)
end

--- Takes the rig back. Safe to call when nothing is mirroring, which is why every other state opens
--- with it: a state can be cancelled mid-act, so this cannot live at the end of the stalk.
function Mimic:StopMirroring()
	self.Humanoid.AutoRotate = true
	if not self.Mirroring then return end

	local target = self.Mirroring
	self.Mirroring = nil
	self:SetNetworkOwner(nil)
	self.Animator:Start()
	Mirror:FireClient(target, nil)
end

--- Identity -------------------------------------------------------------------------------------

-- A player's live appearance, straight off their character where possible so the copy matches what
-- everyone in the server has actually been looking at.
local function getDescription(player: Player): HumanoidDescription?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid then
		local ok, description = pcall(humanoid.GetAppliedDescription, humanoid)
		if ok then return description end
	end

	local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
	return if ok then description else nil
end

--- Someone worth impersonating: preferably a player this mimic cannot currently see, so it does not
--- change face in front of the person it is copying. Falls back to anyone alive.
function Mimic:PickIdentity(): Player?
	local unseen, anyone = {}, {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if humanoid and humanoid.Health > 0 and player ~= self.Identity then
			table.insert(anyone, player)
			if not self:CanSee(player) then
				table.insert(unseen, player)
			end
		end
	end

	local candidates = if #unseen > 0 then unseen else anyone
	return if #candidates > 0 then candidates[math.random(#candidates)] else nil
end

--- Takes `player`'s name and avatar. Applying the description yields on asset loads, so the swap runs
--- off the state machine's thread -- a state cancelled mid-swap would leave a half-dressed mimic. A
--- second identity arriving during a swap is picked up by the same thread rather than racing it.
function Mimic:AssumeIdentity(player: Player)
	self.Identity = player
	if self._swapping then return end
	self._swapping = true

	task.spawn(function()
		while self.Active and self.Identity and self.Identity ~= self._appliedIdentity do
			local identity = self.Identity :: Player
			self.Model.Name = identity.Name
			self.Humanoid.DisplayName = identity.DisplayName

			local description = getDescription(identity)
			if description then
				pcall(self.Humanoid.ApplyDescription, self.Humanoid, description)
				self.Animator:Reload() -- the description may have brought its own animation package
			end
			self._appliedIdentity = identity
		end
		self._swapping = false
	end)
end

--- Lifecycle ------------------------------------------------------------------------------------

function Mimic:Start()
	NPC.Start(self)

	local identity = self:PickIdentity()
	if identity then
		self:AssumeIdentity(identity)
	end
end

function Mimic:Despawn()
	self:StopMirroring()
	NPC.Despawn(self)
end

function Mimic:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = loiter,
		Wander = NPC.SharedStates.Wander,
		Patrol = NPC.SharedStates.Patrol,
		Despawn = NPC.SharedStates.Despawn,
		Stalk = stalk,
		Chase = chase,
		Attack = attack,
		Search = search,
		Stunned = stunned,
	}, {
		-- Spotting someone starts the act, but nothing interrupts the act except the act ending.
		Perception = { "Idle", "Wander", "Patrol", "Search" },
		-- A trap or a paper ball lands whatever it is doing, including mid-performance.
		Impact = { "Idle", "Wander", "Patrol", "Search", "Stalk", "Chase", "Attack" },
	}, {
		Perception = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)

				-- Spawning into an empty server, or before anyone has loaded, leaves it wearing its
				-- own face; it puts one on as soon as there is one to take.
				if not npc.Identity then
					local identity = npc:PickIdentity()
					if identity then
						npc:AssumeIdentity(identity)
					end
				end

				local target = npc:GetNearestVisibleTarget()
				if target then
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				end
			end
		end,
	}, "Idle", self)
end

return Mimic
