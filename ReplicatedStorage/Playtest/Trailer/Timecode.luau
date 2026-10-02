-- Burns the shot clock into every rendered frame so the trailer pipeline can
-- trim and retime a screen capture exactly, whatever the capture or render
-- rate was. Everything drawn here sits in the viewport's left/right margins,
-- outside the centred 16:9 crop, so it never reaches the final video.
--
-- Layout (viewport pixels, IgnoreGuiInset):
--   corner markers: 8x8 white squares at all four viewport corners
--   strip: CELLS cells down the left margin starting at (X, Y), each W x H with
--          GAP between them. Cell 0 is always white (sync), cell 1 is the
--          running flag, cells 2..21 are the shot time in milliseconds (LSB
--          first), cells 22..27 are the shot id (LSB first) and cell 28 is the
--          even parity of those 26 bits. One capture can hold many shots; the
--          id tells them apart.
-- Trailer/tools/conform.py reads the same layout from Trailer/project.yaml;
-- change both together.
local Players = game:GetService("Players")

local Timecode = {}

local X, Y, W, H, GAP = 6, 60, 24, 20, 4
local BITS = 20
local ID_BITS = 6
local CELLS = BITS + ID_BITS + 3
local MARKER = 8
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local gui: ScreenGui? = nil
local cells: { Frame } = {}

local function square(parent: Instance, position: UDim2, size: UDim2, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = BLACK
	frame.Position = position
	frame.Size = size
	frame.AnchorPoint = anchor or Vector2.zero
	frame.ZIndex = 10
	frame.Parent = parent
	return frame
end

function Timecode.Gui(): ScreenGui
	if gui and gui.Parent then return gui end

	local screen = Instance.new("ScreenGui")
	screen.Name = "TrailerTimecode"
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.DisplayOrder = 100000
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local size = UDim2.fromOffset(MARKER, MARKER)
	square(screen, UDim2.new(0, 0, 0, 0), size).BackgroundColor3 = WHITE
	square(screen, UDim2.new(1, 0, 0, 0), size, Vector2.new(1, 0)).BackgroundColor3 = WHITE
	square(screen, UDim2.new(0, 0, 1, 0), size, Vector2.new(0, 1)).BackgroundColor3 = WHITE
	square(screen, UDim2.new(1, 0, 1, 0), size, Vector2.new(1, 1)).BackgroundColor3 = WHITE

	local backing = square(screen, UDim2.fromOffset(X - 4, Y - 4), UDim2.fromOffset(W + 8, CELLS * (H + GAP) - GAP + 8))
	backing.ZIndex = 9

	table.clear(cells)
	for index = 0, CELLS - 1 do
		cells[index] = square(screen, UDim2.fromOffset(X, Y + index * (H + GAP)), UDim2.fromOffset(W, H))
	end
	cells[0].BackgroundColor3 = WHITE

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	return screen
end

function Timecode.Set(seconds: number?, running: boolean, id: number?)
	Timecode.Gui()
	local value = math.clamp(math.floor((seconds or 0) * 1000 + 0.5), 0, 2 ^ BITS - 1)
	local shot = math.clamp(math.floor(id or 0), 0, 2 ^ ID_BITS - 1)
	local parity = 0
	cells[1].BackgroundColor3 = if running then WHITE else BLACK
	for bit = 0, BITS - 1 do
		local on = bit32.band(bit32.rshift(value, bit), 1) == 1
		if on then parity += 1 end
		cells[2 + bit].BackgroundColor3 = if on then WHITE else BLACK
	end
	for bit = 0, ID_BITS - 1 do
		local on = bit32.band(bit32.rshift(shot, bit), 1) == 1
		if on then parity += 1 end
		cells[2 + BITS + bit].BackgroundColor3 = if on then WHITE else BLACK
	end
	cells[2 + BITS + ID_BITS].BackgroundColor3 = if parity % 2 == 1 then WHITE else BLACK
end

function Timecode.Destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(cells)
end

return Timecode
