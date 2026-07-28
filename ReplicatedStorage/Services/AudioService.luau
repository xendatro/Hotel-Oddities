local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundsFolder = workspace:WaitForChild("Sounds")

local AudioService = {}

--[[
Plays a 2D sound (non-spatial) by cloning a Sound object from this ModuleScript's children.

Parameters:
- name (string): The name of the Sound instance under this ModuleScript.
- looped (boolean): Whether the sound should loop.
- soundGroup (string): Name of a SoundGroup in workspace.Sounds to assign the sound to.
- settings (table, optional): A dictionary of properties to assign to the sound instance (like Volume, PlaybackSpeed, TimePosition, etc.).

Returns:
- Sound: The playing Sound instance (for further manipulation).
]]
function AudioService:Play2DSound(name: string, looped: boolean, soundGroup: string, settings: {[string]: any}?)
	local sourceSound = ReplicatedStorage:WaitForChild("Sounds"):FindFirstChild(name)
	if not sourceSound or not sourceSound:IsA("Sound") then
		warn(`Sound "{name}" not found as child of AudioService.`)
		return
	end

	local newAudio = sourceSound:Clone()
	newAudio.Looped = looped
	newAudio.Parent = SoundsFolder:FindFirstChild(soundGroup)


	local group = SoundsFolder:FindFirstChild(soundGroup)
	if group and group:IsA("SoundGroup") then
		newAudio.SoundGroup = group
	else
		warn(`SoundGroup "{soundGroup}" not found in SoundsFolder.`)
	end

	-- Apply optional settings
	if settings then
		for prop, value in pairs(settings) do
			pcall(function()
				newAudio[prop] = value
			end)
		end
	end

	newAudio:Play()
	newAudio.Ended:Connect(function()
		newAudio:Destroy()
	end)

	return newAudio
end

--[[
Plays a 3D spatial sound at the given BasePart by cloning a Sound from ReplicatedStorage.Sounds.

Parameters:
- name (string): The name of the Sound instance under this ModuleScript.
- parent (BasePart): The part where the sound will play.
- looped (boolean): Whether the sound should loop.
- soundGroup (string): Name of a SoundGroup in workspace.Sounds to assign the sound to.
- settings (table, optional): A dictionary of properties to assign to the sound instance.

Returns:
- Sound: The playing Sound instance.
]]
function AudioService:Play3DSound(name: string, parent: BasePart, looped: boolean, soundGroup: string, settings: {[string]: any}?)
	local sourceSound = ReplicatedStorage:WaitForChild("Sounds"):FindFirstChild(name)
	if not sourceSound or not sourceSound:IsA("Sound") then
		warn(`Sound "{name}" not found as child of AudioService.`)
		return
	end

	local newAudio = Instance.new("Sound")
	newAudio.Name = name
	newAudio.SoundId = sourceSound.SoundId
	newAudio.Looped = looped
	newAudio.Parent = parent

	local group = SoundsFolder:FindFirstChild(soundGroup)
	if group and group:IsA("SoundGroup") then
		newAudio.SoundGroup = group
	else
		warn(`SoundGroup "{soundGroup}" not found in SoundsFolder.`)
	end

	-- Apply optional settings
	if settings then
		for prop, value in pairs(settings) do
			pcall(function()
				newAudio[prop] = value
			end)
		end
	end

	newAudio:Play()
	newAudio.Ended:Connect(function()
		newAudio:Destroy()
	end)

	return newAudio
end

--[[
Changes the volume of a SoundGroup in workspace.Sounds.

Parameters:
- soundGroupName (string): Name of the SoundGroup.
- newVolume (number): New volume value to assign.
]]
function AudioService:AdjustSoundGroup(soundGroupName: string, newVolume: number)
	local soundGroup = SoundsFolder:FindFirstChild(soundGroupName)
	if soundGroup and soundGroup:IsA("SoundGroup") then
		soundGroup.Volume = newVolume
	else
		warn(`SoundGroup "{soundGroupName}" not found in SoundsFolder.`)
	end
end

return AudioService
