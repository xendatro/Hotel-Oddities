local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathService = require(ReplicatedStorage.Services.MathService)
local CabinStage = require(ReplicatedStorage.Classes.EndingCutscene.CabinStage)
local StagedRig = require(ReplicatedStorage.Classes.EndingCutscene.StagedRig)

local Cast = {}
Cast.__index = Cast

local NECK = "Neck"
local IDLE_PACK = { Folder = "idle", Child = "Animation1" }
local WALK_PACK = { Folder = "walk", Child = "WalkAnim" }

type Place = { At: Vector3, Facing: Vector3, Tilt: number? }
type Bend = { Pitch: number, Yaw: number, Roll: number, Time: number }

export type Settings = {
	StandIn: Place,
	Walk: { To: number, Speed: number, Accelerate: number, StrideScale: number, FadeFrom: number, FadeTo: number },
	LookUp: Bend,
	LookDown: Bend,
	Double: { [string]: any },
	Sisters: { Template: string, Facing: Vector3, Tilt: number, Steps: { { Vector3 } } },
}

export type Options = {
	Stage: CabinStage.CabinStage,
	Character: Model,
	Enemies: Instance?,
	Animations: Instance?,
	IdleName: string,
	WalkName: string,
	Parent: Instance,
	Settings: Settings,
}

type Walking = { StartedAt: number, From: number, Done: boolean }

type Spin = { StartedAt: number, From: number, Delta: number, Duration: number }

type Twitching = { EndsAt: number, NextAt: number }

export type Cast = typeof(setmetatable({} :: {
	Stage: CabinStage.CabinStage,
	Settings: Settings,
	StandIn: StagedRig.StagedRig?,
	Double: StagedRig.StagedRig?,
	Sisters: { StagedRig.StagedRig },
	Idle: Animation?,
	Walk: Animation?,
	Walking: Walking?,
	Spin: Spin?,
	FloatedAt: number?,
	DoubleYaw: number,
	Twitching: Twitching?,
	Random: Random,
	Clock: number,
	Destroyed: boolean,
}, Cast))

local function packId(copy: Model, pack: { Folder: string, Child: string }): string?
	local animate = copy:FindFirstChild("Animate")
	local value = animate and animate:FindFirstChild(pack.Folder)
	if not value then return nil end

	local preferred = value:FindFirstChild(pack.Child)
	if preferred and preferred:IsA("Animation") and preferred.AnimationId ~= "" then
		return preferred.AnimationId
	end
	for _, child in value:GetChildren() do
		if child:IsA("Animation") and child.AnimationId ~= "" then
			return child.AnimationId
		end
	end
	return nil
end

local function animationFrom(folder: Instance?, name: string, id: string?): Animation?
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA("Animation") then return nil end
	if not id or id == template.AnimationId then return template end

	local animation = template:Clone()
	animation.AnimationId = id
	return animation
end

local function enemy(folder: Instance?, name: string): Model?
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template:Clone()
	end
	warn(`[Cast] ReplicatedStorage.Enemies.{name} is missing; that figure is left out`)
	return nil
end

function Cast.new(options: Options): Cast
	local settings = options.Settings
	local self = setmetatable({
		Stage = options.Stage,
		Settings = settings,
		StandIn = nil :: StagedRig.StagedRig?,
		Double = nil :: StagedRig.StagedRig?,
		Sisters = {},
		Idle = nil :: Animation?,
		Walk = nil :: Animation?,
		Walking = nil :: Walking?,
		Spin = nil :: Spin?,
		FloatedAt = nil :: number?,
		DoubleYaw = 0,
		Twitching = nil :: Twitching?,
		Random = Random.new(),
		Clock = 0,
		Destroyed = false,
	}, Cast)

	local first = StagedRig.CloneCharacter(options.Character)
	if first then
		self.Idle = animationFrom(options.Animations, options.IdleName, packId(first, IDLE_PACK))
		self.Walk = animationFrom(options.Animations, options.WalkName, packId(first, WALK_PACK))
		self.StandIn = StagedRig.new(first, options.Parent)
	end
	local second = StagedRig.CloneCharacter(options.Character)
	if second then
		self.Double = StagedRig.new(second, options.Parent)
	end

	for side = -1, 1, 2 do
		local model = enemy(options.Enemies, settings.Sisters.Template)
		if not model then break end
		local sister = StagedRig.new(model, options.Parent)
		sister:Bend(NECK, 0, 0, -side * settings.Sisters.Tilt)
		table.insert(self.Sisters, sister)
	end
	self:SistersStep(1)

	return self
