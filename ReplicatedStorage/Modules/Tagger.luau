local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Classes = ReplicatedStorage.Classes
local Ball = require(Classes.Ball)
local Hole = require(Classes.Hole)
local Shovel = require(Classes.Shovel)

-- Client-side class-to-instance wiring. Tools listen globally (nil ancestor) because they move
-- between a player's Backpack and their Character; world objects are scoped to workspace.
return function()
	TagService:Listen("Ball", function(o) return Ball.new(o) end, function(_, o) o:Destroy() end)
	TagService:Listen("Shovel", function(o) return Shovel.new(o) end, function(_, o) o:Destroy() end)

	TagService:Listen("Hole", function(o) return Hole.new(o) end, function(_, o)
		o:Destroy()
	end, workspace)
end
