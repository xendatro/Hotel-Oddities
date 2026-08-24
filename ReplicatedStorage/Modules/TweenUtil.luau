local TweenService = game:GetService("TweenService")

local TweenUtil = {}

function TweenUtil.CancelAll(tweens: { Tween })
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
end

function TweenUtil.Proxy(className: string, initialValue: any, goalValue: any, tweenInfo: TweenInfo, apply: (value: any) -> ()): Tween
	local proxy = Instance.new(className)
	proxy.Value = initialValue
	local connection = proxy.Changed:Connect(function(value)
		apply(value)
	end)
	local tween = TweenService:Create(proxy, tweenInfo, { Value = goalValue })
	tween.Completed:Once(function(playbackState)
		connection:Disconnect()
		if playbackState == Enum.PlaybackState.Completed then
			apply(goalValue)
		end
		proxy:Destroy()
	end)
	return tween
end

function TweenUtil.ScaleModel(model: Model, from: number, to: number, tweenInfo: TweenInfo): Tween
	return TweenUtil.Proxy("NumberValue", from, to, tweenInfo, function(value)
		if model.Parent then
			model:ScaleTo(value)
		end
	end)
end

return TweenUtil
