local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GamepadUIConfig = require(ReplicatedStorage.Configs.GamepadUIConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local CURSOR = GamepadUIConfig.Cursor
local ACTION_NAME = "GamepadCursor"
local RENDER_JOB = "GamepadCursor"

export type Handler = {
	Press: (point: Vector2, alternate: boolean) -> (),
	Release: ((point: Vector2, alternate: boolean) -> ())?,
	Move: ((point: Vector2) -> ())?,
	Stick: Enum.KeyCode?,
}

local GamepadCursor = {}
GamepadCursor.__index = GamepadCursor

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

function GamepadCursor.new()
	local self = setmetatable({}, GamepadCursor)

	local gui = GuiBuilderService.CreateScreenGui(CURSOR.GuiName, CURSOR.DisplayOrder, true)
	gui.Enabled = false

	local image = Instance.new("ImageLabel")
	image.Name = "Cursor"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Size = UDim2.fromOffset(CURSOR.Size, CURSOR.Size)
	image.BackgroundTransparency = 1
	image.Image = CURSOR.Image
	image.ZIndex = 10
	image.Parent = gui

	self.Gui = gui
	self.Image = image
	self.Position = Vector2.zero
	self.Stick = Vector2.zero
	self.Handler = nil :: Handler?
	self.Shown = false
	self.StickKey = CURSOR.Stick

	return self
end

function GamepadCursor:GetPosition(): Vector2
	return self.Position
end

function GamepadCursor:SetHandler(handler: Handler?)
	self.Handler = handler
	if handler and not self.Shown then
		self:_show()
	elseif not handler and self.Shown then
		self:_hide()
	elseif handler and (handler.Stick or CURSOR.Stick) ~= self.StickKey then
		self:_bind()
	end
end

function GamepadCursor:_place()
	self.Image.Position = UDim2.fromOffset(self.Position.X, self.Position.Y)
end

function GamepadCursor:_onAction(inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local handler = self.Handler
	if not handler then return Enum.ContextActionResult.Pass end

	if input.KeyCode == self.StickKey then
		if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			self.Stick = Vector2.zero
		else
			self.Stick = Vector2.new(input.Position.X, -input.Position.Y)
		end
		return Enum.ContextActionResult.Sink
	end

	local alternate = table.find(CURSOR.AlternateKeys, input.KeyCode) ~= nil
	if inputState == Enum.UserInputState.Begin then
		handler.Press(self.Position, alternate)
	elseif inputState == Enum.UserInputState.End and handler.Release then
		handler.Release(self.Position, alternate)
	end
	return Enum.ContextActionResult.Sink
end

function GamepadCursor:_step(deltaTime: number)
	local stick = self.Stick
	local magnitude = math.min(stick.Magnitude, 1)
	if magnitude <= CURSOR.Deadzone then return end

	local strength = ((magnitude - CURSOR.Deadzone) / (1 - CURSOR.Deadzone)) ^ CURSOR.Curve
	local viewport = viewportSize()
	local moved = self.Position + stick.Unit * strength * viewport.Y * CURSOR.Speed * deltaTime
	self.Position = Vector2.new(math.clamp(moved.X, 0, viewport.X), math.clamp(moved.Y, 0, viewport.Y))
	self:_place()

	local handler = self.Handler
	if handler and handler.Move then
		handler.Move(self.Position)
	end
end

function GamepadCursor:_show()
	self.Shown = true
	self.Position = viewportSize() / 2
	self.Stick = Vector2.zero
	self:_place()
	self.Gui.Enabled = true

	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Input.Value + 1, function(deltaTime: number)
		self:_step(deltaTime)
	end)
	self:_bind()
end

function GamepadCursor:_bind()
	local handler = self.Handler
	self.StickKey = (handler and handler.Stick) or CURSOR.Stick
	self.Stick = Vector2.zero
	ContextActionService:UnbindAction(ACTION_NAME)

	local keys = { self.StickKey }
	for _, keyCode in CURSOR.PressKeys do
		table.insert(keys, keyCode)
	end
	for _, keyCode in CURSOR.AlternateKeys do
		table.insert(keys, keyCode)
	end
	ContextActionService:BindActionAtPriority(
		ACTION_NAME,
		function(_action: string, inputState: Enum.UserInputState, input: InputObject)
			return self:_onAction(inputState, input)
		end,
		false,
		CURSOR.Priority,
		table.unpack(keys)
	)
end

function GamepadCursor:_hide()
	self.Shown = false
	self.Stick = Vector2.zero
	self.Gui.Enabled = false
	RunService:UnbindFromRenderStep(RENDER_JOB)
	ContextActionService:UnbindAction(ACTION_NAME)
end

function GamepadCursor:Destroy()
	if self.Shown then
		self:_hide()
	end
	self.Handler = nil
	self.Gui:Destroy()
end

return GamepadCursor
