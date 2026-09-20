local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Dropdown = require(script.Parent.Dropdown)
local Panel = {}
Panel.__index = Panel
local function create(class,parent,props)
	local instance = Instance.new(class)
	for key,value in props do instance[key] = value end
	instance.Parent = parent
	return instance
end

function Panel.new(transport)
	local self = setmetatable({ transport = transport, scenarioIndex = 1, focusIndex = 1, scenarios = {}, format = "summary", mode = "score" },Panel)
	local gui = create("ScreenGui",Players.LocalPlayer:WaitForChild("PlayerGui",10),{ Name = "ProfilerUI", ResetOnSpawn = false, DisplayOrder = 10000, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	self.gui = gui
	local frame = create("Frame",gui,{ Name = "Panel", AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.fromScale(0.5,0.5), Size = UDim2.fromScale(0.94,0.88), BackgroundColor3 = Color3.fromRGB(20,24,32), BorderSizePixel = 0 })
	self.dropdown = Dropdown.new(gui,frame)
	create("UISizeConstraint",frame,{ MaxSize = Vector2.new(980,820) })
	create("UICorner",frame,{ CornerRadius = UDim.new(0,10) })
	create("TextLabel",frame,{ Text = "ROBLOX PROFILER", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(232,240,250), BackgroundTransparency = 1, Position = UDim2.fromOffset(14,8), Size = UDim2.new(1,-80,0,28), TextXAlignment = Enum.TextXAlignment.Left })
	local function button(name,text,x,y,w,callback)
		local b = create("TextButton",frame,{ Name = name, Text = text, TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = Color3.new(1,1,1), BackgroundColor3 = Color3.fromRGB(47,58,74), BorderSizePixel = 0, Position = UDim2.new(x,8,y,0), Size = UDim2.new(w,-16,0,32) })
		create("UICorner",b,{ CornerRadius = UDim.new(0,5) })
		b.TextWrapped = true; b.TextScaled = true
		create("UITextSizeConstraint",b,{MinTextSize=9,MaxTextSize=13})
		b.Activated:Connect(function()
			task.spawn(function()
				self:Try(callback)
			end)
		end)
		return b
	end
	local close = button("Close","Close",0.86,0,0.14,function() self:Hide() end)
	close.Position = UDim2.new(0.86,0,0,8); close.Modal = true
	local function control(name,text,index,callback)
		local b = button(name,text,(index-1)/4,0,0.25,callback)
		b.Position = UDim2.new((index-1)/4,8,0,46)
		b.ZIndex = 10
		create("UIPadding",b,{PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,22)})
		for index,rotation in {45,-45} do
			create("Frame",b,{Name="Chevron" .. index,AnchorPoint=Vector2.new(0.5,0.5),
				Position=UDim2.new(1,if index==1 then -12 else -8,0.5,0),Size=UDim2.fromOffset(6,2),
				Rotation=rotation,BackgroundColor3=Color3.fromRGB(220,230,242),BorderSizePixel=0,ZIndex=11})
		end
		return b
	end
	self.scenarioButton = control("Scenario","Choose scenario",1,function()
		local items = {}
		for index,scenario in self.scenarios do table.insert(items,{value=index,label=scenario.name}) end
		self.dropdown:Toggle(self.scenarioButton,items,self.scenarioIndex,function(value) self.scenarioIndex=value; self:RefreshChoices() end)
	end)
	self.focuses = { "all","render","memory","server","network","functions" }
	self.focusButton = control("Focus","Focus: all",2,function()
		local items = {}
		for index,focus in self.focuses do table.insert(items,{value=index,label=focus}) end
		self.dropdown:Toggle(self.focusButton,items,self.focusIndex,function(value) self.focusIndex=value; self:RefreshChoices() end)
	end)
	self.modeButton = control("Mode","Mode: score",3,function()
		self.dropdown:Toggle(self.modeButton,{
			{value="score",label="Score: measure performance"},
			{value="diagnostic",label="Diagnostic: find expensive work"},
		},self.mode,function(value) self.mode=value; self:RefreshChoices() end)
	end)
	self.historyButton = control("History","History",4,function() self:OpenHistory() end)
	local function field(name,placeholder,value,index)
		return create("TextBox",frame,{ Name = name, PlaceholderText = placeholder, Text = value, ClearTextOnFocus = false,
			Position = UDim2.new((index-1)/4,8,0,84),Size = UDim2.new(0.25,-16,0,30), BackgroundColor3 = Color3.fromRGB(32,40,53),
			TextColor3 = Color3.new(1,1,1),PlaceholderColor3 = Color3.fromRGB(165,180,195),TextSize = 13,Font = Enum.Font.Gotham })
	end
	self.duration = field("Duration","Seconds / phase","20",1)
	self.repeats = field("Repeats","Repeat count","1",2)
	self.build = field("Build","Build label","working-tree",3)
	self.device = field("Device","Device label","unlabeled",4)
	self.description = create("TextLabel",frame,{ Name = "Description",Text = "Seconds per phase | repeat count | build | device",TextSize = 12,Font = Enum.Font.Gotham,TextWrapped = true,TextColor3 = Color3.fromRGB(169,187,207),BackgroundTransparency = 1,Position = UDim2.fromOffset(12,118),Size = UDim2.new(1,-24,0,40),TextXAlignment = Enum.TextXAlignment.Left })
	self.status = create("TextLabel",frame,{ Name = "Status",Text = "Ready. /profile opens this panel.",TextSize = 13,Font = Enum.Font.Gotham,TextWrapped = true,TextColor3 = Color3.fromRGB(113,211,199),BackgroundTransparency = 1,Position = UDim2.fromOffset(12,160),Size = UDim2.new(1,-24,0,32),TextXAlignment = Enum.TextXAlignment.Left })
	local scroll = create("ScrollingFrame",frame,{ Name = "ReportScroll",Position = UDim2.fromOffset(10,198),Size = UDim2.new(1,-20,1,-292),CanvasSize = UDim2.new(),AutomaticCanvasSize = Enum.AutomaticSize.Y,ScrollBarThickness = 6,BackgroundColor3 = Color3.fromRGB(12,16,22),BorderSizePixel = 0 })
	self.output = create("TextBox",scroll,{ Name = "Report",Text = "Run a scenario or record normal play. Select the report text to copy it into an LLM.\n\nDuration and repeat count apply to every phase. Diagnostic mode adds profiler overhead. Controlled Hotel scenarios reset ambient enemies and require Studio or a private server.",ClearTextOnFocus = false,MultiLine = true,TextWrapped = true,TextXAlignment = Enum.TextXAlignment.Left,TextYAlignment = Enum.TextYAlignment.Top,TextSize = 13,Font = Enum.Font.Code,TextColor3 = Color3.fromRGB(220,230,242),BackgroundTransparency = 1,Position = UDim2.fromOffset(8,8),Size = UDim2.new(1,-24,0,260),AutomaticSize = Enum.AutomaticSize.Y })
	local function bottom(name,text,index,row,callback)
		local b = button(name,text,(index-1)/4,1,0.25,callback)
		b.Position = UDim2.new((index-1)/4,8,1,if row == 1 then -84 else -44)
		return b
	end
	bottom("Run","Run",1,1,function()
		local scenario = assert(self.scenarios[self.scenarioIndex],"No scenario")
		local result = self.transport:Command({ action = "start",scenario = scenario.id,options = {
			duration = tonumber(self.duration.Text),repeats = tonumber(self.repeats.Text),build = self.build.Text,
			device = self.device.Text,focus = self.focuses[self.focusIndex],mode = self.mode } })
		self.lastId = result.id; self.openAfterRun = true; self:Hide()
	end)
	bottom("Stop","Stop recording",2,1,function() self.transport:Command({ action = "stop" }) end)
	bottom("Cancel","Cancel",3,1,function() self.transport:Command({ action = "cancel" }) end)
	bottom("Select","Select text",4,1,function()
		self.output:CaptureFocus(); self.output.SelectionStart = 1; self.output.CursorPosition = #self.output.Text+1
	end)
	bottom("Format","Summary / details / JSON",1,2,function()
		self.format = if self.format == "summary" then "details" elseif self.format == "details" then "json" elseif self.format == "json" then "baseline" else "summary"; self:LoadReport()
	end)
	bottom("Baseline","Set baseline",2,2,function()
		assert(self.lastId,"No report selected"); self.baseline = self.lastId; self.status.Text = "Baseline: " .. self.baseline
	end)
	bottom("Compare","Compare +15% FPS",3,2,function()
		assert(self.baseline and self.lastId,"Select a baseline and a candidate first")
		self.transport:Command({ action = "compare",baseline = self.baseline,candidate = self.lastId,target = 15 })
		self:LoadReport()
	end)
	bottom("Import","Import pasted JSON",4,2,function()
		local result = self.transport:Command({ action = "import",json = self.output.Text })
		self.lastId = result.id; self.baseline = result.id; self:LoadReport()
	end)
	local function layout()
		self.dropdown:Close()
		local narrow = frame.AbsoluteSize.X < 600 and frame.AbsoluteSize.Y >= 500
		local columns = if narrow then 2 else 4
		for i,name in {"Scenario","Focus","Mode","History"} do
			local b = frame[name]
			b.Position = UDim2.new(((i-1)%columns)/columns,8,0,46+math.floor((i-1)/columns)*38)
			b.Size = UDim2.new(1/columns,-16,0,32)
		end
		for i,name in {"Duration","Repeats","Build","Device"} do
			local box = frame[name]
			box.Position = UDim2.new(((i-1)%columns)/columns,8,0,(if narrow then 122 else 84)+math.floor((i-1)/columns)*38)
			box.Size = UDim2.new(1/columns,-16,0,30)
		end
		self.description.Position = UDim2.fromOffset(12,if narrow then 198 else 118)
		self.status.Position = UDim2.fromOffset(12,if narrow then 240 else 160)
		local top = if narrow then 278 else 198
		local bottomHeight = if narrow then 174 else 94
		scroll.Position = UDim2.fromOffset(10,top); scroll.Size = UDim2.new(1,-20,1,-top-bottomHeight)
		for i,name in {"Run","Stop","Cancel","Select","Format","Baseline","Compare","Import"} do
			local b = frame[name]
			b.Position = UDim2.new(((i-1)%columns)/columns,8,1,-(math.ceil(8/columns)-math.floor((i-1)/columns))*40-4)
			b.Size = UDim2.new(1/columns,-16,0,32)
		end
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	return self
end

function Panel:RefreshChoices()
	local scenario = self.scenarios[self.scenarioIndex]
	self.scenarioButton.Text = if scenario then scenario.name else "No scenarios"
	self.focusButton.Text = "Focus: " .. self.focuses[self.focusIndex]
	self.modeButton.Text = "Mode: " .. self.mode
	self.description.Text = if scenario then scenario.description .. " | " .. table.concat(scenario.phases or {"steady"},", ") else "No scenarios"
end

function Panel:OpenHistory()
	if self.dropdown.anchor==self.historyButton then self.dropdown:Close(); return end
	self.dropdown:Open(self.historyButton,{{label="Loading reports...",disabled=true}},nil,function() end)
	local generation = self.dropdown.generation
	local ok,history = pcall(function() return self.transport:Command({action="history",details=true}) end)
	if self.dropdown.generation~=generation then return end
	if not ok then self.dropdown:Close(); error(history,0) end
	local items = {}
	for index=#history,1,-1 do
		local row = history[index]
		table.insert(items,{value=row.id,label=row.scenario .. " | " .. row.build .. "\n"
			.. row.created .. " | " .. row.status .. " | " .. row.id:sub(1,8)})
	end
	self.dropdown:Open(self.historyButton,items,self.lastId,function(id)
		self.lastId=id; self:LoadReport()
	end)
end

function Panel:Try(callback)
	local ok,value = pcall(callback)
	if not ok then self.status.Text = tostring(value) end
	return ok,value
end

function Panel:Show()
	if not self.gui.Enabled then
		self.mouse = UserInputService.MouseBehavior; self.icon = UserInputService.MouseIconEnabled
		self.gui.Enabled = true
		RunService:BindToRenderStep("ProfilerMouse",Enum.RenderPriority.Last.Value+100,function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled = true
		end)
	end
	if self.choicesInitialized or self.loadingChoices then return end
	self.loadingChoices = true
	local ok,list = self:Try(function() return self.transport:Command({ action = "list" }) end)
	self.loadingChoices = false
	if not ok then return end
	self.status.Text = "Ready. Choose a scenario or open the latest report."
	self.scenarios = list.scenarios; self:RefreshChoices()
	if not self.choicesInitialized then
		self.choicesInitialized = true
		for i,scenario in self.scenarios do if scenario.id == "manual" then self.scenarioIndex = i end end
		self:RefreshChoices()
	end
end

function Panel:Hide()
	self.dropdown:Close()
	self.gui.Enabled = false
	RunService:UnbindFromRenderStep("ProfilerMouse")
	if self.mouse then UserInputService.MouseBehavior = self.mouse; UserInputService.MouseIconEnabled = self.icon end
end

function Panel:LoadReport()
	return self:Try(function()
		assert(self.lastId,"No report selected")
		self.output.Text = self.transport:Export(self.lastId,self.format)
		self.historyButton.Text = "Report: " .. self.lastId:sub(1,8)
		self.status.Text = "Report " .. self.lastId .. " | " .. self.format .. " | select text to copy"
	end)
end

return Panel