end

function Cast:_put(rig: StagedRig.StagedRig?, place: Place)
	if not rig then return end
	rig:Place(self.Stage:Frame(place.At, place.Facing, rig:RootHeight()))
	rig:SetVisible(true)
end

function Cast:Opening()
	local standIn = self.StandIn
	self:_put(standIn, self.Settings.StandIn)
	if standIn then
		standIn:Play(self.Idle, Enum.AnimationPriority.Idle, 0)
	end
	for _, sister in self.Sisters do
		sister:SetVisible(true)
	end
end

function Cast:SistersStep(index: number)
	local settings = self.Settings.Sisters
	local step = settings.Steps[index]
	if not step then return end

	for number, sister in self.Sisters do
		local place = step[number]
		if place then
			sister:Place(self.Stage:Frame(place, settings.Facing, sister:RootHeight()))
		end
	end
end

function Cast:ClearCorridor()
	for _, sister in self.Sisters do
		sister:Destroy()
	end
	table.clear(self.Sisters)
end

function Cast:Look(bend: Bend)
	local standIn = self.StandIn
	if standIn then
		standIn:Bend(NECK, bend.Pitch, bend.Yaw, bend.Roll, bend.Time)
	end
end

function Cast:DoubleAt(name: string)
	local place = self.Settings.Double[name]
	local double = self.Double
	if not place or not double then return end
	self:_put(double, place)
	double:Bend(NECK, 0, 0, place.Tilt or 0, 0)
end

function Cast:HideDouble()
	local double = self.Double
	if double then
		double:SetVisible(false)
	end
end

function Cast:StartWalk()
	local standIn = self.StandIn
	if not standIn or self.Walking then return end
	self.Walking = { StartedAt = self.Clock, From = self.Settings.StandIn.At.Z, Done = false }
	standIn:Stop(self.Idle, 0.3)
	standIn:Play(self.Walk, Enum.AnimationPriority.Movement, 0.3)
end

function Cast:Kept()
	local standIn = self.StandIn
	if standIn then
		standIn:SetVisible(false)
	end
	local double = self.Double
	if not double then return end
	self:DoubleAt("Kept")
	local bow = self.Settings.Double.Bow
	double:Bend(NECK, bow.Pitch, bow.Yaw, bow.Roll, 0)
end

function Cast:_yaw(facing: Vector3): number
	local direction = self.Stage:Direction(Vector3.new(facing.X, 0, facing.Z))
	return math.atan2(-direction.X, -direction.Z)
end

function Cast:SpinDouble()
	local settings = self.Settings.Double
	local from = self:_yaw(settings.Kept.Facing)
	local difference = self:_yaw(settings.Spin.Facing) - from
	local shortest = math.atan2(math.sin(difference), math.cos(difference))
	local direction = if shortest < 0 then -1 else 1
	self.DoubleYaw = from
	self.Spin = {
		StartedAt = self.Clock,
		From = from,
		Delta = shortest + direction * MathService.TAU * settings.Spin.ExtraTurns,
		Duration = math.max(settings.Spin.Time, 1e-3),
	}
end

function Cast:FloatDouble()
	self.FloatedAt = self.Clock
end

function Cast:Twitch(duration: number)
	self.Twitching = { EndsAt = self.Clock + duration, NextAt = self.Clock }
end

