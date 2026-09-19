local HttpService = game:GetService("HttpService")
local Root = game:GetService("ReplicatedStorage").Profiler
local Settings = require(Root.Config.Settings)
local Report = require(Root.Core.Report)
local Store = {}
Store.__index = Store

function Store.new(folder)
	return setmetatable({ reports = {}, order = {}, folder = folder }, Store)
end

function Store:Put(report)
	local summary = Report.Format(report)
	local json = HttpService:JSONEncode(report)
	if not self.reports[report.id] then table.insert(self.order, report.id) end
	self.reports[report.id] = report
	while #self.order > Settings.MaxReports do
		local id = table.remove(self.order, 1)
		self.reports[id] = nil
		local old = self.folder:FindFirstChild(id)
		if old then old:Destroy() end
	end
	local folder = self.folder:FindFirstChild(report.id) or Instance.new("Folder")
	folder.Name = report.id; folder.Parent = self.folder
	folder:ClearAllChildren()
	local text = Instance.new("StringValue")
	text.Name = "Summary"; text.Value = summary; text.Parent = folder
	folder:SetAttribute("JsonBytes", #json)
	folder:SetAttribute("Chunks", math.ceil(#json/Settings.ChunkBytes))
	for offset = 1, #json, Settings.ChunkBytes do
		local chunk = Instance.new("StringValue")
		chunk.Name = string.format("Json%04d", math.floor((offset-1)/Settings.ChunkBytes)+1)
		chunk.Value = string.sub(json,offset,offset+Settings.ChunkBytes-1); chunk.Parent = folder
	end
	return report.id
end

function Store:Import(json)
	assert(type(json) == "string" and #json <= Settings.MaxImportBytes, "Import is too large")
	local report = HttpService:JSONDecode(json)
	assert(type(report) == "table" and report.schema == 1 and type(report.trials) == "table" and #report.trials <= 10, "Invalid report")
	assert(type(report.options) == "table" and type(report.scenario) == "table" and type(report.warnings) == "table", "Invalid report fields")
	local original = report.id
	report.id = "import-" .. HttpService:GenerateGUID(false)
	report.importedFrom = original
	self:Put(report)
	return report.id
end

return Store
