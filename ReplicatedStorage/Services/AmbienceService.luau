local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Configs.AmbienceConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local DeathScreenService = require(ReplicatedStorage.Services.DeathScreenService)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local LobbyService = require(ReplicatedStorage.Services.LobbyService)

local AmbienceService = {}
local Suppressors: { [string]: true } = {}

function AmbienceService:Suppress(key: string, suppressed: boolean)
	Suppressors[key] = if suppressed then true else nil
end

if not RunService:IsClient() then
	return AmbienceService
end

local AMBIENCE_FOLDER = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Ambience")
local ENEMY_TAG = "Enemy"
local DEATH_AMBIENCE = "DeathAmbience"
local AMBIENCE_BUS = "Ambience"
local DEATH_FADE_TIME = 1

local Duck = Instance.new("AudioFader")
Duck.Name = "AmbienceDuck"
Duck.Parent = workspace:WaitForChild("Sounds")

local AmbienceMixer = Instance.new("AudioChannelMixer")
AmbienceMixer.Name = "AmbienceMixer"
AmbienceMixer.Layout = Enum.AudioChannelLayout.Stereo
AmbienceMixer.Parent = workspace.Sounds
AudioService:Wire(Duck, AmbienceMixer)
AudioService:Wire(AmbienceMixer, AudioService:GetOutput())

local sources = {}
for _, child in AMBIENCE_FOLDER:GetChildren() do
	if child:IsA("AudioPlayer") then
		table.insert(sources, child)
	end
end

local playing: AudioPlayer?
local deathPlaying: Sound?
local deathBaseVolume = 1
local sourceIndex = 0
local volumeMultiplier = 1
local accumulator = math.huge
local poiActive = false
local poiEffect: {
	Root: Folder,
	Fader: AudioFader,
	DryFader: AudioFader,
	Shifter: AudioPitchShifter,
	Distortion: AudioDistortion,
	Tremolo: AudioTremolo,
}?

local function getNextSource(): AudioPlayer?
	if #sources == 0 then return nil end

	local nextIndex = sourceIndex + 1
	if nextIndex > #sources then
		nextIndex = 1
	end
	sourceIndex = nextIndex
	return sources[sourceIndex]
end

local function createPOIEffect(): {
	Root: Folder,
	Fader: AudioFader,
	DryFader: AudioFader,
	Shifter: AudioPitchShifter,
	Distortion: AudioDistortion,
	Tremolo: AudioTremolo,
}
	local root = Instance.new("Folder")
	root.Name = "AmbiencePOIEffect"
	root.Parent = workspace.Sounds

	local dryFader = Instance.new("AudioFader")
	dryFader.Name = "POIDryFader"
	dryFader.Volume = 1
	dryFader.Parent = root

	local shifter = Instance.new("AudioPitchShifter")
	shifter.Name = "POIPitch"
	shifter.Pitch = AmbienceConfig.POI.Pitch
	shifter.Parent = root

	local distortion = Instance.new("AudioDistortion")
	distortion.Name = "POIDistortion"
	distortion.Level = AmbienceConfig.POI.DistortionLevel
	distortion.Parent = root

	local tremolo = Instance.new("AudioTremolo")
	tremolo.Name = "POITremolo"
	tremolo.Depth = AmbienceConfig.POI.TremoloDepth
	tremolo.Frequency = AmbienceConfig.POI.TremoloFrequency
	tremolo.Parent = root

	local fader = Instance.new("AudioFader")
	fader.Name = "POIFader"
	fader.Volume = 0
	fader.Parent = root

	return { Root = root, Fader = fader, DryFader = dryFader, Shifter = shifter, Distortion = distortion, Tremolo = tremolo }
end

local function connectPOIEffect(effect, player: AudioPlayer)
	AudioService:Wire(player, effect.Shifter)
	AudioService:Wire(effect.Shifter, effect.Distortion)
	AudioService:Wire(effect.Distortion, effect.Tremolo)
	AudioService:Wire(effect.Tremolo, effect.Fader)
	AudioService:Wire(effect.Fader, AmbienceMixer)

	poiEffect = effect
	player.Destroying:Once(function()
		if poiEffect == effect then
			poiEffect = nil
		end
		if effect.Root.Parent then effect.Root:Destroy() end
	end)
end

