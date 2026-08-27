local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PhotoConfig = require(ReplicatedStorage.Configs.PhotoConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)
local PhotoCameraService = require(ServerStorage.Services.PhotoCameraService)

local PhotoCommandService = {}

local function place(player: Player): Model?
	local root = CharacterService.GetAliveRoot(player)
	if not root then return nil end

	local forward = root.CFrame.LookVector
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude < 1e-3 then return nil end
	flat = flat.Unit

	local ahead = root.Position + flat * 8

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local ground = workspace:Raycast(ahead + Vector3.new(0, 5, 0), Vector3.new(0, -30, 0), params)
	if not ground then return nil end

	local body = ground.Position + Vector3.new(0, PhotoConfig.Place.BodyHeight, 0)
	return PhotoCameraService:Place(player, CFrame.lookAt(body, body + flat))
end

local function run(player: Player, argument: string?)
	local command = (argument or ""):lower():match("%S+")

	if command == "figure" then
		local state = argument and argument:match("%S+%s+(.+)")
		if state then
			local lowered = state:lower()
			if lowered == "on" then
				PhotoCameraService.ForceFigure = true
			elseif lowered == "off" then
				PhotoCameraService.ForceFigure = false
			else
				local enemies = ReplicatedStorage:FindFirstChild("Enemies")
				local rig = nil
				for _, child in (enemies and enemies:GetChildren() or {}) do
					if child.Name:lower() == lowered then
						rig = child
						break
					end
				end
				if not rig then
					warn(`[photo] no rig named "{state}" in ReplicatedStorage.Enemies`)
					return
				end
				PhotoCameraService.FigureName = rig.Name
				PhotoCameraService.ForceFigure = true
			end
		else
			PhotoCameraService.ForceFigure = not PhotoCameraService.ForceFigure
		end
		warn(`[photo] forced figure {if PhotoCameraService.ForceFigure then "on" else "off"}, rig "{PhotoCameraService.FigureName}"`)
		return
	end

	if command == "now" or command == "snap" then
		local taken = 0
		for _, model in PhotoCameraService:GetActive() do
			if not model:GetAttribute(PhotoConfig.Attributes.Snapped) then
				PhotoCameraService:Snap(model)
				taken += 1
			end
		end
		warn(`[photo] snapped {taken} camera(s)`)
		return
	end

	if command == nil or command == "place" then
		local model = place(player)
		warn(if model then `[photo] placed a camera in front of {player.Name}` else "[photo] no floor in front of you to stand it on")
		return
	end

	warn("[photo] use /photo, /photo now, or /photo figure [on|off|<rig name>]")
end

ChatCommandService.Register("photo", {
	Handler = run,
})

return PhotoCommandService
