local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local CONTENT_CLASSES = {
	"MeshPart", "SpecialMesh", "Decal", "Texture",
	"ImageLabel", "ImageButton", "Sound", "Animation",
	"ParticleEmitter", "Beam", "Trail", "Shirt", "Pants", "SurfaceAppearance",
}

local BATCH_SIZE = 64

local function carriesContent(instance: Instance): boolean
	for _, className in CONTENT_CLASSES do
		if instance:IsA(className) then return true end
	end
	return false
end

task.spawn(function()
	local started = os.clock()
	local queue: { any } = {}
	local total = 0

	local function flush()
		if #queue == 0 then return end
		local batch = queue
		queue = {}
		total += #batch
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
	end

	local function enqueue(item: any)
		table.insert(queue, item)
		if #queue >= BATCH_SIZE then
			flush()
		end
	end

	local configs = ReplicatedStorage:WaitForChild("Configs")
	local ok, effectsConfig = pcall(require, configs:WaitForChild("EffectsHUDConfig"))
	if ok then
		for _, id in effectsConfig.Icons do
			if id ~= "" then enqueue(id) end
		end
	end

	local okAnimations, animationConfig = pcall(require, configs:WaitForChild("AnimationConfig"))
	if okAnimations then
		for _, id in animationConfig.Animations do
			enqueue(`rbxassetid://{id}`)
		end
	end

	for _, root in { ReplicatedStorage, workspace, StarterGui, SoundService, Lighting } do
		for _, instance in root:GetDescendants() do
			if carriesContent(instance) then
				enqueue(instance)
			end
		end
	end
	flush()

	print(`[Preload] warmed {total} assets in {math.floor((os.clock() - started) * 10) / 10}s`)
end)
