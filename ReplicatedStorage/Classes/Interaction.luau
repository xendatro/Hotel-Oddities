local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)

local Interaction = {}
Interaction.__index = Interaction

export type Prompt = string | ((model: Model) -> string?)

export type TargetOptions = {
	Prompt: Prompt,
	TextWidth: number?,
	CanSelect: ((model: Model) -> boolean)?,
	Reach: number?,
	IgnoreOcclusion: boolean?,
	HoldDuration: number?,
	OnActivated: ((model: Model) -> boolean)?,
}

type Target = {
	Model: Model,
	Prompt: Prompt,
	TextWidth: number?,
	CanSelect: ((model: Model) -> boolean)?,
	Reach: number?,
	IgnoreOcclusion: boolean?,
	HoldDuration: number?,
	OnActivated: ((model: Model) -> boolean)?,
}

type Candidate = {
	Target: Target,
	Distance: number,
	Score: number,
}

local TARGETING = DrawerConfig.Targeting
local INPUT = DrawerConfig.Input
local HIGHLIGHT = DrawerConfig.Highlight
local UI = DrawerConfig.UI

local ACTION_NAME = "InteractionActivate"
local RENDER_JOB = "Interaction"
local HIGHLIGHT_FADE_SPEED = 16
local HIGHLIGHT_NAME = "InteractionHighlight"
local PROMPT_NAME = "InteractionPrompt"

local player = Players.LocalPlayer

function Interaction.new()
	local self = setmetatable({}, Interaction)

	self._targets = {}
	self._includeModels = {}
	self._selected = nil
	self._selectedTarget = nil
	self._reach = TARGETING.Reach
	self._highlightAlpha = 0
	self._promptAlpha = 0
	self._pressFlash = 0
	self._holdTarget = nil :: Target?
	self._holdStart = 0
	self._holdAlpha = 0
	self._shownText = ""
	self._shownTextWidth = 0
	self._shownKey = ""
	self._touching = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	self._usingGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	self._bound = false
	self._targetsDirty = false
	self._cachedCharacter = nil :: Model?
	self._cachedHumanoid = nil :: Humanoid?
	self._touchTarget = nil :: Target?
	self._touchScanAt = 0
	self._touchScreen = nil :: Vector2?
	self._tapInput = nil :: InputObject?

	self._selectionChanged = Instance.new("BindableEvent")
	self.Selected = self._selectionChanged.Event

	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._ignored = {}

	self._includeParams = RaycastParams.new()
	self._includeParams.FilterType = Enum.RaycastFilterType.Include

	self._highlight = nil :: Highlight?

	self:_buildPrompt()

	self._inputConnection = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if inputType == Enum.UserInputType.Touch then
			self._touching = true
		elseif inputType.Name:find("Gamepad") then
			self._touching = false
			self._usingGamepad = true
		elseif inputType == Enum.UserInputType.Keyboard
			or inputType == Enum.UserInputType.MouseButton1
			or inputType == Enum.UserInputType.MouseButton2
			or inputType == Enum.UserInputType.MouseMovement
		then
			self._touching = false
			self._usingGamepad = false
		end
	end)

	self._tapConnection = UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		if processedByUI or not self._touching then return end
		self:_tapWorld(position)
	end)

	self._releaseConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input ~= self._tapInput then return end
		self._tapInput = nil
		self:_cancelHold()
	end)

	self._characterRemoving = player.CharacterRemoving:Connect(function()
		self:_reset()
	end)
	self._characterAdded = player.CharacterAdded:Connect(function()
		self:_reset()
	end)

	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 3, function(deltaTime: number)
		self:_render(deltaTime)
	end)

	return self
end

