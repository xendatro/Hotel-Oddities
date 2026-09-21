local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local maze = workspace.Maze15
assert(not maze:FindFirstChild("StartElevator") and not maze:FindFirstChild("ExitElevator"), "Elevators already exist")
local source = workspace.Lobby.Elevator
local sourceFront = CFrame.lookAt(Vector3.new(-791.90918, 1.24593246, -253.0376892), Vector3.new(-792.90918, 1.24593246, -253.0376892))
local backup = Instance.new("Folder")
backup.Name = "MazeElevatorOriginalWalls"
backup.Parent = ServerStorage
local function stripTags(instance)
	for _, tag in CollectionService:GetTags(instance) do CollectionService:RemoveTag(instance, tag) end
	for _, child in instance:GetDescendants() do
		for _, tag in CollectionService:GetTags(child) do CollectionService:RemoveTag(child, tag) end
	end
end
local function cutOpening(front)
	local center = front.Position + Vector3.new(0, 4.3, 0)
	for _, part in maze.Walls:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		local p = part.CFrame:PointToObjectSpace(center)
		local half = part.Size / 2
		if math.abs(p.Z) > half.Z + 0.15 or math.abs(p.X) > half.X + 4.1 or math.abs(p.Y) > half.Y + 4.3 then continue end
		local x0, x1 = math.max(-half.X, p.X - 4.1), math.min(half.X, p.X + 4.1)
		local y0, y1 = math.max(-half.Y, p.Y - 4.3), math.min(half.Y, p.Y + 4.3)
		if x1 <= x0 or y1 <= y0 then continue end
		local saved = part:Clone()
		stripTags(saved)
		saved:SetAttribute("OriginalParent", part.Parent:GetFullName())
		saved.Parent = backup
		local function slab(a,b,c,d)
			if b-a < 0.01 or d-c < 0.01 then return end
			local piece = part:Clone()
			piece.Size = Vector3.new(b-a,d-c,part.Size.Z)
			piece.CFrame = part.CFrame * CFrame.new((a+b)/2,(c+d)/2,0)
			piece.Parent = part.Parent
		end
		slab(-half.X,x0,-half.Y,half.Y)
		slab(x1,half.X,-half.Y,half.Y)
		slab(x0,x1,-half.Y,y0)
		slab(x0,x1,y1,half.Y)
		part:Destroy()
	end
end
local function part(parent,name,size,frame,color,material)
	local p = Instance.new("Part")
	p.Name=name p.Size=size p.CFrame=frame p.Color=color p.Material=material or Enum.Material.Metal
	p.Anchored=true p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth p.Parent=parent
	return p
end
local function label(parent,name,text,position,size,color,textSize)
	local l=Instance.new("TextLabel")
	l.Name=name l.Text=text l.Position=position l.Size=size l.BackgroundTransparency=1
	l.TextColor3=color l.Font=Enum.Font.GothamMedium l.TextSize=textSize l.Parent=parent
	return l
end
local function sign(parent,front,text)
	local p=part(parent,"Identification",Vector3.new(6.8,0.85,0.16),front*CFrame.new(0,9.25,-0.65),Color3.fromRGB(45,37,29))
	local gui=Instance.new("SurfaceGui") gui.Face=Enum.NormalId.Front gui.CanvasSize=Vector2.new(680,85) gui.LightInfluence=0 gui.Brightness=1.5 gui.MaxDistance=150 gui.Parent=p
	label(gui,"Title",text,UDim2.fromScale(0,0),UDim2.fromScale(1,1),Color3.fromRGB(235,212,158),64)
end
local function build(name,kind,position,inward)
	local front=CFrame.lookAt(position,position+inward)
	cutOpening(front)
	local model=source:Clone() stripTags(model) model.Name=name
	for _, p in model:GetDescendants() do
		if p:IsA("LuaSourceContainer") then p:Destroy()
		elseif p:IsA("BasePart") then
			if p.Position.Y>11 then p:Destroy() else p.Anchored=true end
		end
	end
	model:PivotTo(front*sourceFront:Inverse()*source:GetPivot())
	model:SetAttribute("Type",kind) model:SetAttribute("DoorOffset",3.35)
	model.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
	model.Parent=maze CollectionService:AddTag(model,"Elevator")
	local hitbox=model:FindFirstChild("Hitbox")
	if hitbox then hitbox.PivotOffset=hitbox.CFrame:ToObjectSpace(model:GetPivot()) model.PrimaryPart=hitbox end
	local marker=part(model,"Approach",Vector3.new(1,1,1),front*CFrame.new(0,3,-4),Color3.new())
	marker.Transparency=1 marker.CanCollide=false marker.CanTouch=false marker.CanQuery=false
	local threshold=part(model,"Threshold",Vector3.new(8.2,0.15,2),front*CFrame.new(0,-0.075,0),Color3.fromRGB(105,88,65))
	for _, x in {-4.05,4.05} do
		part(model,"Jamb",Vector3.new(0.3,8.6,0.45),front*CFrame.new(x,4.3,-0.2),Color3.fromRGB(86,66,54),Enum.Material.Wood)
	end
	part(model,"Lintel",Vector3.new(8.4,0.32,0.45),front*CFrame.new(0,8.6,-0.2),Color3.fromRGB(86,66,54),Enum.Material.Wood)
	sign(model,front,kind=="Start" and "ARRIVAL" or "EXIT")
	return model,front
