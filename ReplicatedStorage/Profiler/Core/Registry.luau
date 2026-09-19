local Registry = {}
Registry.__index = Registry

-- Packs return plain scenario definitions. Requiring a pack must not start game
-- services or mutate a scene. Resolve game dependencies only in Prepare.
function Registry.new(folder)
	local self = setmetatable({ items = {}, errors = {} }, Registry)
	local modules = folder:GetDescendants()
	table.sort(modules, function(a,b) return a:GetFullName() < b:GetFullName() end)
	for _, module in modules do
		if not module:IsA("ModuleScript") then continue end
		local ok, definitions = pcall(require, module)
		if not ok then table.insert(self.errors, module.Name .. ": " .. tostring(definitions)); continue end
		if type(definitions) ~= "table" or not definitions.Scenarios then continue end
		for _, definition in definitions.Scenarios do
			assert(type(definition.Id) == "string" and not self.items[definition.Id], "Duplicate/invalid scenario ID")
			self.items[definition.Id] = definition
		end
	end
	return self
end

function Registry:List()
	local rows = {}
	for id, item in self.items do
		table.insert(rows, { id = id, name = item.Name, version = item.Version,
			description = item.Description, focus = item.Focus, controlled = item.Controlled == true,
			phases = item.Phases, diagnosticOnly = item.DiagnosticOnly == true })
	end
	table.sort(rows, function(a,b) return a.id < b.id end)
	return rows
end

return Registry