function Interaction:_buildPrompt()
	local playerGui = player:WaitForChild("PlayerGui")
	local cursor = playerGui:WaitForChild("Cursor", 30) :: ScreenGui?
	if not cursor then
		warn(`Interaction: no Cursor gui; the interaction prompt will not draw`)
		return
	end

	local template = cursor:WaitForChild(UI.Container, 30)
	if not template then
		warn(`Interaction: no {UI.Container} under the Cursor gui; the interaction prompt will not draw`)
		return
	end

	local container = template:Clone() :: CanvasGroup
	container.Name = PROMPT_NAME
	container.Visible = false
	container.GroupTransparency = 1
	container.Parent = cursor

	local scale = container:FindFirstChild("Scale") :: UIScale
	local pill = container:FindFirstChild("Pill") :: Frame
	local key = pill and pill:FindFirstChild("Key") :: Frame
	local keyScale = key and key:FindFirstChild("Scale") :: UIScale
	local keyLabel = key and key:FindFirstChild("Label") :: TextLabel
	local action = pill and pill:FindFirstChild("Action") :: TextLabel

	if not (scale and pill and key and keyScale and keyLabel and action) then
		warn(`Interaction: the {UI.Container} prompt is not shaped as expected; the interaction prompt will not draw`)
		container:Destroy()
		return
	end

	local fill = Instance.new("Frame")
	fill.Name = "Hold"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UI.Colors.KeyPressed
	fill.BackgroundTransparency = UI.HoldFillTransparency
	fill.BorderSizePixel = 0
	fill.ZIndex = 0
	fill.Visible = false

	local fillCorner = pill:FindFirstChildOfClass("UICorner")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if fillCorner then fillCorner.CornerRadius else UDim.new(0, 10)
	corner.Parent = fill
	fill.Parent = pill

	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.Size = UDim2.fromScale(1, 1)
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.ZIndex = 10
	tap.Visible = false
	tap.Parent = container

	tap.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
		if self:_begin() then
			self._tapInput = input
		end
	end)

	self._prompt = {
		Container = container,
		Anchor = container.AnchorPoint,
		Scale = scale,
		Pill = pill,
		Key = key,
		KeyScale = keyScale,
		KeyLabel = keyLabel,
		Action = action,
		Fill = fill,
		Tap = tap,
	}
	self:_layout(UI.KeySize, UI.TextWidth)
end

function Interaction:_layout(keyWidth: number, textWidth: number)
	local prompt = self._prompt
	if not prompt then return end

	local left = UI.PillPaddingLeft + keyWidth + UI.KeyGap
	local width = left + textWidth + UI.PillPaddingRight

	prompt.Container.Size = UDim2.fromOffset(width + UI.Padding * 2, UI.PillHeight + UI.Padding * 2)
	prompt.Pill.Size = UDim2.fromOffset(width, UI.PillHeight)
	prompt.Key.Size = UDim2.fromOffset(keyWidth, UI.KeySize)
	prompt.Action.Position = UDim2.new(0, left, 0.5, 0)
	prompt.Action.Size = UDim2.fromOffset(textWidth, UI.KeySize)
end

function Interaction:_refreshIncludeFilter()
	table.clear(self._includeModels)
	for model, target in self._targets do
		if target.IgnoreOcclusion then
			table.insert(self._includeModels, model)
		end
	end
	self._includeParams.FilterDescendantsInstances = self._includeModels
end

function Interaction:_refreshReach()
	self._reach = TARGETING.Reach
	for _, target in self._targets do
		self._reach = math.max(self._reach, target.Reach or TARGETING.Reach)
	end
end

function Interaction:Register(model: Model, options: TargetOptions)
	self._targets[model] = {
		Model = model,
		Prompt = options.Prompt,
		TextWidth = options.TextWidth,
		CanSelect = options.CanSelect,
		Reach = options.Reach,
		IgnoreOcclusion = options.IgnoreOcclusion,
		HoldDuration = options.HoldDuration,
		OnActivated = options.OnActivated,
	}
	self._targetsDirty = true
end

function Interaction:Unregister(model: Model)
	if not self._targets[model] then return end

	self._targets[model] = nil
	self._targetsDirty = true

	if self._touchTarget and self._touchTarget.Model == model then
		self._touchTarget = nil
	end

	if self._selected == model then
		self:_setSelected(nil, true)
	end
end

function Interaction:_promptFor(target: Target): string?
	local prompt = target.Prompt
	local text = if type(prompt) == "function" then prompt(target.Model) else prompt
	return if text and text ~= "" then text else nil
end

function Interaction:_selectable(target: Target, distance: number): (boolean, string?)
	if not target.Model:IsDescendantOf(workspace) then return false, nil end
	if distance > (target.Reach or TARGETING.Reach) then return false, nil end
	if target.CanSelect and not target.CanSelect(target.Model) then return false, nil end

	local text = self:_promptFor(target)
	return text ~= nil, text
end

function Interaction:_targetAt(instance: Instance): Target?
	while instance and instance ~= workspace do
		local target = self._targets[instance]
		if target then return target end
		instance = instance.Parent
	end
	return nil
end

function Interaction:_resetIgnored(character: Model)
	local ignored = self._ignored
	if ignored[1] ~= character or #ignored > 1 then
		table.clear(ignored)
		ignored[1] = character
		self._raycastParams.FilterDescendantsInstances = ignored
	end
end

