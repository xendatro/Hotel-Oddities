local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.MapOddityConfig)
local Hallways = require(ReplicatedStorage.Modules.Hallways)

local MapOddityService = {}

-- Studio edit mode can require server modules while syncing or inspecting the place.
-- Do not create remotes, start schedulers, or mutate map parts until the game is running.
if RunService:IsStudio() and not RunService:IsRunning() then
	function MapOddityService:Trigger(_position: Vector3, _kind: string?): (boolean, string?, string?)
		return false, nil, "map oddities are disabled in Studio edit mode"
	end

	function MapOddityService:Clear(_token: number?): boolean
		return false
	end

	function MapOddityService:GetActive(): { [number]: any }
		return {}
	end

	return MapOddityService
end

local LightService = require(game:GetService("ServerStorage").Services.LightService)

local function getMapDoorsRemote(): RemoteEvent
	local communication = ReplicatedStorage:FindFirstChild("Communication")
	if not communication then
		communication = Instance.new("Folder")
		communication.Name = "Communication"
		communication.Parent = ReplicatedStorage
	end

	local oddities = communication:FindFirstChild("Oddities")
	if not oddities then
		oddities = Instance.new("Folder")
		oddities.Name = "Oddities"
		oddities.Parent = communication
	end

	local remote = oddities:FindFirstChild("MapDoors")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "MapDoors"
		remote.Parent = oddities
	end
	return remote :: RemoteEvent
end

if not Config.Enabled then
	function MapOddityService:Trigger(_position: Vector3, _kind: string?): (boolean, string?, string?)
		return false, nil, "map oddities are disabled"
	end

	function MapOddityService:Clear(_token: number?): boolean
		return false
	end

	return MapOddityService
end

local MapDoors = getMapDoorsRemote()

type ActiveEffect = {
	Token: number,
	Kind: string,
	Span: Hallways.StraightSpan,
	BoxCFrame: CFrame,
	BoxSize: Vector3,
	Parts: { [BasePart]: boolean },
	Added: RBXScriptConnection?,
	LightClaim: any?,
}

type TransparencyClaim = {
	Original: number,
	Count: number,
}

local active: { [number]: ActiveEffect } = {}
local transparencyClaims: { [BasePart]: TransparencyClaim } = {}
local nextToken = 0

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

local function setting(kind: string, name: string, fallback: number): number
	local effectConfig = Config.Effects[kind]
	local value = effectConfig and effectConfig[name]
	return if type(value) == "number" then value else Config[name] or fallback
end

local function sameSpan(first: Hallways.StraightSpan, second: Hallways.StraightSpan): boolean
	local sameDirection = (first.Start - second.Start).Magnitude <= Config.SpatialPadding
		and (first.Finish - second.Finish).Magnitude <= Config.SpatialPadding
	local oppositeDirection = (first.Start - second.Finish).Magnitude <= Config.SpatialPadding
		and (first.Finish - second.Start).Magnitude <= Config.SpatialPadding
	return sameDirection or oppositeDirection
end

local function hallwayWidth(span: Hallways.StraightSpan): number
	local width = 0
	for _, hallway in Hallways.All() do
		local candidate = Hallways.StraightSpanAt(hallway.Center, span.Axis)
		if candidate and sameSpan(candidate, span) then
			width = math.max(width, hallway.HalfWidth)
		end
	end

	if width > 0 then return width end
	local nearest = Hallways.Nearest(span.Center)
	return if nearest then nearest.HalfWidth else 0
end

local function floorY(span: Hallways.StraightSpan): number
	local hallway = Hallways.Nearest(span.Center)
	return if hallway then hallway.FloorY else span.Center.Y
end

local function boxForSpan(span: Hallways.StraightSpan): (CFrame, Vector3)
	local heightWindow = math.max(Config.HallwayHeightWindow, 0)
	local belowWindow = math.max(Config.HallwayBelowWindow, 0)
	local floor = floorY(span)
	local center = Vector3.new(
		span.Center.X,
		floor + (heightWindow - belowWindow) / 2,
		span.Center.Z
	)
	local padding = math.max(Config.SpatialPadding, 0)
	local width = hallwayWidth(span)
	local cframe = CFrame.lookAt(center, center + span.Axis, Vector3.yAxis)
	local size = Vector3.new(
		width * 2 + padding * 2,
		heightWindow + belowWindow,
		span.Length + padding * 2
	)
	return cframe, size
