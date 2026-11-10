local T = {}
local L = game:GetService("Lighting")
local S = game:GetService("CollectionService")
if not _G.ThumbnailRunSequence then _G.ThumbnailRunSequence=game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync("rbxassetid://2510198475") end
T.original = {lighting={}, guis={}, camera=workspace.CurrentCamera.CFrame, fov=workspace.CurrentCamera.FieldOfView}
for _,p in {"Brightness","Ambient","OutdoorAmbient","ExposureCompensation","FogEnd","FogStart","ClockTime"} do T.original.lighting[p]=L[p] end
for _,g in game.StarterGui:GetChildren() do if g:IsA("LayerCollector") then T.original.guis[g]=g.Enabled g.Enabled=false end end
L.Brightness=2
L.Ambient=Color3.fromRGB(45,42,50)
L.OutdoorAmbient=Color3.fromRGB(70,78,100)
L.ExposureCompensation=-0.15
L.FogEnd=800
L.FogStart=350
T.folder=Instance.new("Folder")
T.folder.Name="ThumbnailStage"
T.folder.Parent=workspace
function T.clear()
 T.folder:ClearAllChildren()
end
function T.actor(name,pos,target,pose,scale)
 local source=workspace.Lobby:FindFirstChild(name) or game.ReplicatedStorage.Enemies:FindFirstChild(name)
 assert(source,name)
 local m=source:Clone()
 local hairs=m:FindFirstChild("Hairs") if hairs then hairs:Destroy() end
 for _,v in m:GetDescendants() do
  if v:IsA("AnimationConstraint") or v:IsA("RigidConstraint") then
   local a,b=v.Attachment0,v.Attachment1
   if a and b then
    local j=Instance.new(if v:IsA("AnimationConstraint") then "Motor6D" else "Weld")
    j.Name=v.Name j.Part0=a.Parent j.Part1=b.Parent j.C0=a.CFrame j.C1=b.CFrame j.Parent=a.Parent
   end
   v:Destroy()
  end
 end
 for _,v in m:GetDescendants() do
  for _,tag in S:GetTags(v) do S:RemoveTag(v,tag) end
  if v:IsA("BaseScript") or v:IsA("ProximityPrompt") or v:IsA("BillboardGui") then v:Destroy()
  elseif v:IsA("BasePart") then v.Anchored=true v.CanCollide=false v.CanQuery=false v.CanTouch=false end
 end
 for _,tag in S:GetTags(m) do S:RemoveTag(m,tag) end
 local h=m:FindFirstChildOfClass("Humanoid")
 if h then h.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
 if scale then m:ScaleTo(scale) end
 local root=m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("RootPart") or m.PrimaryPart
 local cf=CFrame.lookAt(Vector3.new(unpack(pos)),Vector3.new(unpack(target)))
 m:PivotTo(cf*root.CFrame:Inverse()*m:GetPivot())
 local transforms={}
 local animPoses={}
 if pose=="run" then
  local frames=_G.ThumbnailRunSequence:GetKeyframes()
  table.sort(frames,function(a,b) return a.Time<b.Time end)
  local frame=frames[4]
  for _,p in frame:GetDescendants() do if p:IsA("Pose") then animPoses[p.Name]=p.CFrame end end
 elseif pose=="reach" then transforms={LeftShoulder={75,0,-8},RightShoulder={65,0,8},LeftElbow={20,0,0},RightElbow={30,0,0},Neck={-8,0,0}}
 elseif pose=="fear" then transforms={LeftShoulder={20,0,-12},RightShoulder={35,0,12},LeftElbow={65,0,0},RightElbow={75,0,0},Neck={-8,-20,0}}
 elseif pose=="creep" then transforms={Waist={-12,0,0},LeftShoulder={30,0,-10},RightShoulder={30,0,10},LeftElbow={25,0,0},RightElbow={25,0,0},Neck={10,0,0}} end
 local joints={}
 for _,j in m:GetDescendants() do
  if j:IsA("Motor6D") or j:IsA("Weld") then
   if j:IsA("Motor6D") then j.Transform=CFrame.identity end
   local a=transforms[j.Name]
   if a then j.C0=j.C0*CFrame.Angles(math.rad(a[1]),math.rad(a[2]),math.rad(a[3])) end
   if j.Part1 and animPoses[j.Part1.Name] then j.C0=j.C0*animPoses[j.Part1.Name] end
   table.insert(joints,j)
  end
 end
 local known={[root]=true}
 for i=1,15 do
  for _,j in joints do
   if j.Part0 and j.Part1 then
    if known[j.Part0] and not known[j.Part1] then j.Part1.CFrame=j.Part0.CFrame*j.C0*j.C1:Inverse() known[j.Part1]=true
    elseif known[j.Part1] and not known[j.Part0] then j.Part0.CFrame=j.Part1.CFrame*j.C1*j.C0:Inverse() known[j.Part0]=true end
   end
  end
 end
 m.Parent=T.folder
 return m
end
function T.light(pos,color,brightness,range)
 local p=Instance.new("Part") p.Name="PhotographicLight" p.Size=Vector3.one p.Transparency=1 p.Anchored=true p.CanCollide=false p.CanQuery=false p.Position=Vector3.new(unpack(pos))
 local l=Instance.new("PointLight") l.Color=Color3.fromRGB(unpack(color)) l.Brightness=brightness or 3 l.Range=range or 35 l.Shadows=true l.Parent=p p.Parent=T.folder
end
function T.shot(spec)
 T.clear()
 for _,a in spec.actors do T.actor(unpack(a)) end
 for _,l in spec.lights or {} do T.light(unpack(l)) end
 workspace.CurrentCamera.FieldOfView=spec.fov or 60
 workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(unpack(spec.camera)),Vector3.new(unpack(spec.look)))
 return {name=spec.name,actors=#spec.actors,camera=spec.camera,look=spec.look}
end
function T.restore()
 T.folder:Destroy()
 for p,v in T.original.lighting do L[p]=v end
 for g,v in T.original.guis do if g.Parent then g.Enabled=v end end
 workspace.CurrentCamera.CFrame=T.original.camera workspace.CurrentCamera.FieldOfView=T.original.fov
end
_G.HotelThumbnails=T
return "Thumbnail stage ready"
