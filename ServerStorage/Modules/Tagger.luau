local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Classes = ServerStorage.Classes
local Bandage = require(Classes.Bandage)
local Medkit = require(Classes.Medkit)
local SpellBook = require(Classes.SpellBook)
local Trap = require(Classes.Trap)
local TrapObject = require(Classes.TrapObject)

-- Server-side class-to-instance wiring. Tools listen globally (nil ancestor) because they move
-- between a player's Backpack and their Character; world objects are scoped to workspace.
return function()
	TagService:Listen("Bandage", function(o) return Bandage.new(o) end, function(_, o) o:Destroy() end)
	TagService:Listen("Medkit", function(o) return Medkit.new(o) end, function(_, o) o:Destroy() end)
	TagService:Listen("SpellBook", function(o) return SpellBook.new(o) end, function(_, o) o:Destroy() end)
	TagService:Listen("Trap", function(o) return Trap.new(o) end, function(_, o) o:Destroy() end)

	TagService:Listen("TrapObject", function(o) return TrapObject.new(o) end, function(_, o)
		o:Destroy()
	end, workspace)
end
