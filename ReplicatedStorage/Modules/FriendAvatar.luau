local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--- Builds a rig wearing one of the local player's friends' avatars, entirely on this client.
---
--- Every enemy that borrows a face wants the same three things -- the friend list, a
--- `HumanoidDescription` for one of them, and a model built from it -- and each of those is a web
--- call worth making once. Everything here is cached for the session: the friend list once, a
--- description per user, and a built prototype per user that later calls clone rather than rebuild.
---
--- Which friend gets used is memoized per `key`, so an enemy that has its rig rebuilt -- because a
--- card was repainted, or the same enemy is being shown in two places at once -- keeps wearing the
--- same face. Two different keys are rolled independently and may land on the same friend.
---
--- A player with no friends, or a lookup Roblox refuses, falls back to the local player's own
--- avatar; if even that fails the caller gets nil and is expected to have something else to show.
--- Note `GhostRenderService` still carries its own copy of this logic, written before this module
--- existed -- it is the same behaviour and could be pointed here once a ghost can be spawned to
--- test the change against.
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

--- Yields until the friend list has come back, then hands it over. Empty is a real answer -- a
--- player with no friends, or a lookup that failed -- and is not retried.
function FriendAvatar.GetUserIds(): { number }
	while UserIds == nil do
		task.wait()
	end
	return UserIds :: { number }
end

--- The friend `key` wears, rolled on first use and kept for the session. Falls back to the local
--- player, who is always available and is a face the player will recognise just as fast.
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

	-- The local player's own description is already in the world and does not need fetching, which
	-- also makes the no-friends fallback instant.
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

--- Studs below the map a rig is assembled at. Far enough under the hotel that the two frames it
--- spends there cannot be seen from inside it, and nothing down there to land on.
local ASSEMBLY_DEPTH = -5000

--- Lets the engine put the rig together, then takes it back out of the world.
---
--- `CreateHumanoidModelFromDescriptionAsync` returns before its rig is assembled: the body parts are
--- still stacked where they were created, the `Motor6D`s that would pose them do not exist yet, and
--- the accessory handles are hundreds of studs out. All of that is finished by the engine, and only
--- once the model is somewhere the engine simulates -- which a `ViewportFrame` is not. Clone it any
--- earlier and what you get is whatever happened to be true that frame, which is why the same code
--- produced a good rig and a scattered one on consecutive runs.
---
--- So it goes into the world for two frames, far under the hotel, and comes out assembled. Two is
--- what it takes: joints are built on the frame the model lands, and the parts are moved onto them
--- on the next.
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

--- Puts every accessory onto the body part its weld says it belongs to.
---
--- `CreateHumanoidModelFromDescriptionAsync` returns the *body* already posed -- torso, limbs and
--- head all sit correctly relative to the root -- but the accessories do not: their handles are left
--- at whatever CFrame they were authored at, hundreds of studs out, and the `AccessoryWeld` that
--- would bring them in is only resolved once the engine's joint solver gets hold of the rig. A
--- `ViewportFrame` never runs that solver, so without this a headshot is a bare head surrounded by
--- hats orbiting the map.
---
--- Only handles are ever moved. Seeding the solve with every body part -- rather than with the root
--- alone -- is what guarantees that: the rig carries no `Motor6D`s at all, so a walk out from the
--- root would reach the head through an *accessory* weld and drag the head off to meet a floating
--- hat instead of the other way round. The sweep repeats because accessories can stack on accessories
--- and each pass can only place a handle whose other end is already placed.
---
--- Run after `assemble`, which normally leaves nothing to do -- this is the guard for the accessory
--- the engine did not get to. A handle with no weld to anything cannot be placed at all and is
--- destroyed rather than left to drift through the shot.
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

--- A fresh R15 rig wearing `key`'s friend, or nil if Roblox would not build one. Comes back
--- assembled and standing, so it can be dropped straight into a `ViewportFrame`. The caller owns
--- what it gets and should destroy it; the prototype it was cloned from is kept here.
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
		-- Comes back out of the world assembled, and is kept here only to be cloned from.
		assemble(prototype)
		seatAccessories(prototype)

		Prototypes[userId] = prototype
	end

	return prototype:Clone()
end

return FriendAvatar
