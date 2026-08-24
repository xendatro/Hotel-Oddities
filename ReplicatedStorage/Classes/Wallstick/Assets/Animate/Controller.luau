--!strict

local CharacterAnimate = require(script.Parent:WaitForChild("CharacterAnimate"))

local animate = script.Parent
local character = animate.Parent
local performer = character:WaitForChild("Humanoid")

local module = {}
local controller

function module.matchAnimate(director: Humanoid)
	if controller then
		controller.cleanup()
	end

	controller = CharacterAnimate.animate(animate, director, performer)
end

local playEmote = animate:FindFirstChild("PlayEmote") :: BindableFunction?
if not playEmote then
	playEmote = Instance.new("BindableFunction")
	local created = playEmote :: BindableFunction
	created.Name = "PlayEmote"
	created.Parent = animate
end

(playEmote :: BindableFunction).OnInvoke = function(emote)
	return controller.playEmote(emote)
end

module.matchAnimate(performer)

return module
