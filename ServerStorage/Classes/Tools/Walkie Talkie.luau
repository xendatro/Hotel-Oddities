local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local WalkieTalkieService = require(ServerStorage.Services.WalkieTalkieService)

local WalkieTalkie = ServerTool.extend("WalkieTalkie")

function WalkieTalkie.new(tool: Tool)
	local self = ServerTool.new(tool, WalkieTalkie)
	self.Owner = self:GetPlayer()
	if self.Owner then WalkieTalkieService:Reconcile(self.Owner) end
	return self
end

function WalkieTalkie:OnEquipped()
	self.Owner = self:GetPlayer()
	if self.Owner then WalkieTalkieService:Reconcile(self.Owner) end
end

function WalkieTalkie:OnUnequipped()
	if self.Owner then WalkieTalkieService:Reconcile(self.Owner) end
end

function WalkieTalkie:OnDestroy()
	local owner = self.Owner
	self.Owner = nil
	if owner then task.defer(WalkieTalkieService.Reconcile, WalkieTalkieService, owner) end
end

return WalkieTalkie
