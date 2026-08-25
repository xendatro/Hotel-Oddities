local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local MathService = require(ReplicatedStorage.Services.MathService)

local Controls = MapConfig.Controls

local MapControlService = {}

local Viewport: GuiObject? = nil
local Content: Frame? = nil
local ContentScale: UIScale? = nil
local Connections: { RBXScriptConnection } = {}

local Zoom, TargetZoom = 1, 1
local Offset, TargetOffset = Vector2.zero, Vector2.zero
local Touches: { [InputObject]: Vector2 } = {}
local DragLast: Vector2? = nil
local PinchDistance = 0

local function touchList(): { InputObject }
	local list = {}
	for input in Touches do
		table.insert(list, input)
	end
	return list
end

local function clampOffset(offset: Vector2, zoom: number): Vector2
	local viewport = Viewport
	if not viewport then return offset end

	local size = viewport.AbsoluteSize
	local limitX = math.max((zoom - 1) * size.X / 2, 0)
	local limitY = math.max((zoom - 1) * size.Y / 2, 0)
	return Vector2.new(math.clamp(offset.X, -limitX, limitX), math.clamp(offset.Y, -limitY, limitY))
end

local function zoomAbout(newZoom: number, focus: Vector2)
	local viewport = Viewport
	if not viewport then return end

	newZoom = math.clamp(newZoom, Controls.MinZoom, Controls.MaxZoom)
	if newZoom == TargetZoom then return end

	local centre = viewport.AbsolutePosition + viewport.AbsoluteSize / 2
	local pointer = focus - centre
	local ratio = newZoom / TargetZoom

	TargetOffset = clampOffset((TargetOffset - pointer) * ratio + pointer, newZoom)
	TargetZoom = newZoom
end

local function isOverViewport(position: Vector2): boolean
	local viewport = Viewport
	if not viewport then return false end

	local topLeft = viewport.AbsolutePosition
	local size = viewport.AbsoluteSize
	return position.X >= topLeft.X
		and position.X <= topLeft.X + size.X
		and position.Y >= topLeft.Y
		and position.Y <= topLeft.Y + size.Y
end

local function beginInput(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		DragLast = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		Touches[input] = Vector2.new(input.Position.X, input.Position.Y)
		local list = touchList()
		if #list == 2 then
			PinchDistance = (Touches[list[1]] - Touches[list[2]]).Magnitude
		end
	end
end

local function endInput(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then DragLast = nil end
	if Touches[input] then
		Touches[input] = nil
		PinchDistance = 0
	end
end

local function changedInput(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local position = UserInputService:GetMouseLocation()
		if not isOverViewport(position) then return end
		zoomAbout(TargetZoom * (1 + input.Position.Z * Controls.WheelStep), position)
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement and DragLast then
		local current = Vector2.new(input.Position.X, input.Position.Y)
		TargetOffset = clampOffset(TargetOffset + (current - DragLast), TargetZoom)
		DragLast = current
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch or not Touches[input] then return end

	local previous = Touches[input]
	local current = Vector2.new(input.Position.X, input.Position.Y)
	Touches[input] = current

	local list = touchList()
	if #list == 1 then
		TargetOffset = clampOffset(TargetOffset + (current - previous), TargetZoom)
		return
	end

	if #list ~= 2 then return end

	local first, second = Touches[list[1]], Touches[list[2]]
	local distance = (first - second).Magnitude
	if PinchDistance <= 0 then
		PinchDistance = distance
		return
	end

	local ratio = 1 + (distance / PinchDistance - 1) * Controls.PinchSensitivity
	PinchDistance = distance
	zoomAbout(TargetZoom * ratio, (first + second) / 2)
end

function MapControlService:Attach(viewport: GuiObject, content: Frame)
	self:Detach()

	Viewport = viewport
	Content = content

	local scale = Instance.new("UIScale")
	scale.Parent = content
	ContentScale = scale

	Zoom, TargetZoom = 1, 1
	Offset, TargetOffset = Vector2.zero, Vector2.zero
	DragLast = nil

	Connections = {
		viewport.InputBegan:Connect(beginInput),
		UserInputService.InputChanged:Connect(changedInput),
		UserInputService.InputEnded:Connect(endInput),
		RunService.RenderStepped:Connect(function(deltaTime)
			Zoom += (TargetZoom - Zoom) * MathService.ExpAlpha(Controls.ZoomLerp, deltaTime)
			Offset = Offset:Lerp(TargetOffset, MathService.ExpAlpha(Controls.PanLerp, deltaTime))

			scale.Scale = Zoom
			content.Position = UDim2.new(0.5, Offset.X, 0.5, Offset.Y)
		end),
	}
end

function MapControlService:Detach()
	for _, connection in Connections do
		connection:Disconnect()
	end
	table.clear(Connections)
	table.clear(Touches)

	DragLast = nil
	PinchDistance = 0
	Viewport = nil
	Content = nil
	ContentScale = nil
end

function MapControlService:Reset(snap: boolean?)
	TargetZoom = 1
	TargetOffset = Vector2.zero
	DragLast = nil
	PinchDistance = 0
	table.clear(Touches)

	if not snap then return end

	Zoom = 1
	Offset = Vector2.zero
	if Content then
		Content.Position = UDim2.fromScale(0.5, 0.5)
	end
	if ContentScale then
		ContentScale.Scale = 1
	end
end

function MapControlService:GetZoom(): number
	return Zoom
end

return MapControlService
