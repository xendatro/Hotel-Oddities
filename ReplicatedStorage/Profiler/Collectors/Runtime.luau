local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local Root = script.Parent.Parent
local Settings = require(Root.Config.Settings)
local Statistics = require(Root.Core.Statistics)
local Scope = require(Root.Core.Scope)
local Runtime = {}
Runtime.__index = Runtime

local groups = {
	render = { FrameTime = "engineFrameMs", RenderCPUFrameTime = "renderCpuMs", RenderGPUFrameTime = "renderGpuMs",
		SceneDrawcallCount = "sceneDrawCalls", SceneTriangleCount = "sceneTriangles",
		ShadowsDrawcallCount = "shadowDrawCalls", ShadowsTriangleCount = "shadowTriangles",
		UI2DDrawcallCount = "ui2dDrawCalls", UI2DTriangleCount = "ui2dTriangles",
		UI3DDrawcallCount = "ui3dDrawCalls", UI3DTriangleCount = "ui3dTriangles" },
	server = { HeartbeatTime = "heartbeatWorkMs", PhysicsStepTime = "physicsStepMs",
		ContactsCount = "contacts", MovingPrimitivesCount = "movingPrimitives", PrimitivesCount = "primitives" },
	network = { DataSendKbps = "sendKbps", DataReceiveKbps = "receiveKbps",
		PhysicsSendKbps = "physicsSendKbps", PhysicsReceiveKbps = "physicsReceiveKbps" },
	memory = { InstanceCount = "instances" },
}

function Runtime.new(options, player)
	local self = setmetatable({ options = options, player = player, frames = Statistics.New(Settings.MaxFrameSamples),
		streams = {}, rows = {}, connections = {}, unavailable = {}, churn = { added = 0, removed = 0 },
		client = RunService:IsClient(), collectorMs = 0, samplesDropped = 0, lostFocus = false }, Runtime)
	return self
end

function Runtime:Wants(group)
	return self.options.focus == "all" or self.options.focus == group
end

function Runtime:Add(key, value)
	if not Statistics.Finite(value) then return end
	if not self.streams[key] then self.streams[key] = Statistics.New(Settings.MaxSamples) end
	Statistics.Add(self.streams[key], value)
end

function Runtime:Sample()
	local start = os.clock()
	local row = { t = start - self.started }
	if self.client and self.player then
		local gui = self.player:FindFirstChild("PlayerGui")
		local panel = gui and gui:FindFirstChild("ProfilerUI")
		if panel and panel.Enabled then self.uiVisible = true end
	end
	for group, properties in groups do
		if not self:Wants(group) then continue end
		if group == "render" and not self.client then continue end
		for property, key in properties do
			if self.unavailable[key] then continue end
			local ok, value = pcall(function() return Stats[property] end)
			if ok and Statistics.Finite(value) then
				if string.sub(key, -2) == "Ms" then value *= 1000 end
				row[key] = value; self:Add(key, value)
			else self.unavailable[key] = tostring(value) end
		end
	end
	if self:Wants("memory") then
		local ok, value = pcall(Stats.GetTotalMemoryUsageMb, Stats)
		if ok then row.memoryMb = value; self:Add("memoryMb", value) end
		if Stats.MemoryTrackingEnabled then
			for _, tag in Enum.DeveloperMemoryTag:GetEnumItems() do
				local success, amount = pcall(Stats.GetMemoryUsageMbForTag, Stats, tag)
				local key = "memory." .. tag.Name .. "Mb"
				if success then row[key] = amount; self:Add(key, amount) end
			end
		else self.unavailable.memoryCategories = "MemoryTrackingEnabled is false; zero is not a measurement" end
		row.instancesAdded = self.churn.added; row.instancesRemoved = self.churn.removed
	end
	if self:Wants("network") and self.player and not self.unavailable.pingSeconds then
		local ok, value = pcall(self.player.GetNetworkPing, self.player)
		if ok then row.pingSeconds = value; self:Add("pingSeconds", value)
		else self.unavailable.pingSeconds = tostring(value) end
	end
	if #self.rows < Settings.MaxSamples then table.insert(self.rows, row) else self.samplesDropped += 1 end
	self.collectorMs += (os.clock() - start) * 1000
end

function Runtime:Start()
	self.started = os.clock()
	if self:Wants("functions") then self.scopeSession = Scope.Start(self.options.scopes) end
	local event = if self.client then RunService.RenderStepped else RunService.Heartbeat
	local firstFrame = true
	table.insert(self.connections, event:Connect(function(dt)
		if firstFrame then firstFrame = false; return end
		-- Intervals measure delivered cadence, not CPU execution. FPS is frames / time.
		Statistics.Add(self.frames, dt * 1000, self.options.frameBudgetMs)
	end))
	if self.client then
		table.insert(self.connections, UserInputService.WindowFocusReleased:Connect(function() self.lostFocus = true end))
		local ok, focused = pcall(function() return UserInputService:IsWindowFocused() end)
		self.focusAtStart = if ok then focused else "unknown"
	end
	if self:Wants("memory") then
		table.insert(self.connections, workspace.DescendantAdded:Connect(function() self.churn.added += 1 end))
		table.insert(self.connections, workspace.DescendantRemoving:Connect(function() self.churn.removed += 1 end))
	end
	self:Sample()
	local elapsed = 0
	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= Settings.SampleInterval then elapsed = 0; self:Sample() end
	end))
end

function Runtime:Stop()
	if self.result then return self.result end
	for _, connection in self.connections do connection:Disconnect() end
	local duration = os.clock() - self.started
	self:Sample()
	local metrics = {}
	for key, stream in self.streams do metrics[key] = Statistics.Summary(stream) end
	local frame = Statistics.Summary(self.frames)
	frame.over50 = self.frames.over50; frame.over100 = self.frames.over100; frame.overBudget = self.frames.overBudget
	frame.budgetMs = self.options.frameBudgetMs
	frame.fps = if self.frames.sum > 0 then self.frames.count / (self.frames.sum / 1000) else nil
	local first, last = self.rows[1], self.rows[#self.rows]
	self.result = {
		side = if self.client then "client" else "server", duration = duration,
		cadence = frame, cadenceSource = if self.client then "RenderStepped interval" else "Heartbeat interval",
		metrics = metrics, samples = self.rows, frameSamplesMs = self.frames.values,
		memoryDeltaMb = if first and last and first.memoryMb and last.memoryMb then last.memoryMb - first.memoryMb else nil,
		memorySlopeMbPerMinute = (Statistics.Slope(self.rows, "memoryMb") or 0) * 60,
		churn = self.churn, unavailable = self.unavailable, samplesDropped = self.samplesDropped,
		collectorMs = self.collectorMs, focusLost = self.lostFocus, focusAtStart = self.focusAtStart, uiVisible = self.uiVisible == true,
		scopes = if self.scopeSession then Scope.Stop(self.scopeSession) else nil,
	}
	return self.result
end

return Runtime
