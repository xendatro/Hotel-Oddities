local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Probe = {}

local ANALYZER_NAME = "PlaytestAnalyzer"

function Probe.listener(): AudioListener?
	local camera = workspace.CurrentCamera
	local onCamera = camera and camera:FindFirstChildOfClass("AudioListener")
	if onCamera then return onCamera end

	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("AudioListener") then return descendant end
	end
	return nil
end

-- The listener normally rides the Camera and tracks the character fine. It has
-- been seen parked hundreds of studs away mid-session though, so pin it to the
-- character rather than assuming. Check Probe.listenerDistance() either way.
function Probe.attachToCharacter(player: Player?)
	local listener = Probe.listener()
	if not listener then return nil, "no AudioListener in the place" end

	local target = player or Players.LocalPlayer
	local character = target and target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil, "no HumanoidRootPart to attach to" end

	local home = listener.Parent
	listener.Parent = root
	return function()
		if listener.Parent then
			listener.Parent = home
		end
	end
end

-- Any audio measurement taken while this is large is measuring the wrong place.
function Probe.listenerDistance(player: Player?): number?
	local listener = Probe.listener()
	local parent = listener and listener.Parent
	if not parent then return nil end

	local target = player or Players.LocalPlayer
	local character = target and target.Character
	if not character then return nil end

	local at = if parent:IsA("BasePart") then parent.Position else (parent :: any).CFrame.Position
	return (at - character:GetPivot().Position).Magnitude
end

function Probe.audio(): AudioAnalyzer?
	local listener = Probe.listener()
	if not listener then return nil end

	local existing = listener:FindFirstChild(ANALYZER_NAME)
	if existing and existing:IsA("AudioAnalyzer") then return existing end

	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.Name = ANALYZER_NAME
	analyzer.Parent = listener

	local wire = Instance.new("Wire")
	wire.SourceInstance = listener
	wire.TargetInstance = analyzer
	wire.Parent = analyzer
	return analyzer
end

function Probe.level(): number
	local analyzer = Probe.audio()
	return if analyzer then analyzer.RmsLevel else 0
end

function Probe.window(seconds: number, interval: number?)
	local analyzer = Probe.audio()
	if not analyzer then return nil end

	local values = {}
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		table.insert(values, analyzer.RmsLevel)
		task.wait(interval or 0.1)
	end

	local sum, high = 0, 0
	for _, value in values do
		sum += value
		high = math.max(high, value)
	end
	local function round(n: number)
		return math.round(n * 10000) / 10000
	end
	return { n = #values, mean = round(sum / #values), max = round(high) }
end

-- Never assert on a value the code just wrote. Measure the effect present
-- against the effect absent.
function Probe.compare(seconds: number, action: () -> (() -> ())?)
	local before = Probe.window(seconds)
	local undo = action()
	task.wait(0.75)
	local after = Probe.window(seconds)
	if undo then undo() end
	return { before = before, after = after }
end

function Probe.emitters(root: Instance?)
	local out = {}
	for _, descendant in (root or workspace):GetDescendants() do
		if not descendant:IsA("AudioEmitter") then continue end

		local player = descendant:FindFirstChildOfClass("AudioPlayer")
		table.insert(out, string.format("%s vol=%s playing=%s bounds=%s mode=%s",
			descendant:GetFullName(),
			if player then string.format("%.3f", player.Volume) else "-",
			if player then tostring(player.IsPlaying) else "-",
			tostring(descendant.DistanceAttenuationBounds),
			tostring(descendant.DistanceAttenuationMode)))
	end
	return out
end

function Probe.assertClient()
	if not RunService:IsClient() then
		error("Playtest.Probe only works on the Client datamodel", 2)
	end
end

return Probe
