local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local PathfinderMarker = require(ReplicatedStorage.Classes.PathfinderMarker)
local ToolCounter = require(ReplicatedStorage.Classes.ToolCounter)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)

--- @class Pathfinder
--- Drops a marker at the player's feet pointing the way they were facing, so a corridor they have
--- already walked reads as walked.
---
--- Entirely client side. The markers exist only for the player who placed them, which is the point:
--- the hotel stays unmapped, and what one player knows is theirs to pass on or not.
---
--- Two versions share this code. The plain tool is a stack of `MaxInWorld` uses that spends one per
--- placement and is gone when the stack empties. The gamepass version never spends, so it hits the
--- cap instead and each new marker recycles the oldest -- an endless trail with a fixed tail.
local Pathfinder = ClientTool.extend("Pathfinder")

-- Module level, not per instance: the trail outlives the tool that made it. Running out destroys the
-- Tool and dying destroys the class instance, but the markers stand until the player leaves.
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

local function ownsUnlimited(): boolean
	return MarketplaceService:UserOwnsGamePass(Players.LocalPlayer, MarketplaceService.Gamepasses.Pathfinder) == true
end

local function reshade()
	local newest = #Markers
	for index, marker in Markers do
		marker:SetShade(newest > 1 and (index - 1) / (newest - 1) or 1)
	end
end

function Pathfinder.new(tool: Tool)
	local self = ClientTool.new(tool, Pathfinder)
	self:_refreshPass()
	return self
end

-- Asking the server can yield, so it never happens inline with a placement. Re-asked on every equip
-- so a pass bought mid-round takes effect without a rejoin.
function Pathfinder:_refreshPass()
	task.spawn(function()
		self.Unlimited = ownsUnlimited()
		self:_updateCounter()
	end)
end

--- Charges left on the device. The server owns this; the client only reads it.
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
	self:_refreshPass()

	self.Counter = ToolCounter.new(self.Config.Caption)
	self:_updateCounter()

	self.UsesChanged = self.Tool:GetAttributeChangedSignal("uses"):Connect(function()
		self.Predicted = nil -- the real number landed; stop guessing
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
	if self.Counter then
		self.Counter:Destroy()
		self.Counter = nil
	end
end

-- The nearest marker within MinSpacing, if there is one.
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

	-- Standing on one already: flare it rather than spending a second marker on the same spot.
	local crowded = self:_crowdedBy(root.Position)
	if crowded then
		crowded:Pulse()
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, markerFolder() }

	local ground = workspace:Raycast(root.Position, Vector3.new(0, -self.Config.SnapDistance, 0), params)
	if not ground then return end -- midair, or over a hole

	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)

	local position = ground.Position + Vector3.new(0, 0.05, 0)

	-- Planted before anything is spent, so a marker that cannot be built -- a missing prop -- costs
	-- the player nothing.
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

	-- Reported even when this player believes they own the pass: the server re-checks and is the one
	-- that decides whether a charge is actually spent.
	self:Fire("Placed")

	if not self.Unlimited then
		-- The charge count comes back from the server a round trip later. The counter shows the
		-- answer now and is corrected when the real one arrives.
		self.Predicted = self:GetUses() - 1
		self:_updateCounter()
	end
end

return Pathfinder
