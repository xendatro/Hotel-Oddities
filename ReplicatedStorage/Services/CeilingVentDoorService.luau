local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local CeilingVentDoorService = {}

if not RunService:IsClient() or not FLAGS.Enemies then
	return CeilingVentDoorService
end

local doorEvent = CommunicationService.Get("Enemies", "CeilingVentDoor") :: RemoteEvent

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
	local tween = TweenProxyService.Proxy(
		"CFrameValue",
		door:GetPivot(),
		target,
		TweenInfo.new(duration, style, Enum.EasingDirection.Out),
		function(value)
			if door.Parent then
				door:PivotTo(value)
			end
		end
	)
	activeTweens[door] = tween
	tween.Completed:Once(function()
		if activeTweens[door] == tween then
			activeTweens[door] = nil
		end
	end)
	tween:Play()
end)

return CeilingVentDoorService
