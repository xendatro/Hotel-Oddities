-- Drives the real client services for controller and touch checks from an MCP
-- snippet (call through Bridge). Simulated pad presses from the MCP keyboard
-- tool arrive as Keyboard input and flip PreferredInput away from Gamepad, so
-- these open things and press them without any input. A fresh play session
-- starts with PreferredInput = Gamepad in Studio.
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GamepadProbe = {}

local function services()
	local folder = ReplicatedStorage.Services
	return {
		Interface = require(folder.InterfaceService),
		Computer = require(folder.ComputerService),
		Minigame = require(folder.MinigameService),
		Gamepad = require(folder.GamepadUIService),
		Surface = require(folder.SurfaceCursorService),
		Interaction = require(folder.InteractionService),
		Drawer = require(folder.DrawerService),
	}
end

function GamepadProbe.State()
	local selected = GuiService.SelectedObject
	local s = services()
	return {
		preferred = tostring(UserInputService.PreferredInput),
		selected = if selected then selected:GetFullName() else "nil",
		focused = s.Gamepad:IsFocused(),
		cursor = s.Gamepad:IsCursorShown(),
		page = s.Interface:GetActive(),
		minigame = s.Minigame:IsOpen(),
	}
end

function GamepadProbe.Open(pageId: string)
	services().Interface:Open(pageId)
	task.wait(0.6)
	return GamepadProbe.State()
end

function GamepadProbe.Close()
	services().Interface:Close()
	task.wait(0.6)
	return GamepadProbe.State()
end

-- Opens an unhacked terminal running `gameId`, teleporting the character to it.
function GamepadProbe.Computer(gameId: string)
	local s = services()
	for _, model in CollectionService:GetTagged("HackComputer") do
		if not model:IsA("Model") or not model:IsDescendantOf(workspace) then continue end
		if s.Minigame:GameFor(model) ~= gameId or s.Computer:IsHacked(model) then continue end
		local character = Players.LocalPlayer.Character
		if character then
			character:PivotTo(model:GetPivot() * CFrame.new(0, 0, -6))
		end
		task.wait(0.5)
		local ok = s.Computer:Activate(model)
		task.wait(1.5)
		local state = GamepadProbe.State()
		state.activated = ok
		state.model = model:GetFullName()
		return state
	end
	return { error = `no unhacked {gameId} terminal` }
end

local function minigameGui(): SurfaceGui?
	return Players.LocalPlayer.PlayerGui:FindFirstChild("MinigameGui") :: SurfaceGui?
end

local function shown(object: GuiObject): boolean
	local current: Instance? = object
	while current and not current:IsA("LayerCollector") do
		if current:IsA("GuiObject") and not current.Visible then return false end
		current = current.Parent
	end
	return true
end

local function viewportPointOf(gui: SurfaceGui, element: GuiObject): Vector2?
	local part = gui.Adornee :: BasePart
	local camera = workspace.CurrentCamera
	if not part or not camera then return nil end
	local surface = services().Surface
	local offset = surface:GetElementFrame(part, gui.Face, element, gui.AbsoluteSize)
	local normal = surface:GetFaceBasis(gui.Face).Normal
	local depth = math.abs(part.Size:Dot(normal))
	local world = part.CFrame:PointToWorldSpace(offset + normal * depth / 2)
	local point = camera:WorldToViewportPoint(world)
	return Vector2.new(point.X, point.Y)
end

-- Presses the `index`th shown element named `name` in the open minigame
-- through MinigameService:PressAt, the controller cursor's own path.
function GamepadProbe.Press(name: string, alternate: boolean?, index: number?)
	local gui = minigameGui()
	if not gui then return { error = "no minigame" } end
	local found = 0
	for _, element in gui:GetDescendants() do
		if element.Name ~= name or not element:IsA("GuiObject") or not shown(element) then continue end
		found += 1
		if found < (index or 1) then continue end
		local point = viewportPointOf(gui, element)
		if not point then return { error = "no point" } end
		services().Minigame:PressAt(point, alternate == true)
		task.wait(0.3)
		local state = GamepadProbe.State()
		state.point = tostring(point)
		return state
	end
	return { error = `no shown {name}` }
end

function GamepadProbe.Texts()
	local gui = minigameGui()
	if not gui then return {} end
	local texts = {}
	for _, label in gui:GetDescendants() do
		if (label:IsA("TextLabel") or label:IsA("TextButton")) and label.Text ~= "" and shown(label) then
			table.insert(texts, `{label.Name}={label.Text}`)
		end
	end
	return texts
end

-- Frames the nearest drawer from `distance` studs in front of its handle with
-- a scriptable camera, then taps `offset` pixels right of its centre through
-- Interaction's real touch tap path. `rayHit` says whether the direct ray
-- under the finger already found a target.
function GamepadProbe.TapNearDrawer(offset: number, distance: number?)
	local s = services()
	local character = Players.LocalPlayer.Character
	local camera = workspace.CurrentCamera
	if not character or not camera then return { error = "no character" } end

	local origin = character:GetPivot().Position
	local best: Model?, bestDistance = nil, math.huge
	for _, drawer in CollectionService:GetTagged("Drawer") do
		if not drawer:IsA("Model") or not drawer:IsDescendantOf(workspace) then continue end
		local away = (drawer:GetPivot().Position - origin).Magnitude
		if away < bestDistance then
			best, bestDistance = drawer, away
		end
	end
	if not best then return { error = "no drawer" } end

	local handle: BasePart? = nil
	for _, part in best:GetDescendants() do
		if part:IsA("BasePart") and part.Name:lower():find("handle") then
			handle = part
			break
		end
	end
	local centre = best:GetBoundingBox().Position
	local outward = if handle then (handle.Position - centre) * Vector3.new(1, 0, 1) else Vector3.new(0, 0, -1)
	outward = if outward.Magnitude > 0.01 then outward.Unit else Vector3.new(0, 0, -1)

	character:PivotTo(CFrame.new(centre + outward * 4))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(centre + outward * (distance or 5) + Vector3.new(0, 1.5, 0), centre)
	task.wait(0.5)

	local wasOpen = s.Drawer:IsOpen(best)
	local screen = camera:WorldToScreenPoint(centre)
	local point = Vector2.new(screen.X + offset, screen.Y)
	local rayHit = s.Interaction:_targetAtScreen(point)
	s.Interaction:_tapWorld(point)
	task.wait(0.3)
	local nowOpen = s.Drawer:IsOpen(best)
	camera.CameraType = Enum.CameraType.Custom
	return {
		rayHit = if rayHit then rayHit.Model:GetFullName() else "none",
		drawer = best:GetFullName(),
		wasOpen = wasOpen,
		nowOpen = nowOpen,
	}
end

return GamepadProbe
