local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local WalkieTalkieService = require(ServerStorage.Services.WalkieTalkieService)

local WalkieTalkie = ServerTool.extend("WalkieTalkie")

function WalkieTalkie.new(tool: Tool)
	return ServerTool.new(tool, WalkieTalkie)
end

function WalkieTalkie:OnEquipped()
	self.Owner = self:GetPlayer()
	if self.Owner then WalkieTalkieService:Equip(self.Owner, self.Tool) end
end

function WalkieTalkie:OnUnequipped()
	if self.Owner then WalkieTalkieService:Unequip(self.Owner, self.Tool) end
end

function WalkieTalkie:OnDestroy()
	if self.Owner then WalkieTalkieService:Unequip(self.Owner, self.Tool) end
	self.Owner = nil
end

return WalkieTalkie