function Cast:_stepDouble()
	local double = self.Double
	if not double then return end

	local spin = self.Spin
	if spin then
		local alpha = math.clamp((self.Clock - spin.StartedAt) / spin.Duration, 0, 1)
		self.DoubleYaw = spin.From + spin.Delta * MathService.Eases.InOutCubic(alpha)
		if alpha >= 1 then
			self.Spin = nil
		end
	end

	local floatedAt = self.FloatedAt
	if spin or floatedAt then
		local float = self.Settings.Double.Float
		local lift = 0
		if floatedAt then
			local elapsed = self.Clock - floatedAt
			local rise = math.clamp(elapsed / math.max(float.RiseTime, 1e-3), 0, 1)
			lift = float.Rise * MathService.Eases.OutQuad(rise)
			if elapsed > float.RiseTime then
				lift += float.Bob * math.sin((elapsed - float.RiseTime) * MathService.TAU / float.BobPeriod)
			end
		end
		local base = self.Stage:ToWorld(self.Settings.Double.Kept.At) + Vector3.yAxis * (double:RootHeight() + lift)
		double:Place(CFrame.new(base) * CFrame.Angles(0, self.DoubleYaw, 0))
	end

	local twitching = self.Twitching
	if not twitching then return end
	if self.Clock >= twitching.EndsAt then
		self.Twitching = nil
		double:SetOffset(NECK, CFrame.identity)
		return
	end
	if self.Clock < twitching.NextAt then return end

	local twitch = self.Settings.Double.Twitch
	local random = self.Random
	double:SetOffset(NECK, CFrame.fromEulerAnglesYXZ(
		math.rad(random:NextNumber(-twitch.Pitch, twitch.Pitch)),
		math.rad(random:NextNumber(-twitch.Yaw, twitch.Yaw)),
		math.rad(random:NextNumber(-twitch.Roll, twitch.Roll))
	))
	twitching.NextAt = self.Clock + random:NextNumber(twitch.Gap[1], twitch.Gap[2])
end

function Cast:DoubleNeck(name: string)
	local double = self.Double
	local bend = self.Settings.Double[name]
	if double and bend then
		double:Bend(NECK, bend.Pitch, bend.Yaw, bend.Roll, bend.Time)
	end
end

function Cast:_stepWalk()
	local walking = self.Walking
	local standIn = self.StandIn
	if not walking or walking.Done or not standIn then return end

	local settings = self.Settings.Walk
	local elapsed = self.Clock - walking.StartedAt
	local ramp = math.max(settings.Accelerate, 1e-3)
	local speed, distance
	if elapsed < ramp then
		speed = settings.Speed * elapsed / ramp
		distance = 0.5 * speed * elapsed
	else
		speed = settings.Speed
		distance = 0.5 * settings.Speed * ramp + settings.Speed * (elapsed - ramp)
	end

	local forward = math.min(walking.From + distance, settings.To)
	local place = self.Settings.StandIn
	standIn:Place(self.Stage:Frame(Vector3.new(place.At.X, 0, forward), place.Facing, standIn:RootHeight()))

	local walk = self.Walk
	local track = walk and standIn.Tracks[walk]
	if track then
		track:AdjustSpeed(math.max(speed * settings.StrideScale, 0.05))
	end

	local span = math.max(settings.FadeTo - settings.FadeFrom, 1e-3)
	standIn:SetFade(math.clamp((forward - settings.FadeFrom) / span, 0, 1))
	if forward >= settings.To then
		walking.Done = true
		standIn:SetVisible(false)
	end
end

function Cast:Update(deltaTime: number)
	if self.Destroyed then return end
	self.Clock += deltaTime
	self:_stepWalk()
	self:_stepDouble()

	local rigs = { self.StandIn, self.Double }
	for _, rig in rigs do
		if rig then
			rig:Update(deltaTime)
		end
	end
	for _, sister in self.Sisters do
		sister:Update(deltaTime)
	end
end

function Cast:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self:ClearCorridor()
	local standIn, double = self.StandIn, self.Double
	self.StandIn, self.Double = nil, nil
	if standIn then
		standIn:Destroy()
	end
	if double then
		double:Destroy()
	end
end

return Cast
