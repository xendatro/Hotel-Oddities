local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Classes = ServerStorage.Classes
local TrapObject = require(Classes.TrapObject)

-- Server-side class-to-instance wiring for WORLD objects. Tools are not listed here: they register
-- themselves from `ToolConfigs` through `ToolService`, so adding one never means editing this file.
return function()
	task.defer(function()
		TagService:Listen("TrapObject", function(o) return TrapObject.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
	end)
end
