local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local WalkieTalkieService = require(ReplicatedStorage.Services.WalkieTalkieService)

local WalkieTalkie = ClientTool.extend("WalkieTalkie")

function WalkieTalkie.new(tool: Tool)
	return ClientTool.new(tool, WalkieTalkie)
end

function WalkieTalkie:OnEquipped()
	WalkieTalkieService:SetEnabled(true, self.Tool)
end

function WalkieTalkie:OnUnequipped()
	WalkieTalkieService:SetEnabled(false)
end

function WalkieTalkie:OnDestroy()
	WalkieTalkieService:SetEnabled(false)
end

return WalkieTalkie
