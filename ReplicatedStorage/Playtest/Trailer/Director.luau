-- Plays one trailer shot from Trailer/Shots on the local client: hides every
-- interface, parks and hides the character, holds the first frame while the
-- lighting settles, then runs the shot's camera track, events and staging on
-- a clock that Timecode burns into each frame. Restores everything after.
--
-- Called through Bridge.client:
--   Director.Play("Arrival", { Warmup = 3, HoldAt = 1.5 })
--   Director.Stop()   Director.Status()   Director.List()
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraTrack = require(ReplicatedStorage.Classes.CameraTrack)
local InterfaceHideService = require(ReplicatedStorage.Services.InterfaceHideService)
local Stage = require(script.Parent.Stage)
local Timecode = require(script.Parent.Timecode)

local Director = {}

local BIND = "TrailerDirector"
local PRIORITY = Enum.RenderPriority.Last.Value + 50
local DEFAULT_WARMUP = 3
local DEFAULT_TAIL = 0.4
local STREAM_TIMEOUT = 4
local PRELOAD_TIMEOUT = 15

local player = Players.LocalPlayer

type Run = {
	Name: string,
	Shot: any,
	Stage: any,
	Context: any,
	Track: any,
	Phase: string,
	Time: number,
	Started: number?,
	Options: { [string]: any },
	EventIndex: number,
	Restore: { () -> () },
	Hold: (() -> ())?,
}

local current: Run? = nil
local sequence: any = nil

local function shotsFolder(): Instance
	return script.Parent:FindFirstChild("Shots") :: Instance
end

local function character(): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	if not model then return nil end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return model, (humanoid and humanoid.RootPart) or model:FindFirstChild("HumanoidRootPart") :: BasePart?, humanoid
end

local function sortedEvents(shot: any): { any }
	local events = table.clone(shot.Events or {})
	table.sort(events, function(a, b)
		return a.Time < b.Time
	end)
	return events
end

local function cleanup(run: Run)
	RunService:UnbindFromRenderStep(BIND)
	if run.Shot.Cleanup then
		pcall(run.Shot.Cleanup, run.Stage, run.Context)
	end
	pcall(function()
		run.Stage:Destroy()
	end)
	for index = #run.Restore, 1, -1 do
		local ok, err = pcall(run.Restore[index])
		if not ok then
			warn(`[Trailer] restore failed: {err}`)
		end
	end
	Timecode.Destroy()
	if current == run then
		current = nil
	end
	print(`[Trailer] {run.Name} restored`)
end

local function prepareCharacter(run: Run, park: CFrame?)
	local model, root, humanoid = character()
	if not model or not root then return end
	if humanoid then
		humanoid:UnequipTools()
	end
	local anchored = root.Anchored
	local pivot = model:GetPivot()
	root.Anchored = true
	if park then
		model:PivotTo(park)
	end
	table.insert(run.Restore, function()
		if root.Parent then
			model:PivotTo(pivot)
			root.Anchored = anchored
		end
	end)
end

local function prepareCamera(run: Run)
	local camera = workspace.CurrentCamera
	local cameraType = camera.CameraType
	local fov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	local mouseIcon = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false
	table.insert(run.Restore, function()
		camera.CameraType = cameraType
		camera.FieldOfView = fov
		UserInputService.MouseIconEnabled = mouseIcon
	end)
end

local function prepareInterface(run: Run)
	local hold, restore = InterfaceHideService.Capture({ Exclude = { Timecode.Gui() }, HideNew = true })
	run.Hold = hold
	table.insert(run.Restore, restore)
end

local function preload(run: Run)
	local assets: { any } = { run.Stage.Folder }
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	if effects then
		table.insert(assets, effects)
	end
	for _, id in run.Shot.Preload or {} do
		table.insert(assets, if type(id) == "number" then `rbxassetid://{id}` else id)
	end
	local started = os.clock()
	pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
	for _, rig in run.Stage.Rigs do
		for _, track in rig.Tracks do
			while track.Length <= 0 and os.clock() - started < PRELOAD_TIMEOUT do
				task.wait()
			end
		end
	end
	print(`[Trailer] {run.Name} preloaded in {math.floor((os.clock() - started) * 100) / 100}s`)
end

local function stream(points: { Vector3 })
	for _, point in points do
		pcall(player.RequestStreamAroundAsync, player, point, STREAM_TIMEOUT)
	end
end

local function fire(run: Run, events: { any }, time: number)
	while true do
		local event = events[run.EventIndex]
		if not event or event.Time > time then return end
		run.EventIndex += 1
		local ok, err = pcall(event.Run, run.Stage, run.Context, time)
		if not ok then
			warn(`[Trailer] {run.Name} event at {event.Time} failed: {err}`)
		end
	end
end

