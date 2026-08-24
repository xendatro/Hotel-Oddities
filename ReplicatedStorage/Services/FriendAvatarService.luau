local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FriendAvatar = {}

if not RunService:IsClient() then
	return FriendAvatar
end

local LocalPlayer = Players.LocalPlayer

local UserIds: { number }? = nil
local Descriptions: { [number]: HumanoidDescription } = {}
local Prototypes: { [number]: Model } = {}
local Chosen: { [string]: number } = {}

local function loadUserIds(): { number }
	local success, pages = pcall(Players.GetFriendsAsync, Players, LocalPlayer.UserId)
	if not success then return {} end

	local userIds = {}
	while true do
		local pageSuccess, page = pcall(pages.GetCurrentPage, pages)
		if not pageSuccess then break end

		for _, friend in page do
			table.insert(userIds, friend.Id)
		end

		if pages.IsFinished then break end
		if not pcall(pages.AdvanceToNextPageAsync, pages) then break end
	end

	return userIds
end

task.spawn(function()
	UserIds = loadUserIds()
end)

function FriendAvatar.GetUserIds(): { number }
	while UserIds == nil do
		task.wait()
	end
	return UserIds :: { number }
end

function FriendAvatar.PickUserId(key: string): number
	local existing = Chosen[key]
	if existing then return existing end

	local userIds = FriendAvatar.GetUserIds()
	local userId = if #userIds > 0 then userIds[math.random(#userIds)] else LocalPlayer.UserId

	Chosen[key] = userId
	return userId
end

function FriendAvatar.GetDescription(userId: number): HumanoidDescription?
	local cached = Descriptions[userId]
	if cached then return cached end

	if userId == LocalPlayer.UserId then
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if humanoid then
			local success, description = pcall(humanoid.GetAppliedDescription, humanoid)
			if success then
				Descriptions[userId] = description
				return description
			end
		end
	end

	local success, description = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, userId)
	if not success then return nil end

	Descriptions[userId] = description
	return description
end

local ASSEMBLY_DEPTH = -5000

local function assemble(model: Model)
	local staging = Instance.new("Folder")
	staging.Name = "FriendAvatarStaging"
	staging.Parent = workspace

	model:PivotTo(CFrame.new(0, ASSEMBLY_DEPTH, 0))
	model.Parent = staging

	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()

	model.Parent = nil
	staging:Destroy()
end

local function seatAccessories(model: Model)
	local seated: { [BasePart]: boolean } = {}
	local handles: { BasePart } = {}

	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end

		if descendant:FindFirstAncestorOfClass("Accessory") then
			table.insert(handles, descendant)
		else
			seated[descendant] = true
		end
	end

	local joints: { JointInstance } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("JointInstance") then
			table.insert(joints, descendant)
		end
	end

	local moved = true
	while moved do
		moved = false
		for _, joint in joints do
			local part0, part1 = joint.Part0, joint.Part1
			if not part0 or not part1 then continue end

			if seated[part0] and not seated[part1] then
				part1.CFrame = part0.CFrame * joint.C0 * joint.C1:Inverse()
				seated[part1] = true
				moved = true
			elseif seated[part1] and not seated[part0] then
				part0.CFrame = part1.CFrame * joint.C1 * joint.C0:Inverse()
				seated[part0] = true
				moved = true
			end
		end
	end

	for _, handle in handles do
		if not seated[handle] then
			handle:Destroy()
		end
	end
end

function FriendAvatar.Build(key: string): Model?
	local userId = FriendAvatar.PickUserId(key)

	local prototype = Prototypes[userId]
	if not prototype then
		local description = FriendAvatar.GetDescription(userId)
		if not description and userId ~= LocalPlayer.UserId then
			description = FriendAvatar.GetDescription(LocalPlayer.UserId)
		end
		if not description then return nil end

		local success, result = pcall(
			Players.CreateHumanoidModelFromDescriptionAsync,
			Players,
			description,
			Enum.HumanoidRigType.R15,
			Enum.AssetTypeVerification.Always
		)
		if not success then return nil end

		prototype = result
		assemble(prototype)
		seatAccessories(prototype)

		Prototypes[userId] = prototype
	end

	return prototype:Clone()
end

return FriendAvatar