function Interaction:_castFrom(origin: Vector3, direction: Vector3): (Target?, string?)
	for _ = 1, TARGETING.MaxPassthrough + 1 do
		local result = workspace:Raycast(origin, direction, self._raycastParams)
		if not result then break end

		local target = self:_targetAt(result.Instance)
		if target then
			local selectable, text = self:_selectable(target, result.Distance)
			if selectable then return target, text end
			return nil, nil
		end

		if result.Instance.CanCollide or result.Instance.Transparency < 1 then break end
		table.insert(self._ignored, result.Instance)
		self._raycastParams.FilterDescendantsInstances = self._ignored
	end

	if #self._includeModels == 0 then return nil, nil end

	local result = workspace:Raycast(origin, direction, self._includeParams)
	if not result then return nil, nil end

	local target = self:_targetAt(result.Instance)
	if not target or not target.IgnoreOcclusion then return nil, nil end

	local selectable, text = self:_selectable(target, result.Distance)
	if selectable then return target, text end
	return nil, nil
end

function Interaction:_touchPoint(target: Target): (Vector3, number)
	local cframe, size = target.Model:GetBoundingBox()
	return cframe.Position, math.max(size.X, size.Y, size.Z) / 2
end

function Interaction:_inSight(origin: Vector3, point: Vector3, target: Target): boolean
	local direction = point - origin
	for _ = 1, TARGETING.MaxPassthrough + 1 do
		local result = workspace:Raycast(origin, direction, self._raycastParams)
		if not result then return true end
		if self:_targetAt(result.Instance) == target then return true end
		if result.Instance.CanCollide or result.Instance.Transparency < 1 then return false end
		table.insert(self._ignored, result.Instance)
		self._raycastParams.FilterDescendantsInstances = self._ignored
	end
	return false
end

function Interaction:_scanTouch(camera: Camera): Target?
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local candidates: { Candidate } = {}

	for model, target in self._targets do
		if not model:IsDescendantOf(workspace) then continue end

		local reach = target.Reach or TARGETING.Reach
		if (model:GetPivot().Position - origin).Magnitude > reach + TARGETING.TouchScanMargin then continue end

		local point, radius = self:_touchPoint(target)
		local offset = point - origin
		local distance = math.max(offset.Magnitude - radius, 0)
		if distance > reach then continue end

		local _, onScreen = camera:WorldToViewportPoint(point)
		if not onScreen then continue end

		local facing = if offset.Magnitude > 1e-3 then offset.Unit:Dot(look) else 1
		table.insert(candidates, {
			Target = target,
			Distance = distance,
			Score = distance * (2 - facing),
		})
	end

	table.sort(candidates, function(a: Candidate, b: Candidate)
		return a.Score < b.Score
	end)

	for _, candidate in candidates do
		local target = candidate.Target
		if not self:_selectable(target, candidate.Distance) then continue end
		if target.IgnoreOcclusion then return target end

		local point = self:_touchPoint(target)
		if self:_inSight(origin, point, target) then return target end
	end

	return nil
end

function Interaction:_findTouchSelection(camera: Camera): (Target?, string?)
	local now = os.clock()
	if now >= self._touchScanAt then
		self._touchScanAt = now + TARGETING.TouchRefresh
		self._touchTarget = self:_scanTouch(camera)
	end

	local target = self._touchTarget
	if not target then return nil, nil end

	local selectable, text = self:_selectable(target, 0)
	if not selectable then
		self._touchTarget = nil
		return nil, nil
	end
	return target, text
end

function Interaction:_findSelection(): (Target?, string?)
	if self._targetsDirty then
		self._targetsDirty = false
		self:_refreshIncludeFilter()
		self:_refreshReach()
	end

	local camera = workspace.CurrentCamera
	local character = player.Character
	if character ~= self._cachedCharacter then
		self._cachedCharacter = character
		self._cachedHumanoid = nil
	end
	if character and not self._cachedHumanoid then
		self._cachedHumanoid = character:FindFirstChildOfClass("Humanoid")
	end
	local humanoid = self._cachedHumanoid
	if not camera or not character or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end

	self:_resetIgnored(character)

	if self._touching then
		return self:_findTouchSelection(camera)
	end

	return self:_castFrom(camera.CFrame.Position, camera.CFrame.LookVector * self._reach)
end

function Interaction:_tapWorld(position: Vector2)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = self._cachedHumanoid
	if not camera or not character or character ~= self._cachedCharacter or not humanoid or humanoid.Health <= 0 then
		return
	end

	self:_resetIgnored(character)
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local target = self:_castFrom(ray.Origin, ray.Direction * self._reach)
	if not target then return end

	self._touchTarget = target
	self._touchScanAt = os.clock() + TARGETING.TouchRefresh
	if target.HoldDuration and target.HoldDuration > 0 then return end
	self:_activate(target)
