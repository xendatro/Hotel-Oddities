local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local VfxConfig = require(ReplicatedStorage.Configs.VfxConfig)
local VfxEffect = require(ReplicatedStorage.Classes.VfxEffect)

local VfxService = {}

if RunService:IsServer() then
	local remote = CommunicationService.Ensure(VfxConfig.Remote.Folder, VfxConfig.Remote.Name)

	function VfxService:Play(name: string, cframe: CFrame, options: VfxEffect.Options?)
		remote:FireAllClients(name, cframe, options)
	end

	return VfxService
end

local warned: { [string]: boolean } = {}
local holderFolder: Folder? = nil

local function getHolderFolder(): Folder
	if holderFolder and holderFolder.Parent then return holderFolder end
	local folder = Instance.new("Folder")
	folder.Name = VfxConfig.HolderFolder
	folder.Parent = workspace
	holderFolder = folder
	return folder
end

function VfxService:FindTemplate(name: string): BasePart?
	local effects = ReplicatedStorage:FindFirstChild(VfxConfig.Folder)
	local template = effects and effects:FindFirstChild(name)
	if template and template:IsA("BasePart") then return template end
	if not warned[name] then
		warned[name] = true
		warn(`VfxService: ReplicatedStorage.{VfxConfig.Folder}.{name} is missing or is not a part`)
	end
	return nil
end

function VfxService:IsInRange(position: Vector3, maxDistance: number?): boolean
	local camera = workspace.CurrentCamera
	if not camera then return false end
	return (camera.CFrame.Position - position).Magnitude <= (maxDistance or VfxConfig.MaxDistance)
end

function VfxService:Create(name: string, cframe: CFrame, options: VfxEffect.Options?): VfxEffect.VfxEffect?
	local template = self:FindTemplate(name)
	if not template then return nil end
	return VfxEffect.new(template, cframe, getHolderFolder(), options)
end

function VfxService:Play(name: string, cframe: CFrame, options: VfxEffect.Options?): VfxEffect.VfxEffect?
	local template = self:FindTemplate(name)
	if not template then return nil end
	local maxDistance = template:GetAttribute("MaxDistance")
	if not self:IsInRange(cframe.Position, if type(maxDistance) == "number" then maxDistance else nil) then
		return nil
	end
	return VfxEffect.new(template, cframe, getHolderFolder(), options)
end

local remote = CommunicationService.Get(VfxConfig.Remote.Folder, VfxConfig.Remote.Name)
remote.OnClientEvent:Connect(function(name: any, cframe: any, options: any)
	if type(name) ~= "string" or typeof(cframe) ~= "CFrame" then return end
	VfxService:Play(name, cframe, if type(options) == "table" then options else nil)
end)

return VfxService
