--- Shared Creep presentation tuning. The server reads `LightRange` to extinguish the world, while
--- each client derives its own backdrop placement from the same value.
return {
	LightRange = 64,
	BackdropDistanceScale = 0.5,
	BackdropSize = Vector3.new(100, 100, 1),
}
