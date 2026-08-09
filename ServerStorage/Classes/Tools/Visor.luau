local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)

--- @class Visor
--- Worn rather than carried. While the tool is out its handle goes invisible and a copy of the
--- visor is added to the character as an accessory, so every player sees it sitting on the wearer's
--- face instead of in their hand.
local Visor = ServerTool.extend("Visor")

local WORN_NAME = "VisorWorn"

function Visor.new(tool: Tool)
	local self = ServerTool.new(tool, Visor)

	local handle = tool:FindFirstChild("Handle")
	self.HandleTransparency = if handle and handle:IsA("BasePart") then handle.Transparency else 0
	self.HandleCastShadow = if handle and handle:IsA("BasePart") then handle.CastShadow else true
	self.HiddenFaceVisuals = {}

	return self
end

--- The accessory the tool carries as a template. Cloned per equip; the template itself is never worn.
function Visor:_GetTemplate(): Accessory?
	local template = self.Tool:FindFirstChild(self.Config.FaceAccessory or "Accessory")
	return if template and template:IsA("Accessory") then template else nil
end

function Visor:_SetHandleVisible(visible: boolean)
	local handle = self.Tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end

	handle.Transparency = if visible then self.HandleTransparency else 1
	handle.CastShadow = if visible then self.HandleCastShadow else false
end

local function isFaceAccessory(instance: Instance): boolean
	return instance:IsA("Accessory")
		and instance.AccessoryType == Enum.AccessoryType.Face
		and instance.Name ~= WORN_NAME
end

function Visor:_HideFaceAccessory(accessory: Accessory)
	for _, descendant in accessory:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
			if self.HiddenFaceVisuals[descendant] == nil then
				self.HiddenFaceVisuals[descendant] = descendant.Transparency
			end
			descendant.Transparency = 1
		end
	end
end

function Visor:_HideFaceAccessories()
	local character = self.Character
	if not character then return end

	for _, child in character:GetChildren() do
		if isFaceAccessory(child) then
			self:_HideFaceAccessory(child :: Accessory)
		end
	end

	self.FaceAccessoryAdded = character.ChildAdded:Connect(function(child)
		if isFaceAccessory(child) then
			self:_HideFaceAccessory(child :: Accessory)
		end
	end)
end

function Visor:_RestoreFaceAccessories()
	if self.FaceAccessoryAdded then
		self.FaceAccessoryAdded:Disconnect()
		self.FaceAccessoryAdded = nil
	end

	for visual, transparency in self.HiddenFaceVisuals do
		if visual.Parent then
			visual.Transparency = transparency
		end
	end
	table.clear(self.HiddenFaceVisuals)
end

function Visor:_Wear()
	self:_Remove()

	local humanoid = self.Humanoid
	local template = self:_GetTemplate()
	if not humanoid or not template then return end

	local accessory = template:Clone()
	accessory.Name = WORN_NAME

	-- `AddAccessory` only recognises a part called `Handle`, whatever the template happens to name
	-- its visual.
	local handle = accessory:FindFirstChildWhichIsA("BasePart")
	if not handle then
		accessory:Destroy()
		return
	end
	handle.Name = "Handle"
	handle.CanCollide = false
	handle.Massless = true

	-- Match the standard attachment in an R15 head. Without this, AddAccessory uses its legacy hat
	-- weld and puts the visor at HatAttachment on top of the head.
	local attachment = handle:FindFirstChild("FaceFrontAttachment")
	if not attachment or not attachment:IsA("Attachment") then
		if attachment then attachment:Destroy() end
		attachment = Instance.new("Attachment")
		attachment.Name = "FaceFrontAttachment"
		attachment.Parent = handle
	end
	attachment.CFrame = self.Config.FaceAttachment or CFrame.identity

	humanoid:AddAccessory(accessory)
	self.Worn = accessory
	self:_SetHandleVisible(false)
	self:_HideFaceAccessories()
end

function Visor:_Remove()
	if self.Worn then
		self.Worn:Destroy()
		self.Worn = nil
	end
	self:_RestoreFaceAccessories()
	self:_SetHandleVisible(true)
end

function Visor:OnEquipped()
	self:_Wear()
end

function Visor:OnUnequipped()
	self:_Remove()
end

function Visor:OnDestroy()
	self:_Remove()
end

return Visor
