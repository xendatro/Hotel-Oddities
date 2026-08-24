local Players = game:GetService("Players")

local GuiBuilderService = {}

function GuiBuilderService.GetPlayerGui(): PlayerGui
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

function GuiBuilderService.CreateScreenGui(name: string, displayOrder: number?, ignoreGuiInset: boolean?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if displayOrder then
		gui.DisplayOrder = displayOrder
	end
	if ignoreGuiInset then
		gui.IgnoreGuiInset = true
	end
	gui.Parent = GuiBuilderService.GetPlayerGui()
	return gui
end

function GuiBuilderService.Corner(parent: GuiObject, radius: UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

function GuiBuilderService.Stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

return GuiBuilderService
