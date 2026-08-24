local Redaction = {}

local BLOCK = utf8.char(0x2588)

local BLOCK_RATIO = 0.55

local OrderCache: { [string]: { number } } = {}
local WordCache: { [string]: { string } } = {}
local WeightCache: { [string]: { Weights: { number }, Total: number } } = {}

local function hashString(text: string): number
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 16777619) % 4294967296
	end
	return hash % 2147483647
end

function Redaction.Words(text: string): { string }
	local cached = WordCache[text]
	if cached then return cached end

	local words = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(words, word)
	end

	WordCache[text] = words
	return words
end

function Redaction.WordCount(text: string): number
	return #Redaction.Words(text)
end

function Redaction.Weights(text: string): ({ number }, number)
	local cached = WeightCache[text]
	if cached then return cached.Weights, cached.Total end

	local weights = {}
	local total = 0
	for index, word in Redaction.Words(text) do
		local weight = (utf8.len(word) or #word) + 1
		weights[index] = weight
		total += weight
	end

	WeightCache[text] = { Weights = weights, Total = total }
	return weights, total
end

function Redaction.Order(text: string, seed: string): { number }
	local key = seed .. "\0" .. text
	local cached = OrderCache[key]
	if cached then return cached end

	local order = {}
	for index = 1, #Redaction.Words(text) do
		order[index] = index
	end

	local random = Random.new(hashString(key))
	for index = #order, 2, -1 do
		local swap = random:NextInteger(1, index)
		order[index], order[swap] = order[swap], order[index]
	end

	OrderCache[key] = order
	return order
end

function Redaction.VisibleSet(text: string, seed: string, progress: number): { [number]: boolean }
	local visible = {}
	local weights, total = Redaction.Weights(text)
	if total == 0 then return visible end

	local clamped = math.clamp(progress, 0, 1)
	local order = Redaction.Order(text, seed)

	if clamped >= 1 then
		for index in weights do
			visible[index] = true
		end
		return visible
	end

	local budget = clamped * total
	local spent = 0
	local count = 0
	for _, position in order do
		local weight = weights[position]
		if spent + weight * 0.5 > budget then break end
		visible[position] = true
		spent += weight
		count += 1
	end

	if count == 0 and clamped > 0 then
		visible[order[1]] = true
	end
	return visible
end

export type RenderOptions = {
	Rich: boolean?,
	HiddenColor: Color3?,
	Colors: { [number]: Color3 }?,
	Suppress: { [number]: boolean }?,
	BlockRatio: number?,
}

local function toHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local function escape(word: string): string
	return (word:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function blocksFor(word: string, ratio: number): string
	local length = utf8.len(word) or #word
	return string.rep(BLOCK, math.max(math.round(length * ratio), 1))
end

function Redaction.Render(text: string, seed: string, progress: number, options: RenderOptions?): string
	local settings = options or {}
	local words = Redaction.Words(text)
	if #words == 0 then return text end

	local visible = Redaction.VisibleSet(text, seed, progress)
	local suppress = settings.Suppress
	local colors = settings.Colors
	local rich = settings.Rich == true
	local ratio = settings.BlockRatio or BLOCK_RATIO
	local hidden = settings.HiddenColor or Color3.fromRGB(70, 66, 78)

	local pieces = {}
	for index, word in words do
		local shown = visible[index] and not (suppress and suppress[index])
		local piece = if shown then (rich and escape(word) or word) else blocksFor(word, ratio)

		if rich then
			local color = (colors and colors[index]) or (not shown and hidden or nil)
			if color then
				piece = '<font color="' .. toHex(color) .. '">' .. piece .. "</font>"
			end
		end

		pieces[index] = piece
	end

	return table.concat(pieces, " ")
end

function Redaction.NewlyVisible(text: string, seed: string, before: number, after: number): { number }
	local was = Redaction.VisibleSet(text, seed, before)
	local now = Redaction.VisibleSet(text, seed, after)

	local gained = {}
	for _, position in Redaction.Order(text, seed) do
		if now[position] and not was[position] then
			table.insert(gained, position)
		end
	end
	return gained
end

return Redaction
