local UserInputService = game:GetService("UserInputService")
local Dropdown = {}
Dropdown.__index = Dropdown

local function create(class,parent,props)
	local item = Instance.new(class)
	for key,value in props do item[key] = value end
	item.Parent = parent
	return item
end

function Dropdown.new(gui,frame)
	return setmetatable({gui=gui,frame=frame,generation=0},Dropdown)
end

function Dropdown:Close()
	self.generation += 1
	self.anchor = nil
	if self.dismiss then self.dismiss:Destroy(); self.dismiss = nil end
	if self.menu then self.menu:Destroy(); self.menu = nil end
	if self.keyboard then self.keyboard:Disconnect(); self.keyboard = nil end
end

function Dropdown:Open(anchor,items,selected,onSelect)
	self:Close()
	self.anchor = anchor
	local frame = self.frame
	local offset = anchor.AbsolutePosition-frame.AbsolutePosition
	local width = math.min(math.max(anchor.AbsoluteSize.X,300),frame.AbsoluteSize.X-16)
	local x = math.clamp(offset.X,8,math.max(8,frame.AbsoluteSize.X-width-8))
	local y = offset.Y+anchor.AbsoluteSize.Y+4
	local rowHeight = if anchor.Name=="History" then 62 else 44
	local height = math.min(math.max(1,#items)*rowHeight+8,280,frame.AbsoluteSize.Y-y-8)
	self.dismiss = create("TextButton",frame,{Name="DismissDropdown",Text="",BackgroundTransparency=1,
		Position=UDim2.fromOffset(-frame.AbsolutePosition.X,-frame.AbsolutePosition.Y),
		Size=UDim2.fromOffset(self.gui.AbsoluteSize.X,self.gui.AbsoluteSize.Y),ZIndex=5,AutoButtonColor=false})
	self.dismiss.Activated:Connect(function() self:Close() end)
	self.menu = create("ScrollingFrame",frame,{Name="Dropdown",Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,height),
		BackgroundColor3=Color3.fromRGB(29,37,49),BorderSizePixel=0,ZIndex=20,ScrollBarThickness=5,
		ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.fromOffset(0,math.max(1,#items)*rowHeight+8)})
	create("UICorner",self.menu,{CornerRadius=UDim.new(0,5)})
	create("UIStroke",self.menu,{Color=Color3.fromRGB(76,94,119),Thickness=1})
	if #items==0 then items={{label=if anchor.Name=="History" then "No reports yet" else "Options unavailable",disabled=true}} end
	for index,item in items do
		local chosen = item.value~=nil and item.value==selected
		local option = create("TextButton",self.menu,{Name="Option" .. index,
			Text=(if chosen then "✓ " else "  ") .. item.label,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
			TextSize=13,Font=if chosen then Enum.Font.GothamBold else Enum.Font.Gotham,
			TextColor3=if item.disabled then Color3.fromRGB(155,167,182) else Color3.fromRGB(232,240,250),
			BackgroundColor3=if chosen then Color3.fromRGB(39,91,94) else Color3.fromRGB(38,48,64),
			AutoButtonColor=not item.disabled,Selectable=not item.disabled,BorderSizePixel=0,ZIndex=21,
			Position=UDim2.fromOffset(4,4+(index-1)*rowHeight),Size=UDim2.new(1,-14,0,rowHeight-4)})
		option:SetAttribute("Selected",chosen)
		create("UIPadding",option,{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)})
		option.Activated:Connect(function()
			if item.disabled then return end
			self:Close()
			onSelect(item.value)
		end)
	end
	self.keyboard = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode==Enum.KeyCode.Escape then self:Close() end
	end)
end

function Dropdown:Toggle(anchor,items,selected,onSelect)
	if self.anchor==anchor then self:Close(); return end
	self:Open(anchor,items,selected,onSelect)
end

return Dropdown
