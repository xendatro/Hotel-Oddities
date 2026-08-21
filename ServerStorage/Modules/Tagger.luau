local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Classes = ServerStorage.Classes
local TrapObject = require(Classes.TrapObject)
local Sound = require(Classes.Sound)

return function()
	task.defer(function()
		TagService:Listen("TrapObject", function(o) return TrapObject.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
		TagService:Listen("Sound", function(o) return Sound.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
	end)
end
