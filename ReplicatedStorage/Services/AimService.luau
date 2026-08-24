local Aim = {}

function Aim.Toward(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, target).Rotation
end

function Aim.Ease(rotation: CFrame, goal: CFrame, rate: number, deltaTime: number): CFrame
	return rotation:Lerp(goal, 1 - math.exp(-rate * deltaTime))
end

return Aim
