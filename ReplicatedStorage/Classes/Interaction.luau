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
	OnActivated: ((model: Model) -> boolean)?,
}

type Target = {
	Model: Model,
	Prompt: Prompt,
	TextWidth: number?,
	CanSelect: ((model: Model) -> boolean)?,
	Reach: number?,
	IgnoreOcclusion: boolean?,
	OnActivated: ((model: Model) -> boolean)?,
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
	self._shownText = ""
	self._shownTextWidth = 0
	self._shownGamepad = nil
	self._shownTouchTitle = ""
	self._touching = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	self._usingGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	self._bound = false
	self._boundTouching = nil
	self._targetsDirty = false
	self._cachedCharacter = nil :: Model?
	self._cachedHumanoid = nil :: Humanoid?

	self._selectionChanged = Instance.new("BindableEvent")
	self.Selected = self._selectionChanged.Event

	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._ignored = {}

	self._includeParams = RaycastParams.new()
	self._includeParams.FilterType = Enum.RaycastFilterType.Include

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.FillColor = HIGHLIGHT.FillColor
	highlight.OutlineColor = HIGHLIGHT.OutlineColor
	highlight.DepthMode = HIGHLIGHT.DepthMode
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Adornee = nil
	highlight.Parent = workspace
	self._highlight = highlight

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

	self._prompt = {
		Container = container,
		Scale = scale,
		Pill = pill,
		Key = key,
		KeyScale = keyScale,
		KeyLabel = keyLabel,
		Action = action,
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
		OnActivated = options.OnActivated,
	}
	self._targetsDirty = true
end

function Interaction:Unregister(model: Model)
	if not self._targets[model] then return end

	self._targets[model] = nil
	self._targetsDirty = true

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

	local ignored = self._ignored
	if ignored[1] ~= character or #ignored > 1 then
		table.clear(ignored)
		ignored[1] = character
		self._raycastParams.FilterDescendantsInstances = ignored
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * self._reach

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
		self._highlight.Adornee = model
		self._highlight.Enabled = true
	elseif immediate then
		self._highlightAlpha = 0
		self._highlight.Enabled = false
		self._highlight.Adornee = nil
	end
end

function Interaction:_ensureHighlight()
	if self._highlight.Parent ~= workspace then
		self._highlight.Parent = workspace
	end
	if self._highlight.Adornee and not self._highlight.Adornee:IsDescendantOf(workspace) then
		self:_setSelected(nil, true)
	end
end

function Interaction:_setBound(text: string?)
	local shouldBind = text ~= nil
	if shouldBind == self._bound and self._boundTouching == self._touching then
		if shouldBind and self._touching and text ~= self._shownTouchTitle then
			self._shownTouchTitle = text :: string
			ContextActionService:SetTitle(ACTION_NAME, (text :: string):upper())
		end
		return
	end

	if self._bound then
		ContextActionService:UnbindAction(ACTION_NAME)
	end

	self._bound = shouldBind
	self._boundTouching = if shouldBind then self._touching else nil
	self._shownTouchTitle = ""
	if not shouldBind then return end

	ContextActionService:BindAction(
		ACTION_NAME,
		function(action: string, inputState: Enum.UserInputState)
			return self:_onAction(action, inputState)
		end,
		self._touching,
		table.unpack(INPUT.Keys)
	)

	if not self._touching then return end

	self._shownTouchTitle = text :: string
	ContextActionService:SetTitle(ACTION_NAME, (text :: string):upper())
	ContextActionService:SetPosition(ACTION_NAME, INPUT.TouchButtonPosition)
	local button = ContextActionService:GetButton(ACTION_NAME)
	if button then
		button.Size = INPUT.TouchButtonSize
	end
end

function Interaction:_onAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end

	local target = self._selectedTarget
	if not target then return Enum.ContextActionResult.Pass end

	local selectable = self:_selectable(target, 0)
	if not selectable then return Enum.ContextActionResult.Pass end

	if target.OnActivated and target.OnActivated(target.Model) then
		self._pressFlash = 1
	end
	return Enum.ContextActionResult.Pass
end

function Interaction:_renderHighlight(deltaTime: number)
	local target = if self._selected then 1 else 0
	local previousAlpha = self._highlightAlpha
	self._highlightAlpha += (target - self._highlightAlpha)
		* (1 - math.exp(-HIGHLIGHT_FADE_SPEED * deltaTime))
	if math.abs(target - self._highlightAlpha) < 1e-3 then
		self._highlightAlpha = target
	end

	if self._highlightAlpha <= 0 then
		if self._highlight.Enabled then
			self._highlight.Enabled = false
			self._highlight.Adornee = nil
		end
		return
	end

	if self._highlightAlpha ~= previousAlpha then
		self._highlight.FillTransparency = 1 - (1 - HIGHLIGHT.FillTransparency) * self._highlightAlpha
		self._highlight.OutlineTransparency = 1 - (1 - HIGHLIGHT.OutlineTransparency) * self._highlightAlpha
	end
end

function Interaction:_renderPrompt(deltaTime: number, text: string?, target: Target?)
	self:_setBound(text)

	local prompt = self._prompt
	if not prompt then return end

	local alphaTarget = if text and not self._touching then 1 else 0
	if self._promptAlpha < alphaTarget then
		self._promptAlpha = math.min(self._promptAlpha + deltaTime / UI.FadeInTime, alphaTarget)
	elseif self._promptAlpha > alphaTarget then
		self._promptAlpha = math.max(self._promptAlpha - deltaTime / UI.FadeOutTime, alphaTarget)
	end

	self._pressFlash *= math.exp(-UI.PressDecay * deltaTime)
	if self._pressFlash < 1e-3 then self._pressFlash = 0 end

	prompt.Container.Visible = self._promptAlpha > 0
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
	if textWidth ~= self._shownTextWidth then
		self._shownTextWidth = textWidth
		local keyWidth = if self._usingGamepad
			then (if #INPUT.GamepadLabel <= 1 then UI.KeySize else UI.KeyWideSize)
			else UI.KeySize
		self:_layout(keyWidth, textWidth)
	end

	if self._usingGamepad ~= self._shownGamepad then
		self._shownGamepad = self._usingGamepad
		local keyText = if self._usingGamepad then INPUT.GamepadLabel else INPUT.KeyboardLabel
		prompt.KeyLabel.Text = keyText
		self:_layout(if #keyText <= 1 then UI.KeySize else UI.KeyWideSize, textWidth)
	end

	prompt.Container.GroupTransparency = 1 - self._promptAlpha
	prompt.Container.Position = UDim2.new(0.5, 0, 0.5, UI.TopMargin + math.round((1 - self._promptAlpha) * UI.Rise))
	prompt.Scale.Scale = UI.EnterScale + (1 - UI.EnterScale) * self._promptAlpha
	prompt.KeyScale.Scale = 1 - UI.PressScale * self._pressFlash
	prompt.Key.BackgroundColor3 = UI.Colors.Key:Lerp(UI.Colors.KeyPressed, self._pressFlash)
end

function Interaction:_render(deltaTime: number)
	self:_ensureHighlight()
	local target, text = self:_findSelection()
	self:_setSelected(target)
	self:_renderHighlight(deltaTime)
	self:_renderPrompt(deltaTime, text, target)
end

function Interaction:_reset()
	local wasSelected = self._selected ~= nil
	self._selected = nil
	self._selectedTarget = nil
	self._highlightAlpha = 0
	self._highlight.Enabled = false
	self._highlight.Adornee = nil
	self._promptAlpha = 0
	self._pressFlash = 0
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
	self._characterRemoving:Disconnect()
	self._characterAdded:Disconnect()
	self._selectionChanged:Destroy()
	self._highlight:Destroy()
	if self._prompt then
		self._prompt.Container:Destroy()
	end
end

return Interaction
