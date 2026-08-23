local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Classes = ReplicatedStorage.Classes
local Hole = require(Classes.Hole)
local Spin = require(Classes.Spin)
local Watch = require(Classes.Watch)
local Breathe = require(Classes.Breathe)

return function()
	task.defer(function()
		TagService:Listen("Hole", function(o) return Hole.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
		TagService:Listen("Spin", function(o) return Spin.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
		TagService:Listen("Watch", function(o) return Watch.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
		TagService:Listen("Breathe", function(o) return Breathe.new(o) end, function(_, o)
			if o then o:Destroy() end
		end, workspace)
	end)
end
