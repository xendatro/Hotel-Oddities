local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Classes = ReplicatedStorage.Classes
local Hole = require(Classes.Hole)

-- Client-side class-to-instance wiring for WORLD objects. Tools are not listed here: they register
-- themselves from `ToolConfigs` through `ToolClientService`.
return function()
	task.defer(function()
		TagService:Listen("Hole", function(o) return Hole.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
	end)
end