local function render(run: Run, time: number, dt: number)
	local camera = workspace.CurrentCamera
	if run.Shot.Update then
		local ok, err = pcall(run.Shot.Update, run.Stage, run.Context, time, dt)
		if not ok then
			warn(`[Trailer] {run.Name} update failed: {err}`)
		end
	end
	local frame, fov
	local track = run.Track
	if track.Channels.Yaw then
		local position = track:Sample("Position", time) or Vector3.zero
		local yaw = math.rad(track:Sample("Yaw", time) or 0)
		local pitch = math.rad(track:Sample("Pitch", time) or 0)
		local roll = math.rad(track:Sample("Roll", time) or 0)
		frame = CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll) * track:_handheld(time, time)
		fov = track:Sample("Fov", time) or 70
	else
		frame, fov = track:Evaluate(time)
	end
	if run.Shot.Camera then
		frame, fov = run.Shot.Camera(run.Stage, run.Context, time, frame, fov)
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.CFrame = frame
	camera.Focus = run.Track:GetFocus(frame)
	camera.FieldOfView = fov
	if run.Hold then
		run.Hold()
	end
end

local function play(run: Run)
	local shot = run.Shot
	local options = run.Options

	prepareInterface(run)
	Timecode.Set(0, false, options.Id)
	prepareCamera(run)
	local park = if type(shot.Park) == "function" then shot.Park(options) else shot.Park
	prepareCharacter(run, park)
	run.Stage:Isolate()

	local streamPoints = table.clone(shot.Stream or {})
	if park then
		table.insert(streamPoints, park.Position)
	end
	stream(streamPoints)

	if shot.Setup then
		run.Context = shot.Setup(run.Stage, options) or {}
	else
		run.Context = {}
	end
	preload(run)
	local keys = if type(shot.Keys) == "function" then shot.Keys(run.Stage, run.Context, options) else shot.Keys
	run.Track = CameraTrack.new(keys, {
		Handheld = shot.Handheld,
		FocusDistance = shot.FocusDistance,
		Anchors = if type(shot.Anchors) == "function" then shot.Anchors(run.Stage, run.Context) else shot.Anchors,
	})

	local events = sortedEvents(shot)
	local warmup = options.Warmup or shot.Warmup or DEFAULT_WARMUP
	local duration = shot.Duration
	local tail = shot.Tail or DEFAULT_TAIL
	local speed = options.Speed or 1
	local warmStart = os.clock()

	run.Phase = "warmup"
	RunService:BindToRenderStep(BIND, PRIORITY, function(dt)
		if current ~= run then return end
		local now = os.clock()

		if run.Phase == "warmup" then
			if shot.Warm then
				pcall(shot.Warm, run.Stage, run.Context, now - warmStart)
			end
			render(run, 0, dt)
			Timecode.Set(0, false, options.Id)
			if now - warmStart >= warmup then
				run.Phase = "running"
				run.Started = now
			end
			return
		end

		local time = (now - (run.Started :: number)) * speed
		if options.HoldAt then
			time = math.min(time, options.HoldAt)
		end
		run.Time = time

		if run.Phase == "running" then
			fire(run, events, time)
			render(run, math.min(time, duration + tail), dt)
			Timecode.Set(time, time <= duration + tail, options.Id)
			if time > duration + tail and not options.HoldAt then
				run.Phase = "done"
				task.defer(function()
					task.wait(0.25)
					if current == run and not options.Keep then
						cleanup(run)
					end
				end)
			end
		else
			render(run, duration + tail, dt)
			Timecode.Set(duration + tail, false, options.Id)
		end
	end)
end

function Director.Play(name: string, options: { [string]: any }?): string
	if current then
		cleanup(current)
	end
	local module = shotsFolder():FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `no trailer shot {name}`)
	local shot = require(module) :: any

	local run: Run = {
		Name = name,
		Shot = shot,
		Stage = Stage.new(name),
		Context = nil,
		Track = nil,
		Phase = "setup",
		Time = 0,
		Started = nil,
		Options = options or {},
		EventIndex = 1,
		Restore = {},
		Hold = nil,
	}
	current = run
	task.spawn(function()
		local ok, err = pcall(play, run)
		if not ok then
			warn(`[Trailer] {name} failed to start: {err}`)
			cleanup(run)
		end
	end)
	return `playing {name}`
end

function Director.Sequence(names: { string }, options: { [string]: any }?): string
	local token = {}
	sequence = token
	task.spawn(function()
		for index, name in names do
			if sequence ~= token then return end
			local settings = table.clone(options or {})
			settings.Id = index
			Director.Play(name, settings)
			local run = current
			while sequence == token and current == run and run ~= nil do
				task.wait(0.1)
			end
			task.wait(0.4)
		end
		if sequence == token then
			sequence = nil
			print("[Trailer] sequence finished")
		end
	end)
	return `sequence of {#names} shots`
end

function Director.Stop(): string
	sequence = nil
	local run = current
	if not run then return "idle" end
	cleanup(run)
	return `stopped {run.Name}`
end

function Director.Status(): { [string]: any }
	local run = current
	if not run then return { Phase = "idle", Sequence = sequence ~= nil } end
	return { Name = run.Name, Phase = run.Phase, Time = run.Time, Duration = run.Shot.Duration, Sequence = sequence ~= nil }
end

function Director.List(): { string }
	local names = {}
	for _, module in shotsFolder():GetChildren() do
		if module:IsA("ModuleScript") then
			table.insert(names, module.Name)
		end
	end
	table.sort(names)
	return names
end

return Director
