local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local InterfaceHideService = {}

if not RunService:IsClient() then
	return InterfaceHideService
end

local CORE_TYPES = {}
for _, coreType in Enum.CoreGuiType:GetEnumItems() do
	if coreType ~= Enum.CoreGuiType.All then
		table.insert(CORE_TYPES, coreType)
	end
end

local player = Players.LocalPlayer
local activeCaptures = 0
local hiddenCore: { [Enum.CoreGuiType]: true } = {}

export type Options = {
	Exclude: { LayerCollector }?,
	HideNew: boolean?,
}

type HiddenGui = { Gui: LayerCollector, Parent: Instance, Enabled: boolean, Detached: boolean }

local function isExcluded(gui: Instance, exclude: { LayerCollector }): boolean
	for _, excluded in exclude do
		if gui == excluded or gui:IsDescendantOf(excluded) then
			return true
		end
	end
	return false
end

function InterfaceHideService.Capture(options: Options?): (() -> (), () -> ())
	local exclude: { LayerCollector } = options and options.Exclude or {}
	local hidden: { HiddenGui } = {}
	local captured: { [LayerCollector]: HiddenGui } = {}
	local restored = false

	local function hide(gui: LayerCollector)
		local entry: HiddenGui = { Gui = gui, Parent = gui.Parent :: Instance, Enabled = gui.Enabled, Detached = false }
		table.insert(hidden, entry)
		captured[gui] = entry
		gui.Enabled = false
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, gui in playerGui:GetDescendants() do
			if gui:IsA("LayerCollector") and gui.Parent and not isExcluded(gui, exclude) then
				hide(gui)
			end
		end
	end

	for _, coreType in CORE_TYPES do
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, coreType)
		if ok and enabled then
			hiddenCore[coreType] = true
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, false)
		end
	end
	pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)
	activeCaptures += 1

	local added: RBXScriptConnection? = nil
	if options and options.HideNew and playerGui then
		added = playerGui.DescendantAdded:Connect(function(gui: Instance)
			if restored or not gui:IsA("LayerCollector") or not gui.Parent or isExcluded(gui, exclude) then return end

			local entry = captured[gui]
			if not entry then
				hide(gui)
			elseif entry.Detached then
				entry.Parent = gui.Parent :: Instance
				entry.Detached = false
			end
		end)
	end

	local function hold()
		if restored then return end
		for _, entry in hidden do
			if entry.Detached or not entry.Gui.Parent then continue end
			if entry.Gui.Enabled then
				entry.Gui.Enabled = false
				entry.Gui.Parent = nil
				entry.Detached = true
			end
		end
	end

	return hold, function()
		if restored then return end
		restored = true
		if added then
			added:Disconnect()
		end

		for _, entry in hidden do
			local reenabled = not entry.Detached and entry.Gui.Parent ~= nil and entry.Gui.Enabled
			if entry.Detached and entry.Parent.Parent then
				local reattached = pcall(function()
					entry.Gui.Parent = entry.Parent
				end)
				entry.Detached = not reattached
			end
			if entry.Gui.Parent and not reenabled then
				entry.Gui.Enabled = entry.Enabled
			end
		end

		activeCaptures -= 1
		if activeCaptures == 0 then
			for coreType in hiddenCore do
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, true)
			end
			table.clear(hiddenCore)
			pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", true)
		end
	end
end

return InterfaceHideService