end
local start,startFrame=build("StartElevator","Start",Vector3.new(589.58496094,-22.63200378,-616.20996094),Vector3.new(0,0,1))
local exit,exitFrame=build("ExitElevator","Exit",Vector3.new(-586.73339844,-22.63200378,530.81933594),Vector3.new(1,0,0))
local spawn=maze.Spawn
spawn:SetAttribute("PreviousCFrame",spawn.CFrame)
spawn.CFrame=startFrame*CFrame.new(0,-0.5,6)
spawn.Size=Vector3.new(10,1,10) spawn.Transparency=1 spawn.CanCollide=false spawn.Parent=start
local zone=maze.SpawnSafeZone
zone:SetAttribute("PreviousCFrame",zone.CFrame)
zone.CFrame=startFrame*CFrame.new(0,5.593,6) zone.Parent=start
local panel=part(exit,"StatusPanel",Vector3.new(2.5,5.2,0.22),exitFrame*CFrame.new(5.48,5.15,-0.68),Color3.fromRGB(27,30,29))
local gui=Instance.new("SurfaceGui") gui.Name="ProgressDisplay" gui.Face=Enum.NormalId.Front gui.CanvasSize=Vector2.new(330,690) gui.LightInfluence=0 gui.Brightness=1.5 gui.MaxDistance=150 gui.PixelsPerStud=100 gui.Parent=panel
label(gui,"Heading","EXIT ACCESS",UDim2.fromScale(0.04,0.02),UDim2.fromScale(0.92,0.085),Color3.fromRGB(238,228,201),32)
label(gui,"Instruction","COMPLETE ALL 5",UDim2.fromScale(0.04,0.105),UDim2.fromScale(0.92,0.05),Color3.fromRGB(176,180,172),22)
local colors={{"Blue",60,155,255},{"Yellow",255,220,55},{"Red",255,70,75},{"Green",75,255,125},{"Purple",190,95,255}}
for index,entry in colors do
	local row=Instance.new("Frame") row.Name=entry[1] row.Position=UDim2.fromScale(0.055,0.195+(index-1)*0.13) row.Size=UDim2.fromScale(0.89,0.112) row.BackgroundColor3=Color3.fromRGB(39,43,41) row.BorderSizePixel=0 row.Parent=gui
	local swatch=Instance.new("Frame") swatch.Name="Color" swatch.Position=UDim2.fromScale(0.04,0.18) swatch.Size=UDim2.fromScale(0.04,0.64) swatch.BackgroundColor3=Color3.fromRGB(entry[2],entry[3],entry[4]) swatch.BorderSizePixel=0 swatch.Parent=row
	local title=label(row,"ColorName",string.upper(entry[1]),UDim2.fromScale(0.13,0.05),UDim2.fromScale(0.68,0.43),swatch.BackgroundColor3,25) title.TextXAlignment=Enum.TextXAlignment.Left
	local state=label(row,"Status","MISSING",UDim2.fromScale(0.13,0.52),UDim2.fromScale(0.66,0.33),Color3.fromRGB(220,134,124),19) state.TextXAlignment=Enum.TextXAlignment.Left
	local symbol=Instance.new("Frame") symbol.Name="Indicator" symbol.Position=UDim2.fromScale(0.87,0.5) symbol.Size=UDim2.fromOffset(34,34) symbol.AnchorPoint=Vector2.new(0.5,0.5) symbol.BackgroundTransparency=1 symbol.Parent=row
	for i,rotation in {-45,45} do local bar=Instance.new("Frame") bar.Name="Bar"..i bar.AnchorPoint=Vector2.new(0.5,0.5) bar.Position=UDim2.fromScale(0.5,0.5) bar.Size=UDim2.fromOffset(31,5) bar.Rotation=rotation bar.BorderSizePixel=0 bar.BackgroundColor3=Color3.fromRGB(220,134,124) bar.Parent=symbol end
end
label(gui,"Summary","LOCKED   0 / 5",UDim2.fromScale(0.04,0.87),UDim2.fromScale(0.92,0.09),Color3.fromRGB(230,150,125),25)
local barrier=part(exit,"AccessBarrier",Vector3.new(8.1,8.5,0.6),exitFrame*CFrame.new(0,4.25,0.65),Color3.new())
barrier.Transparency=1 barrier.CanTouch=false
return {start=start:GetFullName(),exit=exit:GetFullName(),spawn=tostring(spawn.Position),safeZone=tostring(zone.Size),backedUpWalls=#backup:GetChildren()}