end

local function isCharacterPart(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function isEligible(part: BasePart): boolean
	return part:IsDescendantOf(workspace)
		and not part:HasTag("TransparencyIgnore")
		and not isCharacterPart(part)
end

local function overlapFraction(part: BasePart, cframe: CFrame, size: Vector3): number
	local relative = cframe:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local extent = Vector3.new(
		math.abs(relative.RightVector.X) * half.X
			+ math.abs(relative.UpVector.X) * half.Y
			+ math.abs(relative.LookVector.X) * half.Z,
		math.abs(relative.RightVector.Y) * half.X
			+ math.abs(relative.UpVector.Y) * half.Y
			+ math.abs(relative.LookVector.Y) * half.Z,
		math.abs(relative.RightVector.Z) * half.X
			+ math.abs(relative.UpVector.Z) * half.Y
			+ math.abs(relative.LookVector.Z) * half.Z
	)
	local partMinimum = relative.Position - extent
	local partMaximum = relative.Position + extent
	local boxHalf = size / 2
	local overlap = Vector3.new(
		math.max(0, math.min(partMaximum.X, boxHalf.X) - math.max(partMinimum.X, -boxHalf.X)),
		math.max(0, math.min(partMaximum.Y, boxHalf.Y) - math.max(partMinimum.Y, -boxHalf.Y)),
		math.max(0, math.min(partMaximum.Z, boxHalf.Z) - math.max(partMinimum.Z, -boxHalf.Z))
	)
	local volume = extent.X * extent.Y * extent.Z * 8
	return if volume > 0 then overlap.X * overlap.Y * overlap.Z / volume else 0
end

local function applyPart(effect: ActiveEffect, part: BasePart)
	if effect.Parts[part] or not isEligible(part) then return end
	if overlapFraction(part, effect.BoxCFrame, effect.BoxSize) < Config.MinimumPartHallwayFraction then
		return
	end

	local claim = transparencyClaims[part]
	if not claim then
		local original = part.Transparency
		if original >= Config.HallwayTransparency then return end
		claim = { Original = original, Count = 0 }
		transparencyClaims[part] = claim
	end

	claim.Count += 1
	effect.Parts[part] = true
	part.Transparency = Config.HallwayTransparency
end

local function queryParts(effect: ActiveEffect)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = {}

	local seen: { [BasePart]: boolean } = {}
	local parts = workspace:GetPartBoundsInBox(effect.BoxCFrame, effect.BoxSize, overlap)
	for _, part in parts do
		seen[part] = true
		applyPart(effect, part)
	end

	-- GetPartBoundsInBox skips parts with CanQuery disabled. The fallback keeps those decorations
	-- included, while applyPart still enforces the same majority-in-hallway test.
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and not seen[instance] and not instance.CanQuery then
			applyPart(effect, instance)
		end
	end
end

local function releaseParts(effect: ActiveEffect)
	for part in effect.Parts do
		local claim = transparencyClaims[part]
		if claim then
			claim.Count -= 1
			if claim.Count <= 0 then
				if part.Parent and part.Transparency == Config.HallwayTransparency then
					part.Transparency = claim.Original
				end
				transparencyClaims[part] = nil
			end
		end
	end
	table.clear(effect.Parts)
end

local function clearEffect(effect: ActiveEffect)
	if active[effect.Token] ~= effect then return end
	active[effect.Token] = nil

	if effect.Added then
		effect.Added:Disconnect()
		effect.Added = nil
	end

	if effect.Kind == "Transparency" then
		releaseParts(effect)
	elseif effect.Kind == "DoorsOpen" then
		MapDoors:FireAllClients("Stop", effect.Token)
	elseif effect.Kind == "HallwayChaos" then
		if effect.LightClaim then
			LightService:ReleaseFlicker(effect.LightClaim)
			effect.LightClaim = nil
		end
		MapDoors:FireAllClients("Stop", effect.Token)
	end
end

function MapOddityService:Clear(token: number?): boolean
	if token then
		local effect = active[token]
		if not effect then return false end
		clearEffect(effect)
		return true
	end

	local effects = {}
	for _, effect in active do
		table.insert(effects, effect)
	end
	for _, effect in effects do
		clearEffect(effect)
	end
	return #effects > 0
end

local function start(span: Hallways.StraightSpan, kind: string): boolean
	nextToken += 1
	local boxCFrame, boxSize = boxForSpan(span)
	local effect: ActiveEffect = {
		Token = nextToken,
		Kind = kind,
		Span = span,
		BoxCFrame = boxCFrame,
		BoxSize = boxSize,
		Parts = {},
		Added = nil,
		LightClaim = nil,
	}
	active[effect.Token] = effect
	local duration = randomRange(
		math.max(setting(kind, "MinDuration", 45), 0),
		math.max(setting(kind, "MaxDuration", 120), 0)
	)

	if kind == "Transparency" then
		queryParts(effect)
		effect.Added = workspace.DescendantAdded:Connect(function(instance: Instance)
			if instance:IsA("BasePart") then
				applyPart(effect, instance)
			end
		end)
	elseif kind == "DoorsOpen" then
		MapDoors:FireAllClients(
			"Start",
			effect.Token,
			effect.BoxCFrame,
			effect.BoxSize,
			math.clamp(setting(kind, "OpeningSpeed", 0.75), 0.05, 4)
		)
	elseif kind == "HallwayChaos" then
		effect.LightClaim = LightService:FlickerChaosAlongHallway(
			span.Center,
			duration,
			math.max(setting(kind, "LightIntervalMin", 0.06), 0.02),
			math.max(setting(kind, "LightIntervalMax", 0.24), 0.03)
		)
		MapDoors:FireAllClients(
			"Start",
			effect.Token,
			effect.BoxCFrame,
			effect.BoxSize,
			math.clamp(setting(kind, "OpeningSpeed", 1.2), 0.05, 4),
			"Chaos",
			math.clamp(setting(kind, "ClosingSpeed", 1.2), 0.05, 4),
			math.max(setting(kind, "DoorIntervalMin", 0.3), 0.05),
			math.max(setting(kind, "DoorIntervalMax", 1.1), 0.06)
		)
	end

	task.delay(duration, function()
		clearEffect(effect)
	end)
	return true
end

local function spanAt(position: Vector3): Hallways.StraightSpan?
	if not Hallways.At(position) then return nil end
	return Hallways.StraightSpanAt(position)
end

local function playerInSpan(span: Hallways.StraightSpan): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local playerSpan = spanAt(root.Position)
			if playerSpan and sameSpan(playerSpan, span) then return true end
		end
	end
	return false
end

--- Starts one map oddity at the hallway containing `position`.
function MapOddityService:Trigger(position: Vector3, kind: string?): (boolean, string?, string?)
	if not Config.Enabled then return false, nil, "map oddities are disabled" end

	local chosen = kind or "Transparency"
	if not Config.Effects[chosen] then
		return false, nil, "unknown effect; use transparency, doors, or chaos"
	end

	local span = spanAt(position)
	if not span then return false, nil, "that position is not in a usable hallway" end
	if (chosen == "DoorsOpen" or chosen == "HallwayChaos") and not playerInSpan(span) then
		return false, nil, "doors need a living player in that hallway"
	end
	if not start(span, chosen) then return false, nil, "could not start that oddity" end
	return true, chosen, nil
end

function MapOddityService:GetActive(): { [number]: ActiveEffect }
	return active
end

local function randomSpan(): Hallways.StraightSpan?
	local spans = Hallways.StraightSpans()
	if #spans == 0 then return nil end

	local distant = {}
	for _, span in spans do
		local farEnough = true
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0
				and (root.Position - span.Center).Magnitude < Config.MinimumPlayerDistance
			then
				farEnough = false
				break
			end
		end
		if farEnough then table.insert(distant, span) end
	end

	local choices = if #distant > 0 then distant else spans
	return choices[math.random(1, #choices)]
end

local function randomPlayerSpan(): Hallways.StraightSpan?
	local spans = {}
	for _, span in Hallways.StraightSpans() do
		if playerInSpan(span) then table.insert(spans, span) end
	end
	if #spans == 0 then return nil end
	return spans[math.random(1, #spans)]
end

local function roll(kind: string)
	if math.random() > setting(kind, "TriggerChance", 0.15) then return end

	local span = if kind == "DoorsOpen" or kind == "HallwayChaos" then randomPlayerSpan() else randomSpan()
	if span then start(span, kind) end
end

for kind in Config.Effects do
	task.spawn(function()
		task.wait(math.max(setting(kind, "InitialDelay", 45), 0))
		while true do
			roll(kind)
			task.wait(math.max(setting(kind, "RollInterval", 45), 1))
		end
	end)
end

return MapOddityService
