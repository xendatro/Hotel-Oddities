-- Freezes and resumes the ending cutscene clock so a shot can be screenshotted.
-- Call through Bridge: { module = "EndingShots", fn = "PauseAt", args = { 12.5 } }.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EndingCutsceneService = require(ReplicatedStorage.Services.EndingCutsceneService)

local EndingShots = {}

function EndingShots.Time(): number?
	return EndingCutsceneService:GetTime()
end

function EndingShots.Rate(rate: number): number?
	EndingCutsceneService:SetRate(rate)
	return EndingCutsceneService:GetTime()
end

-- Waits for the track to reach `time`, then holds it there. Returns the held time,
-- or nil when no cutscene is running or the timeout passed.
function EndingShots.PauseAt(time: number, timeout: number?): number?
	local deadline = os.clock() + (timeout or 60)
	while os.clock() < deadline do
		local now = EndingCutsceneService:GetTime()
		if not now then return nil end
		if now >= time then
			EndingCutsceneService:SetRate(0)
			return EndingCutsceneService:GetTime()
		end
		task.wait()
	end
	return nil
end

return EndingShots
