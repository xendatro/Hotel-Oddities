local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrawerMenuService = {}

if not RunService:IsClient() then
	return DrawerMenuService
end

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local DrawerMenu = require(ReplicatedStorage.Classes.DrawerMenu)
local DrawerService = require(ReplicatedStorage.Services.DrawerService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)

local MENU = DrawerConfig.TouchMenu

local player = Players.LocalPlayer
local playerGui = GuiBuilderService.GetPlayerGui()

local current: { Furniture: Model, Menu: any }? = nil
local nextScan = 0

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local handlers: DrawerMenu.Handlers = {
	Prompt = function(drawer: Model): string?
		return DrawerService:GetPrompt(drawer)
	end,
	Activate = function(drawer: Model)
		DrawerService:Activate(drawer)
	end,
}

local function close()
	if not current then return end
	current.Menu:Destroy()
	current = nil
end

local function open(furniture: Model, drawers: { Model })
	close()
	current = { Furniture = furniture, Menu = DrawerMenu.new(furniture, drawers, handlers, playerGui) }
	current.Menu:Refresh()
end

local function groups(): { [Model]: { Model } }
	local result: { [Model]: { Model } } = {}
	for _, drawer in DrawerService:GetDrawers() do
		local furniture = drawer.Parent
		if not furniture or not furniture:IsA("Model") or not drawer:IsDescendantOf(workspace) then continue end

		local list = result[furniture]
		if not list then
			list = {}
			result[furniture] = list
		end
		table.insert(list, drawer)
	end
	return result
end

local function measure(furniture: Model, drawers: { Model }, root: BasePart, camera: Camera, held: boolean): number?
	if (drawers[1]:GetPivot().Position - root.Position).Magnitude > MENU.Reach + MENU.ScanSkip then return nil end

	local distance = math.huge
	for _, drawer in drawers do
		distance = math.min(distance, (drawer:GetPivot().Position - root.Position).Magnitude)
	end
	if distance > MENU.Reach + MENU.SwitchMargin then return nil end

	local centre = furniture:GetBoundingBox().Position
	if not held then
		local _, onScreen = camera:WorldToViewportPoint(centre)
		if not onScreen then return nil end
	end

	params.FilterDescendantsInstances = { player.Character :: Instance }
	local origin = camera.CFrame.Position
	for _, drawer in drawers do
		local hit = workspace:Raycast(origin, drawer:GetPivot().Position - origin, params)
		if not hit or hit.Instance:IsDescendantOf(furniture) then
			return distance
		end
	end
	return nil
end

local function hidden(): boolean
	if Interaction:GetInputMode() ~= "Touch" then return true end
	local active = InterfaceService:GetActive()
	return active ~= nil and active ~= ""
end

local function scan()
	local camera = workspace.CurrentCamera
	local root = CharacterService.GetAliveRoot(player)
	if hidden() or not camera or not root then
		close()
		return
	end

	local candidates = groups()
	local held = current and current.Furniture
	local heldDistance: number? = nil
	local best: Model? = nil
	local bestDistance = math.huge

	for furniture, drawers in candidates do
		local distance = measure(furniture, drawers, root, camera, furniture == held)
		if not distance then continue end
		if furniture == held then
			heldDistance = distance
		end
		if distance <= MENU.Reach and distance < bestDistance then
			best, bestDistance = furniture, distance
		end
	end

	if current and heldDistance and (not best or best == held or bestDistance > heldDistance - MENU.SwitchMargin) then
		local drawers = candidates[current.Furniture]
		if not current.Menu:Matches(drawers) then
			open(current.Furniture, drawers)
		else
			current.Menu:Refresh()
		end
		return
	end

	if best then
		open(best, candidates[best])
	else
		close()
	end
end

function DrawerMenuService:GetMenu(): any?
	return current and current.Menu
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextScan then return end
	nextScan = now + MENU.Refresh
	scan()
end)

player.CharacterRemoving:Connect(close)

return DrawerMenuService
