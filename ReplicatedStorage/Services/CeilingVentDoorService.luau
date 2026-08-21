local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local CeilingVentDoorService = {}

if not RunService:IsClient() or not FLAGS.Enemies then
	return CeilingVentDoorService
end

local doorEvent = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("CeilingVentDoor") :: RemoteEvent

local activeTweens: { [BasePart]: Tween } = {}

doorEvent.OnClientEvent:Connect(function(door: unknown, target: CFrame, duration: number, easing: string?)
	if typeof(door) ~= "Instance" or not door:IsA("BasePart") or not door:IsDescendantOf(workspace) then
		return
	end

	local previous = activeTweens[door]
	if previous then
		previous:Cancel()
	end

	local style = if easing == "Bounce" then Enum.EasingStyle.Bounce else Enum.EasingStyle.Quad
	local value = Instance.new("CFrameValue")
	value.Value = door:GetPivot()
	local changed = value:GetPropertyChangedSignal("Value"):Connect(function()
		if door.Parent then
			door:PivotTo(value.Value)
		end
	end)

	local tween = TweenService:Create(
		value,
		TweenInfo.new(duration, style, Enum.EasingDirection.Out),
		{ Value = target }
	)
	activeTweens[door] = tween
	tween.Completed:Once(function(playbackState: Enum.PlaybackState)
		changed:Disconnect()
		value:Destroy()
		if activeTweens[door] == tween then
			activeTweens[door] = nil
		end
		if playbackState == Enum.PlaybackState.Completed and door.Parent then
			door:PivotTo(target)
		end
	end)
	tween:Play()
end)

return CeilingVentDoorService
