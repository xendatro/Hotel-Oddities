local Settings = require(script.Parent.Parent.Config.Settings)
local Scene = {}
local methods = {
	render = { "GetTriangleCompositionAsync" },
	memory = { "GetScriptMemoryAsync", "GetUnparentedInstancesAsync", "GetAnimationMemoryAsync", "GetAudioMemoryAsync", "GetInstanceCompositionAsync" },
	server = { "GetInstanceCompositionAsync" },
}

-- Snapshot after scoring. Keep leaf paths and original units; never add children
-- to parent totals. Referenced/unparented objects alone do not prove a memory leak.
local function summarize(tree)
	local leaves = {}
	local visited = 0
	local function walk(node, path)
		if type(node) ~= "table" or visited > 50000 then return end
		visited += 1
		local name = tostring(node.Name or "unknown")
		path = if path == "" then name else path .. "/" .. name
		if type(node.Children) == "table" and #node.Children > 0 then
			for _, child in node.Children do walk(child, path) end
		else
			table.insert(leaves, { path = path, size = node.Size, sizes = node.Sizes })
		end
	end
	walk(tree, "")
	table.sort(leaves, function(a,b)
		return (a.size or (a.sizes and (a.sizes.Drawcalls or a.sizes.Triangles)) or 0)
			> (b.size or (b.sizes and (b.sizes.Drawcalls or b.sizes.Triangles)) or 0)
	end)
	local count = #leaves
	while #leaves > Settings.TopEntries do table.remove(leaves) end
	return { total = tree.Size, totals = tree.Sizes, top = leaves, leafCount = count, scanTruncated = visited > 50000 }
end

function Scene.Capture(focus)
	local result = { available = false, queries = {} }
	local ok, service = pcall(game.GetService, game, "SceneAnalysisService")
	if not ok then result.reason = tostring(service); return result end
	local seen = {}
	for group, names in methods do
		if focus ~= "all" and focus ~= group then continue end
		for _, name in names do
			if seen[name] then continue end
			seen[name] = true
			local success, data = pcall(function() return summarize(service[name](service)) end)
			result.queries[name] = if success then data else { unavailable = tostring(data) }
			if success then result.available = true end
		end
	end
	return result
end

return Scene
