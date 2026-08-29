local CaptureService = game:GetService("CaptureService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CaptureGalleryService = {}

if not RunService:IsClient() then
	return CaptureGalleryService
end

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)

export type Media = {
	Id: string,
	Kind: string,
	Capture: any?,
	ContentId: string?,
	Time: DateTime,
	Saved: boolean,
}

local permission: boolean? = nil
local prompting = false
local recording = false
local pending: { [string]: Media } = {}
local cache: { Media } = {}
local cachedAt = 0

CaptureGalleryService.Changed = Instance.new("BindableEvent")

local function announce()
	CaptureGalleryService.Changed:Fire()
end

local function keyOf(capture: any): string
	local ok, localId = pcall(function() return capture.LocalId end)
	if ok and type(localId) == "string" and localId ~= "" then return localId end
	return `capture-{os.clock()}-{math.random(1, 1000000)}`
end

local function timeOf(capture: any): DateTime
	local ok, value = pcall(function() return capture.CaptureTime end)
	if ok and typeof(value) == "DateTime" then return value end
	return DateTime.now()
end

local function kindOf(capture: any): string
	local ok, value = pcall(function() return capture.CaptureType end)
	if ok and value == Enum.CaptureType.Video then return "Video" end
	return "Screenshot"
end

local function isThisUniverse(capture: any): boolean
	if not CaptureConfig.Gallery.ThisUniverseOnly then return true end

	local ok, universeId = pcall(function() return capture.SourceUniverseId end)
	if not ok or type(universeId) ~= "number" or universeId == 0 then return true end
	return universeId == game.GameId
end

local function wrap(capture: any, saved: boolean): Media
	return {
		Id = keyOf(capture),
		Kind = kindOf(capture),
		Capture = capture,
		ContentId = nil,
		Time = timeOf(capture),
		Saved = saved,
	}
end

local function reasonFor(result: any): string
	if result == Enum.VideoCaptureStartedResult.NoSpaceOnDevice
		or result == Enum.ScreenshotCaptureResult.NoSpaceOnDevice then
		return CaptureConfig.Text.NoSpace
	end
	if result == Enum.VideoCaptureStartedResult.NoDeviceSupport
		or result == Enum.ScreenshotCaptureResult.NoDeviceSupport then
		return CaptureConfig.Text.NoDeviceSupport
	end
	if result == Enum.VideoCaptureStartedResult.CapturingAlready then
		return CaptureConfig.Text.AlreadyRecording
	end
	return CaptureConfig.Text.Unsupported
end

function CaptureGalleryService:HasPermission(): boolean
	return permission == true
end

function CaptureGalleryService:RequestPermission(): boolean
	if permission == true then return true end
	if prompting then return false end

	prompting = true
	local ok, granted = pcall(function()
		return CaptureService:PromptCaptureGalleryPermissionAsync(CaptureConfig.Permission)
	end)
	prompting = false

	permission = ok and granted == true
	if permission then
		announce()
	end
	return permission :: boolean
end

function CaptureGalleryService:WaitForPermission(): boolean
	local deadline = os.clock() + CaptureConfig.Screenshot.Timeout
	while prompting and os.clock() < deadline do
		task.wait(0.1)
	end
	return self:RequestPermission()
end

function CaptureGalleryService:EnsurePermission()
	if permission == true or prompting then return end

	task.spawn(function()
		self:RequestPermission()
	end)
end

function CaptureGalleryService:Content(media: Media): Content?
	if media.Capture then
		local ok, content = pcall(Content.fromObject, media.Capture)
		if ok then return content end
	end
	if media.ContentId then
		return Content.fromUri(media.ContentId)
	end
	return nil
end

function CaptureGalleryService:_TakeLegacyScreenshot(): Media?
	local contentId: string? = nil
	local done = false

	local ok = pcall(function()
		CaptureService:CaptureScreenshot(function(id: string)
			contentId = id
			done = true
		end)
	end)
	if not ok then return nil end

	local deadline = os.clock() + CaptureConfig.Screenshot.Timeout
	while not done and os.clock() < deadline do
		task.wait(0.03)
	end
	if not contentId then return nil end

	local media: Media = {
		Id = contentId :: string,
		Kind = "Screenshot",
		Capture = nil,
		ContentId = contentId,
		Time = DateTime.now(),
		Saved = false,
	}
	pending[media.Id] = media
	return media
end