end

function Interaction:_applyHighlightAlpha()
	local highlight = self._highlight
	if not highlight then return end

	highlight.FillTransparency = 1 - (1 - HIGHLIGHT.FillTransparency) * self._highlightAlpha
	highlight.OutlineTransparency = 1 - (1 - HIGHLIGHT.OutlineTransparency) * self._highlightAlpha
end

function Interaction:_destroyHighlight()
	self._highlightAlpha = 0
	if not self._highlight then return end

	self._highlight:Destroy()
	self._highlight = nil
end

function Interaction:_createHighlight(model: Model)
	self:_destroyHighlight()

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.FillColor = HIGHLIGHT.FillColor
	highlight.OutlineColor = HIGHLIGHT.OutlineColor
	highlight.DepthMode = HIGHLIGHT.DepthMode
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = model
	self._highlight = highlight
end

function Interaction:_setSelected(target: Target?, immediate: boolean?)
	local model = target and target.Model or nil
	if model == self._selected then
		self._selectedTarget = target
		return
	end

	self._selected = model
	self._selectedTarget = target
	self._selectionChanged:Fire(model)

	if model then
		if not (self._highlight and self._highlight.Parent == model) then
			self:_createHighlight(model)
		end
	elseif immediate then
		self:_destroyHighlight()
	end
end

function Interaction:_ensureHighlight()
	local selected = self._selected
	if selected and not selected:IsDescendantOf(workspace) then
		self:_setSelected(nil, true)
	end

	local highlight = self._highlight
	if highlight and not highlight.Parent then
		self:_destroyHighlight()
	end
end

function Interaction:_setBound(text: string?)
	local shouldBind = text ~= nil
	if shouldBind == self._bound then return end
	self._bound = shouldBind

	if not shouldBind then
		ContextActionService:UnbindAction(ACTION_NAME)
		return
	end

	ContextActionService:BindAction(
		ACTION_NAME,
		function(action: string, inputState: Enum.UserInputState)
			return self:_onAction(action, inputState)
		end,
		false,
		table.unpack(INPUT.Keys)
	)
end

function Interaction:_activate(target: Target)
	if target.OnActivated and target.OnActivated(target.Model) then
		self._pressFlash = 1
	end
end

function Interaction:_cancelHold()
	self._holdTarget = nil
	self._holdStart = 0
	self._holdAlpha = 0
end

function Interaction:_renderHold()
	local target = self._holdTarget
	if not target then return end

	if self._selectedTarget ~= target or not self:_selectable(target, 0) then
		self:_cancelHold()
		return
	end

	local duration = target.HoldDuration or 0
	self._holdAlpha = if duration > 0
		then math.clamp((os.clock() - self._holdStart) / duration, 0, 1)
		else 1
	if self._holdAlpha < 1 then return end

	self:_cancelHold()
	self:_activate(target)
end

function Interaction:_begin(): boolean
	local target = self._selectedTarget
	if not target then return false end
	if not self:_selectable(target, 0) then return false end

	if target.HoldDuration and target.HoldDuration > 0 then
		self._holdTarget = target
		self._holdStart = os.clock()
		return true
	end

	self:_activate(target)
	return true
end

function Interaction:_onAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self:_cancelHold()
		return Enum.ContextActionResult.Pass
	end
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end

	self:_begin()
	return Enum.ContextActionResult.Pass
end

function Interaction:_renderHighlight(deltaTime: number)
	if self._selected and not self._highlight then
		self:_createHighlight(self._selected)
	end

	local target = if self._selected then 1 else 0
	local previousAlpha = self._highlightAlpha
	self._highlightAlpha += (target - self._highlightAlpha)
		* (1 - math.exp(-HIGHLIGHT_FADE_SPEED * deltaTime))
	if math.abs(target - self._highlightAlpha) < 1e-3 then
		self._highlightAlpha = target
	end

	if self._highlightAlpha <= 0 then
		self:_destroyHighlight()
		return
	end

	if self._highlightAlpha ~= previousAlpha then
		self:_applyHighlightAlpha()
	end
end

function Interaction:_keyText(target: Target?): string
	if self._touching then
		if not target then
			return if self._shownKey ~= "" then self._shownKey else INPUT.TouchLabel
		end
		return if target.HoldDuration and target.HoldDuration > 0 then INPUT.TouchHoldLabel else INPUT.TouchLabel
	end
	return if self._usingGamepad then INPUT.GamepadLabel else INPUT.KeyboardLabel
