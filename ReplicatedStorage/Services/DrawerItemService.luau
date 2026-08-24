local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DrawerItemService = {}

if not RunService:IsClient() then
	return DrawerItemService
end

local CollectionService = game:GetService("CollectionService")
local ItemConfig = require(ReplicatedStorage.Configs.DrawerItemConfig)
local DrawerService = require(ReplicatedStorage.Services.DrawerService)
local TagService = require(ReplicatedStorage.Services.TagService)

local TARGETING = ItemConfig.Targeting
local HIGHLIGHT = ItemConfig.Highlight
local INPUT = ItemConfig.Input
local UI = ItemConfig.UI
local COLORS = UI.Colors

local FOCUS_JOB = "DrawerItemFocus"
local PROMPT_JOB = "DrawerItemPrompt"
local HIGHLIGHT_FADE_SPEED = 16
local PICKUP_COOLDOWN = 0.15

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local folder = communication and communication:WaitForChild(ItemConfig.Remotes.Folder, 30)
local PickupRemote = folder and folder:WaitForChild(ItemConfig.Remotes.Pickup, 30)

local States: { [Model]: true } = {}
local focused: Model? = nil
local highlightAlpha = 0
local lastPickup = 0

local highlight = Instance.new("Highlight")
highlight.Name = "DrawerItemHighlight"
highlight.FillColor = HIGHLIGHT.FillColor
highlight.OutlineColor = HIGHLIGHT.OutlineColor
highlight.DepthMode = HIGHLIGHT.DepthMode
highlight.FillTransparency = 1
highlight.OutlineTransparency = 1
highlight.Enabled = false
highlight.Adornee = nil
highlight.Parent = workspace

local function resetHighlight()
	focused = nil
	highlightAlpha = 0
	highlight.Enabled = false
	highlight.Adornee = nil
	if highlight.Parent ~= workspace then
		highlight.Parent = workspace
	end
end

local function ensureHighlight()
	if highlight.Parent ~= workspace then
		highlight.Parent = workspace
	end
	if highlight.Adornee and not highlight.Adornee:IsDescendantOf(workspace) then
		highlight.Adornee = nil
		focused = nil
		highlightAlpha = 0
	end
end

local function register(model: Model): Model?
	if not model:IsA("Model") then return nil end
	States[model] = true
	local drawer = model.Parent
	if drawer and drawer:IsA("Model") then
		DrawerService:Sync(drawer)
	end
	return model
end

local function unregister(model: Model)
	States[model] = nil
	if focused == model then
		focused = nil
	end
end

local function itemOf(part: BasePart): Model?
	local instance: Instance? = part
	while instance and instance ~= workspace do
		if instance:IsA("Model") and States[instance] then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

