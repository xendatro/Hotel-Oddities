local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeConfig = require(ReplicatedStorage.Configs.BadgeConfig)

local BadgeIconService = {}

local Icons: { [number]: string } = {}
local Waiting: { [number]: { (string) -> () } } = {}

local function fetch(badgeId: number): string
	for attempt = 1, BadgeConfig.Icon.Retries do
		local ok, info = pcall(BadgeService.GetBadgeInfoAsync, BadgeService, badgeId)
		if ok and type(info) == "table" and type(info.IconImageId) == "number" and info.IconImageId > 0 then
			return "rbxassetid://" .. info.IconImageId
		end
		if attempt < BadgeConfig.Icon.Retries then
			task.wait(BadgeConfig.Icon.RetryDelay * attempt)
		end
	end
	return ""
end

local function resolve(badgeId: number)
	local icon = fetch(badgeId)
	local callbacks = Waiting[badgeId]
	Waiting[badgeId] = nil
	if icon ~= "" then
		Icons[badgeId] = icon
	end
	for _, callback in callbacks or {} do
		task.spawn(callback, icon)
	end
end

local function valid(badgeId: any): boolean
	return type(badgeId) == "number" and badgeId > 0
end

function BadgeIconService:Peek(badgeId: number?): string?
	if not valid(badgeId) then return "" end
	return Icons[badgeId :: number]
end

function BadgeIconService:Fetch(badgeId: number?, callback: (string) -> ())
	if not valid(badgeId) then
		callback("")
		return
	end
	local id = badgeId :: number
	local cached = Icons[id]
	if cached then
		callback(cached)
		return
	end
	local callbacks = Waiting[id]
	if callbacks then
		table.insert(callbacks, callback)
		return
	end
	Waiting[id] = { callback }
	task.spawn(resolve, id)
end

function BadgeIconService:Get(badgeId: number?): string
	if not valid(badgeId) then return "" end
	local id = badgeId :: number
	local cached = Icons[id]
	if cached then return cached end
	local thread = coroutine.running()
	BadgeIconService:Fetch(id, function(icon)
		task.spawn(thread, icon)
	end)
	return coroutine.yield()
end

function BadgeIconService:Prefetch(ids: { number })
	task.spawn(function()
		for _, id in ids do
			if valid(id) and not Icons[id] and not Waiting[id] then
				BadgeIconService:Fetch(id, function() end)
				task.wait(BadgeConfig.Icon.PrefetchGap)
			end
		end
	end)
end

return BadgeIconService
