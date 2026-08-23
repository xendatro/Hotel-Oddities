local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = ReplicatedStorage:WaitForChild("Animations")

local Animation = {}
Animation.__index = Animation

function Animation.new(rig: Model)
	local self = setmetatable({}, Animation)
	self.Track = nil :: AnimationTrack?

	local name = rig:GetAttribute("Animation")
	local animation = if type(name) == "string" then Animations:FindFirstChild(name) else nil
	if not animation or not animation:IsA("Animation") then
		warn(`Animation: {rig:GetFullName()} has no animation named {tostring(name)}`)
		return self
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play()
	self.Track = track

	return self
end

function Animation:Destroy()
	if not self.Track then return end

	self.Track:Stop()
	self.Track:Destroy()
	self.Track = nil
end

return Animation
