local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local PathfinderMarker = require(ReplicatedStorage.Classes.PathfinderMarker)
local ToolCounter = require(ReplicatedStorage.Classes.ToolCounter)
local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)

local Pathfinder = ClientTool.extend("Pathfinder")

local Markers: { any } = {}
local Placed = 0
local Folder: Folder? = nil

local function markerFolder(): Folder
	if Folder and Folder.Parent then
		return Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "PathfinderMarkers"
	folder.Parent = workspace
	Folder = folder
	return folder
end

local UNLIMITED_ATTRIBUTE = PerkConfig.AttributePrefix .. "Pathfinder"

local function ownsUnlimited(): boolean
	return Players.LocalPlayer:GetAttribute(UNLIMITED_ATTRIBUTE) == true
end

local function reshade()
	local newest = #Markers
	for index, marker in Markers do
		marker:SetShade(newest > 1 and (index - 1) / (newest - 1) or 1)
	end
end

function Pathfinder.new(tool: Tool)
	local self = ClientTool.new(tool, Pathfinder)
	self.Unlimited = ownsUnlimited()
	return self
end

function Pathfinder:GetUses(): number
	return self.Tool:GetAttribute("uses") or self.Config.Uses
end

function Pathfinder:_updateCounter()
	if not self.Counter then return end

	if self.Unlimited then
		self.Counter:Set()
		return
	end

	self.Counter:Set(math.max(self.Predicted or self:GetUses(), 0), self.Config.Uses)
end

function Pathfinder:OnEquipped()
	self.Unlimited = ownsUnlimited()

	self.Counter = ToolCounter.new(self.Config.Caption)
	self:_updateCounter()

	self.PassChanged = Players.LocalPlayer:GetAttributeChangedSignal(UNLIMITED_ATTRIBUTE):Connect(function()
		self.Unlimited = ownsUnlimited()
		self:_updateCounter()
	end)

	self.UsesChanged = self.Tool:GetAttributeChangedSignal("uses"):Connect(function()
		self.Predicted = nil
		self:_updateCounter()
	end)
end

function Pathfinder:OnUnequipped()
	self:_closeCounter()
end

function Pathfinder:OnDestroy()
	self:_closeCounter()
end

function Pathfinder:_closeCounter()
	self.Predicted = nil

	if self.UsesChanged then
		self.UsesChanged:Disconnect()
		self.UsesChanged = nil
	end
	if self.PassChanged then
		self.PassChanged:Disconnect()
		self.PassChanged = nil
	end
	if self.Counter then
		self.Counter:Destroy()
		self.Counter = nil
	end
end

function Pathfinder:_crowdedBy(position: Vector3)
	for _, marker in Markers do
		if (marker.Position - position).Magnitude <= self.Config.MinSpacing then
			return marker
		end
	end
	return nil
end

function Pathfinder:OnActivated()
	local character = self.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if not self.Unlimited and self:GetUses() <= 0 then return end

	local crowded = self:_crowdedBy(root.Position)
	if crowded then
		crowded:Pulse()
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, markerFolder() }

	local ground = workspace:Raycast(root.Position, Vector3.new(0, -self.Config.SnapDistance, 0), params)
	if not ground then return end

	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)

	local position = ground.Position + Vector3.new(0, 0.05, 0)

	local marker = PathfinderMarker.new(
		CFrame.lookAt(position, position + look),
		Placed + 1,
		self.Config,
		markerFolder()
	)
	if not marker then return end

	Placed += 1
	table.insert(Markers, marker)

	while #Markers > self.Config.MaxInWorld do
		local oldest = table.remove(Markers, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	reshade()

	self:Fire("Placed")

	if not self.Unlimited then
		self.Predicted = self:GetUses() - 1
		self:_updateCounter()
	end
end

return Pathfinder