function CaptureGalleryService:TakeScreenshot(): (Media?, string?)
	local done, result, capture = false, nil, nil

	local ok = pcall(function()
		CaptureService:TakeScreenshotCaptureAsync(function(captureResult, screenshot)
			result, capture, done = captureResult, screenshot, true
		end, { UICaptureMode = Enum.UICaptureMode.None })
	end)

	if ok then
		local deadline = os.clock() + CaptureConfig.Screenshot.Timeout
		while not done and os.clock() < deadline do
			task.wait(0.03)
		end
	end

	if capture and result == Enum.ScreenshotCaptureResult.Success then
		local media = wrap(capture, false)
		pending[media.Id] = media
		return media, nil
	end

	local fallback = self:_TakeLegacyScreenshot()
	if not fallback then return nil, reasonFor(result) end

	return fallback, CaptureConfig.Text.CaptureFailed .. " - " .. reasonFor(result)
end

function CaptureGalleryService:IsRecording(): boolean
	return recording
end

function CaptureGalleryService:StartVideo(onFinished: (Media?, string?) -> ()): boolean
	if recording then
		onFinished(nil, CaptureConfig.Text.AlreadyRecording)
		return false
	end

	self:EnsurePermission()

	local settled = false
	local function finish(media: Media?, message: string?)
		if settled then return end
		settled = true
		recording = false
		onFinished(media, message)
	end

	recording = true

	local ok, started = pcall(function()
		return CaptureService:StartVideoCaptureAsync(function(result, videoCapture)
			if result ~= Enum.VideoCaptureResult.Success or not videoCapture then
				finish(nil, CaptureConfig.Text.Unsupported)
				return
			end

			local media = wrap(videoCapture, false)
			pending[media.Id] = media
			finish(media, nil)
		end, nil)
	end)

	if not ok or started ~= Enum.VideoCaptureStartedResult.Success then
		finish(nil, reasonFor(started))
		return false
	end

	task.delay(CaptureConfig.Video.MaxDuration + CaptureConfig.Video.ReadyTimeout, function()
		finish(nil, CaptureConfig.Text.Unsupported)
	end)

	return true
end

function CaptureGalleryService:StopVideo()
	if not recording then return end
	pcall(function()
		CaptureService:StopVideoCapture()
	end)
end

function CaptureGalleryService:Save(media: Media): boolean
	if not media.Capture then return false end
	if not self:WaitForPermission() then return false end

	local done, saved = false, false
	local ok = pcall(function()
		CaptureService:PromptSaveCapturesToGallery({ media.Capture }, function(results)
			if type(results) == "table" then
				for _, value in results do
					if value == true then saved = true end
				end
			end
			done = true
		end)
	end)
	if not ok then return false end

	local deadline = os.clock() + CaptureConfig.Screenshot.Timeout
	while not done and os.clock() < deadline do
		task.wait(0.05)
	end

	if saved then
		media.Saved = true
		pending[media.Id] = nil
		cachedAt = 0
		announce()
	end
	return saved
end

function CaptureGalleryService:Discard(media: Media)
	pending[media.Id] = nil
	announce()
end

function CaptureGalleryService:Refresh(force: boolean?): boolean
	if not force and os.clock() - cachedAt < CaptureConfig.Gallery.RefreshCooldown then
		return true
	end
	if not self:WaitForPermission() then return false end

	local ok, result, pages = pcall(function()
		return CaptureService:ReadCapturesFromGalleryAsync({}, false)
	end)
	if not ok or result ~= Enum.ReadCapturesFromGalleryResult.Success or not pages then
		return false
	end

	local found: { Media } = {}
	local limit = CaptureConfig.Gallery.MaxItems

	while true do
		local pageOk, items = pcall(function() return pages:GetCurrentPage() end)
		if not pageOk or type(items) ~= "table" then break end

		for _, capture in items do
			if isThisUniverse(capture) then
				table.insert(found, wrap(capture, true))
				if #found >= limit then break end
			end
		end

		if #found >= limit or pages.IsFinished then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
	end

	cache = found
	cachedAt = os.clock()
	announce()
	return true
end

function CaptureGalleryService:List(): { Media }
	local items: { Media } = {}
	for _, media in pending do
		table.insert(items, media)
	end
	for _, media in cache do
		table.insert(items, media)
	end

	table.sort(items, function(a: Media, b: Media)
		return a.Time.UnixTimestampMillis > b.Time.UnixTimestampMillis
	end)
	return items
end

return CaptureGalleryService
