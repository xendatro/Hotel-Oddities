local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GateConfig = require(ReplicatedStorage.Configs.GateConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local GateService = {}

local UnlockRemote = CommunicationService.Get(GateConfig.Remotes.Folder, GateConfig.Remotes.Unlock) :: RemoteEvent
local REACH = GateConfig.Targeting.ServerReach

type PartState = {
	Part: BasePart,
	ClosedCFrame: CFrame,
}

type Panel = {
	Model: Model,
	Hinge: Vector3,
	Parts: { PartState },
	TargetAngle: number,
}

type State = {
	Model: Model,
	Left: Panel,
	Right: Panel,
	Opened: boolean,
}

local States: { [Model]: State } = {}
local LastUnlock: { [Player]: number } = {}

local function panel(model: Model, name: string): Panel
	local panelModel = model:FindFirstChild(name) :: Model
	local parts = {}
	for _, descendant in panelModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, {
				Part = descendant,
				ClosedCFrame = descendant.CFrame,
			})
		end
	end

	return {
		Model = panelModel,
		Hinge = panelModel:GetPivot().Position,
		Parts = parts,
		TargetAngle = 0,
	}
end

local function register(model: Instance)
	if not model:IsA("Model") then return end
	local gate = model :: Model
	States[gate] = {
		Model = gate,
		Left = panel(gate, "Left"),
		Right = panel(gate, "Right"),
		Opened = false,
	}
end

local function unregister(model: Instance)
	States[model :: Model] = nil
end

local function tweenPanel(panel_: Panel, tweenInfo: TweenInfo)
	local rotation = CFrame.new(panel_.Hinge)
		* CFrame.Angles(0, math.rad(panel_.TargetAngle), 0)
		* CFrame.new(-panel_.Hinge)
	for _, part in panel_.Parts do
		local goal = rotation * part.ClosedCFrame
		TweenService:Create(part.Part, tweenInfo, {
			CFrame = goal,
		}):Play()
	end
end

local function open(state: State, playerPosition: Vector3): boolean
	if state.Opened then return false end

	local localPosition = state.Model:GetPivot():PointToObjectSpace(playerPosition)
	local playerSide = if localPosition.Z >= 0 then 1 else -1
	state.Left.TargetAngle = GateConfig.OpenAngle * playerSide
	state.Right.TargetAngle = -GateConfig.OpenAngle * playerSide
	state.Opened = true

	local tweenInfo = TweenInfo.new(GateConfig.OpenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	tweenPanel(state.Left, tweenInfo)
	tweenPanel(state.Right, tweenInfo)
	return true
end

UnlockRemote.OnServerEvent:Connect(function(player: Player, model: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if not model:IsDescendantOf(workspace) or not CollectionService:HasTag(model, GateConfig.Tag) then return end

	local state = States[model]
	if not state then return end

	local now = os.clock()
	if now - (LastUnlock[player] or 0) < GateConfig.Cooldown then return end

	local playerPosition = CharacterService.GetPosition(player)
	if not playerPosition or (model:GetPivot().Position - playerPosition).Magnitude > REACH then return end

	local character = player.Character
	local tool = InventoryService:Get(player, GateConfig.ToolName)
	if not tool or tool.Parent ~= character or (tool:GetAttribute("quantity") or 0) < 1 then return end

	if not open(state, playerPosition) then return end

	LastUnlock[player] = now
	InventoryService:Remove(player, GateConfig.ToolName, 1)
end)

CollectionService:GetInstanceAddedSignal(GateConfig.Tag):Connect(register)
CollectionService:GetInstanceRemovedSignal(GateConfig.Tag):Connect(unregister)

for _, instance in CollectionService:GetTagged(GateConfig.Tag) do
	register(instance)
end

Players.PlayerRemoving:Connect(function(player: Player)
	LastUnlock[player] = nil
end)

return GateService