end

function Interaction:_touchScreenPoint(target: Target?): Vector2?
	local camera = workspace.CurrentCamera
	if not (target and camera) then return nil end

	local point = self:_touchPoint(target)
	local screen, onScreen = camera:WorldToViewportPoint(point)
	if not onScreen then return nil end
	return Vector2.new(screen.X, screen.Y)
end

function Interaction:_renderPrompt(deltaTime: number, text: string?, target: Target?)
	self:_setBound(text)

	local prompt = self._prompt
	if not prompt then return end

	local alphaTarget = if text then 1 else 0
	if self._promptAlpha < alphaTarget then
		self._promptAlpha = math.min(self._promptAlpha + deltaTime / UI.FadeInTime, alphaTarget)
	elseif self._promptAlpha > alphaTarget then
		self._promptAlpha = math.max(self._promptAlpha - deltaTime / UI.FadeOutTime, alphaTarget)
	end

	self._pressFlash *= math.exp(-UI.PressDecay * deltaTime)
	if self._pressFlash < 1e-3 then self._pressFlash = 0 end

	prompt.Container.Visible = self._promptAlpha > 0
	prompt.Tap.Visible = self._touching and text ~= nil
	if self._promptAlpha <= 0 then return end

	local shownText = text or self._shownText
	if shownText == "" then return end
	local textWidth = if target
		then math.max(target.TextWidth or UI.TextWidth, #shownText * 8)
		else self._shownTextWidth
	if shownText ~= self._shownText then
		self._shownText = shownText
		prompt.Action.Text = shownText
	end

	local keyText = self:_keyText(target)
	if textWidth ~= self._shownTextWidth or keyText ~= self._shownKey then
		self._shownTextWidth = textWidth
		self._shownKey = keyText
		prompt.KeyLabel.Text = keyText
		self:_layout(if #keyText <= 1 then UI.KeySize else UI.KeyWideSize, textWidth)
	end

	prompt.Fill.Visible = self._holdAlpha > 0
	prompt.Fill.Size = UDim2.new(self._holdAlpha, 0, 1, 0)

	local rise = math.round((1 - self._promptAlpha) * UI.Rise)
	if self._touching then
		self._touchScreen = self:_touchScreenPoint(target) or self._touchScreen
	end
	local anchored = self._touching and self._touchScreen
	if anchored then
		prompt.Container.AnchorPoint = Vector2.new(0.5, 0.5)
		prompt.Container.Position = UDim2.fromOffset(anchored.X, anchored.Y + rise)
	else
		prompt.Container.AnchorPoint = prompt.Anchor
		prompt.Container.Position = UDim2.new(0.5, 0, 0.5, UI.TopMargin + rise)
	end

	prompt.Container.GroupTransparency = 1 - self._promptAlpha
	prompt.Scale.Scale = UI.EnterScale + (1 - UI.EnterScale) * self._promptAlpha
	prompt.KeyScale.Scale = 1 - UI.PressScale * self._pressFlash
	prompt.Key.BackgroundColor3 = UI.Colors.Key:Lerp(UI.Colors.KeyPressed, self._pressFlash)
end

function Interaction:_render(deltaTime: number)
	self:_ensureHighlight()
	local target, text = self:_findSelection()
	self:_setSelected(target)
	self:_renderHold()
	self:_renderHighlight(deltaTime)
	self:_renderPrompt(deltaTime, text, target)
end

function Interaction:_reset()
	local wasSelected = self._selected ~= nil
	self._selected = nil
	self._selectedTarget = nil
	self._touchTarget = nil
	self._touchScreen = nil
	self._tapInput = nil
	self:_destroyHighlight()
	self._promptAlpha = 0
	self._pressFlash = 0
	self:_cancelHold()
	if wasSelected then
		self._selectionChanged:Fire(nil)
	end
end

function Interaction:GetSelected(): Model?
	return self._selected
end

function Interaction:Destroy()
	RunService:UnbindFromRenderStep(RENDER_JOB)
	if self._bound then
		ContextActionService:UnbindAction(ACTION_NAME)
	end
	self._inputConnection:Disconnect()
	self._tapConnection:Disconnect()
	self._releaseConnection:Disconnect()
	self._characterRemoving:Disconnect()
	self._characterAdded:Disconnect()
	self._selectionChanged:Destroy()
	self:_destroyHighlight()
	if self._prompt then
		self._prompt.Container:Destroy()
	end
end

return Interaction