local function playNext()
	if playing or DeathScreenService:IsVisible() or LobbyService:IsPlayerOnLobbyFloor() then return end

	local source = getNextSource()
	if not source then return end

	local effect = createPOIEffect()
	local player = AudioService:Play2D(source, false, AMBIENCE_BUS, nil, effect.DryFader)
	playing = player
	AudioService:Wire(effect.DryFader, Duck)
	connectPOIEffect(effect, player)

	player.Ended:Connect(function()
		if playing == player then
			playing = nil
			playNext()
		end
	end)
end

local function stopNormalAmbience()
	if not playing then return end
	AudioService:StopSound(playing)
	playing = nil
end

local function startDeathAmbience()
	if deathPlaying then return end
	deathPlaying = AudioService:Play2DSound(DEATH_AMBIENCE, true, AMBIENCE_BUS) :: Sound
	deathBaseVolume = deathPlaying.Volume
end

local function stopDeathAmbience()
	if not deathPlaying then return end
	AudioService:StopSound(deathPlaying)
	deathPlaying = nil
	deathBaseVolume = 1
end

local function updateDeathAmbience()
	if not deathPlaying then return end

	local timeUntilEnd = DeathScreenService:GetTimeUntilEnd()
	local volumeMultiplier = if timeUntilEnd
		then math.clamp(timeUntilEnd / DEATH_FADE_TIME, 0, 1)
		else 1
	deathPlaying.Volume = deathBaseVolume * volumeMultiplier
end

local function getNearestEnemyDistance(position: Vector3): number
	local nearest = math.huge
	for _, enemy in CollectionService:GetTagged(ENEMY_TAG) do
		if enemy:IsA("Model") and enemy:IsDescendantOf(workspace) then
			local distance = HallwayGraph:GetWalkingDistance(position, enemy:GetPivot().Position)
			nearest = math.min(nearest, distance)
		end
	end
	return nearest
end

local function updatePlayback(deathVisible: boolean, lobbyVisible: boolean)
	if deathVisible then
		startDeathAmbience()
	else
		stopDeathAmbience()
	end

	if deathVisible or lobbyVisible then
		stopNormalAmbience()
	elseif not playing then
		playNext()
	end
end

local function updateVolume(deltaTime: number, ambienceBlocked: boolean)
	local root = CharacterService.GetAliveRoot(Players.LocalPlayer)
	local nearestDistance = if root then getNearestEnemyDistance(root.Position) else math.huge
	local targetMultiplier = if ambienceBlocked
		then 0
		else math.clamp(
			(nearestDistance - AmbienceConfig.SilentDistance)
				/ (AmbienceConfig.FullVolumeDistance - AmbienceConfig.SilentDistance),
			0,
			1
		)

	local fadeTime = math.max(AmbienceConfig.FadeTime, 0.01)
	local alpha = math.clamp(deltaTime / fadeTime, 0, 1)
	volumeMultiplier += (targetMultiplier - volumeMultiplier) * alpha
	Duck.Volume = volumeMultiplier
end

local function updatePOIFader(deltaTime: number)
	if poiEffect then
		local poiVolume = math.max(AmbienceConfig.POI.Volume, 0)
		local poiTarget = if poiActive then poiVolume else 0
		local poiFadeTime = math.max(AmbienceConfig.POI.FadeTime, 0.01)
		local poiAlpha = math.clamp(deltaTime / poiFadeTime, 0, 1)
		poiEffect.Fader.Volume += (poiTarget - poiEffect.Fader.Volume) * poiAlpha
		local alteredWeight = if poiVolume > 0 then math.clamp(poiEffect.Fader.Volume / poiVolume, 0, 1) else 0
		poiEffect.DryFader.Volume = 1 - alteredWeight
	end
end

function AmbienceService:SetPOIActive(active: boolean)
	poiActive = active
end

RunService.Heartbeat:Connect(function(deltaTime)
	local deathVisible = DeathScreenService:IsVisible()
	local lobbyVisible = LobbyService:IsPlayerOnLobbyFloor()
	updatePlayback(deathVisible, lobbyVisible)
	updateDeathAmbience()
	updatePOIFader(deltaTime)

	accumulator += deltaTime
	if accumulator < AmbienceConfig.UpdateInterval then return end

	local elapsed = accumulator
	accumulator = 0
	updateVolume(elapsed, deathVisible or lobbyVisible or next(Suppressors) ~= nil)
end)

updatePlayback(DeathScreenService:IsVisible(), LobbyService:IsPlayerOnLobbyFloor())

return AmbienceService