local function alive(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then character else nil
end

local function findFocus(): Model?
	local camera = workspace.CurrentCamera
	local character = alive()
	if not camera or not character then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = { character }
	params.FilterDescendantsInstances = ignored

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * TARGETING.Reach

	for _ = 1, TARGETING.MaxPassthrough + 1 do
		local result = workspace:Raycast(origin, direction, params)
		if not result then return nil end

		local item = itemOf(result.Instance)
		if item then return item end

		if result.Instance.CanCollide or result.Instance.Transparency < 1 then return nil end

		table.insert(ignored, result.Instance)
		params.FilterDescendantsInstances = ignored
	end

	return nil
end

local function renderFocus(deltaTime: number)
	ensureHighlight()
	focused = findFocus()

	if focused then
		highlight.Adornee = focused
		highlight.Enabled = true
	end

	local target = if focused then 1 else 0
	highlightAlpha += (target - highlightAlpha) * (1 - math.exp(-HIGHLIGHT_FADE_SPEED * deltaTime))
	if math.abs(target - highlightAlpha) < 1e-3 then highlightAlpha = target end

	if highlightAlpha <= 0 then
		if highlight.Enabled then
			highlight.Enabled = false
			highlight.Adornee = nil
		end
		return
	end

	highlight.FillTransparency = 1 - (1 - HIGHLIGHT.FillTransparency) * highlightAlpha
	highlight.OutlineTransparency = 1 - (1 - HIGHLIGHT.OutlineTransparency) * highlightAlpha
end

local cursor = playerGui:WaitForChild("Cursor", 30) :: ScreenGui?
local template = cursor and cursor:WaitForChild(UI.Container, 30)
local container: CanvasGroup? = nil

if template then
	local clone = template:Clone() :: CanvasGroup
	clone.Name = UI.Prompt
	clone.Visible = false
	clone.GroupTransparency = 1
	clone.Parent = cursor
	container = clone
else
	warn(`DrawerItemService: no {UI.Container} under the Cursor gui; the pickup prompt will not draw`)
end

local promptScale: UIScale? = nil
local promptPill: Frame? = nil
local promptKey: Frame? = nil
local promptKeyScale: UIScale? = nil
local promptKeyLabel: TextLabel? = nil
local promptAction: TextLabel? = nil

if container then
	promptScale = container:FindFirstChild("Scale") :: UIScale
	promptPill = container:FindFirstChild("Pill") :: Frame
	promptKey = promptPill and promptPill:FindFirstChild("Key") :: Frame
	promptKeyScale = promptKey and promptKey:FindFirstChild("Scale") :: UIScale
	promptKeyLabel = promptKey and promptKey:FindFirstChild("Label") :: TextLabel
	promptAction = promptPill and promptPill:FindFirstChild("Action") :: TextLabel

	if not (promptScale and promptPill and promptKey and promptKeyScale and promptKeyLabel and promptAction) then
		warn(`DrawerItemService: the {UI.Container} prompt is not shaped as expected; the pickup prompt will not draw`)
		container:Destroy()
		container = nil
	end
end

local function layout(keyWidth: number)
	if not (container and promptPill and promptKey and promptAction) then return end

	local left = UI.PillPaddingLeft + keyWidth + UI.KeyGap
	local width = left + UI.TextWidth + UI.PillPaddingRight

	container.Size = UDim2.fromOffset(width + UI.Padding * 2, UI.PillHeight + UI.Padding * 2)
	promptPill.Size = UDim2.fromOffset(width, UI.PillHeight)
	promptKey.Size = UDim2.fromOffset(keyWidth, UI.KeySize)
	promptAction.Position = UDim2.new(0, left, 0.5, 0)
	promptAction.Size = UDim2.fromOffset(UI.TextWidth, UI.KeySize)
end

local pressFlash = 0
local touching = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local usingGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
local bound = false

local function onPickupAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and DrawerItemService:Pickup() then
		pressFlash = 1
	end
	return Enum.ContextActionResult.Pass
end

local function setBound(shouldBind: boolean)
	if shouldBind == bound then return end
	bound = shouldBind

	if not shouldBind then
		ContextActionService:UnbindAction(INPUT.TouchAction)
		return
	end

	ContextActionService:BindAction(INPUT.TouchAction, onPickupAction, touching, table.unpack(INPUT.Keys))
	if not touching then return end

	ContextActionService:SetTitle(INPUT.TouchAction, UI.PickupText:upper())
	ContextActionService:SetPosition(INPUT.TouchAction, INPUT.TouchButtonPosition)
	local button = ContextActionService:GetButton(INPUT.TouchAction)
	if button then
		button.Size = INPUT.TouchButtonSize
	end
end

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	if inputType == Enum.UserInputType.Touch then
		touching = true
	elseif inputType.Name:find("Gamepad") then
		touching = false
		usingGamepad = true
	elseif inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
	then
		touching = false
		usingGamepad = false
	end
end)

local promptAlpha = 0
local shownGamepad: boolean? = nil

local function renderPrompt(deltaTime: number)
	setBound(focused ~= nil)
	if not (container and promptScale and promptKey and promptKeyScale and promptKeyLabel and promptAction) then
		return
	end

	local target = if focused and not touching then 1 else 0
	if promptAlpha < target then
		promptAlpha = math.min(promptAlpha + deltaTime / UI.FadeInTime, target)
	elseif promptAlpha > target then
		promptAlpha = math.max(promptAlpha - deltaTime / UI.FadeOutTime, target)
	end

	pressFlash *= math.exp(-UI.PressDecay * deltaTime)
	if pressFlash < 1e-3 then pressFlash = 0 end

	container.Visible = promptAlpha > 0
	if promptAlpha <= 0 then return end

	if promptAction.Text ~= UI.PickupText then
		promptAction.Text = UI.PickupText
	end
	if usingGamepad ~= shownGamepad then
		shownGamepad = usingGamepad
		local text = if usingGamepad then INPUT.GamepadLabel else INPUT.KeyboardLabel
		promptKeyLabel.Text = text
		layout(if #text <= 1 then UI.KeySize else UI.KeyWideSize)
	end

	container.GroupTransparency = 1 - promptAlpha
	container.Position = UDim2.new(0.5, 0, 0.5, UI.TopMargin + math.round((1 - promptAlpha) * UI.Rise))
	promptScale.Scale = UI.EnterScale + (1 - UI.EnterScale) * promptAlpha

	promptKeyScale.Scale = 1 - UI.PressScale * pressFlash
	promptKey.BackgroundColor3 = COLORS.Key:Lerp(COLORS.KeyPressed, pressFlash)
end

function DrawerItemService:GetFocused(): Model?
	return focused
end

function DrawerItemService:Pickup(): boolean
	local item = focused
	if not item or not States[item] or not PickupRemote then return false end

	local now = os.clock()
	if now - lastPickup < PICKUP_COOLDOWN then return false end
	lastPickup = now

	;(PickupRemote :: RemoteEvent):FireServer(item)
	return true
end

layout(UI.KeySize)

RunService:BindToRenderStep(FOCUS_JOB, Enum.RenderPriority.Camera.Value + 3, renderFocus)
RunService:BindToRenderStep(PROMPT_JOB, Enum.RenderPriority.Last.Value, renderPrompt)

player.CharacterRemoving:Connect(resetHighlight)
player.CharacterAdded:Connect(resetHighlight)

TagService:Listen(ItemConfig.Tag, register, unregister, workspace)

return DrawerItemService
