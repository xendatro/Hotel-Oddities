local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LookConfig = require(ReplicatedStorage.Configs.LookConfig)

--- Server half of look replication. Clients report where their own camera is aimed; this clamps
--- the numbers and stamps them onto the character as `LookPitch`/`LookYaw` attributes, which is
--- all the replication the feature needs -- every client renders the tilt locally from those.
---
--- It also runs the Mimic bridge: a mimic that is mirroring somebody advertises them through its
--- `LookMirrorUserId` attribute, and this copies that player's pitch onto the mimic's model on the
--- same attribute channel, so the copy tilts its head with the person it is copying. Yaw stays
--- zero on the mimic -- its whole body already faces its target, the way a first-person player's
--- does.
local LookService = {}

local PITCH_ATTRIBUTE = "LookPitch"
local YAW_ATTRIBUTE = "LookYaw"
local MIRROR_ATTRIBUTE = "LookMirrorUserId"

-- The channel is created here rather than authored, like the other runtime remotes.
local communication = ReplicatedStorage:FindFirstChild("Communication")
if not communication then
	communication = Instance.new("Folder")
	communication.Name = "Communication"
	communication.Parent = ReplicatedStorage
end

local folder = communication:FindFirstChild("Look")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Look"
	folder.Parent = communication
end

local Update = folder:FindFirstChild("Update") :: RemoteEvent?
if not Update then
	Update = Instance.new("RemoteEvent")
	Update.Name = "Update"
	Update.Parent = folder
end

-- Reports faster than the client is supposed to send are dropped, not queued.
local lastReportAt: { [Player]: number } = {}

Update.OnServerEvent:Connect(function(player: Player, pitch: any, yaw: any)
	if type(pitch) ~= "number" or type(yaw) ~= "number" then return end
	if pitch ~= pitch or yaw ~= yaw then return end -- NaN

	local now = os.clock()
	if now - (lastReportAt[player] or 0) < LookConfig.SendInterval * 0.5 then return end
	lastReportAt[player] = now

	local character = player.Character
	if not character then return end

	character:SetAttribute(PITCH_ATTRIBUTE, math.clamp(pitch, -LookConfig.MaxPitch, LookConfig.MaxPitch))
	character:SetAttribute(YAW_ATTRIBUTE, math.clamp(yaw, -LookConfig.MaxYaw, LookConfig.MaxYaw))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastReportAt[player] = nil
end)

--- The Mimic bridge --------------------------------------------------------------------------------

local nextMimicUpdate = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextMimicUpdate then return end
	nextMimicUpdate = now + LookConfig.MimicUpdateInterval

	for _, model in CollectionService:GetTagged("Enemy") do
		local userId = model:GetAttribute(MIRROR_ATTRIBUTE)
		if type(userId) ~= "number" then
			-- Done mirroring: settle the tilt back to level rather than freezing mid-glance.
			if model:GetAttribute(PITCH_ATTRIBUTE) then
				model:SetAttribute(PITCH_ATTRIBUTE, 0)
				model:SetAttribute(YAW_ATTRIBUTE, 0)
			end
			continue
		end

		local target = Players:GetPlayerByUserId(userId)
		local character = target and target.Character
		local pitch = character and character:GetAttribute(PITCH_ATTRIBUTE)
		model:SetAttribute(PITCH_ATTRIBUTE, if type(pitch) == "number" then pitch else 0)
		model:SetAttribute(YAW_ATTRIBUTE, 0)
	end
end)

return LookService
