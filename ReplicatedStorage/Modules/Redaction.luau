--- Blanks out part of a description, and does it the same way every time.
---
--- An entry in the index is not learned all at once: a player who has glimpsed a Chaser twice knows
--- less about it than one who has been killed by it, and the description is where that difference is
--- shown. This turns a progress value into a partly-redacted version of the text.
---
--- Two properties matter, and everything here exists to hold them:
---
--- * **Stable.** The same text and seed always hide the same words. A player who reads an entry,
---   closes the index and opens it again must see the identical half-sentence -- text that reshuffles
---   itself reads as noise rather than as knowledge, and there would be nothing to point at when more
---   of it arrives.
--- * **Monotonic.** A word visible at one progress is visible at every progress above it. Words are
---   revealed in a fixed order, so learning more can only ever add. Rolling per word per call would
---   satisfy neither.
---
--- The order is a seeded shuffle of the word positions, so which words go first is arbitrary but
--- fixed. Arbitrary is the point: revealing left to right would read as a sentence being typed out,
--- where a scatter reads as a page that has been damaged and is being pieced back together.
---
--- Progress is spent on *characters* rather than on words. Counting words made a description's
--- twelve one-word steps mean twelve different things depending on how long those words were: half
--- a paragraph of short words looked far less than half revealed, and a gain that landed on "a"
--- bought visibly less than the same gain landing on "corridors". Weighting each word by its own
--- length makes the fraction of the paragraph a player can read equal to the fraction they have
--- earned, which is what the number was supposed to mean.

local Redaction = {}

--- What a hidden word is drawn as. Full-block rather than an underscore run so the redaction reads
--- as something covering the text rather than as a blank to be filled in.
local BLOCK = utf8.char(0x2588)

--- Blocks drawn per character of the word they cover. A full block is about an em wide where an
--- average letter is a little over half of one, so a nine-letter word covered by nine blocks is drawn
--- close to twice its real width. That is not just ugly: the description sits in a `TextScaled` label,
--- so the widest line decides the size of every line, and a word turning from blocks into letters used
--- to shrink the paragraph and shuffle the whole thing around mid-reveal. Drawing about half as many
--- blocks as the word has letters keeps covered and uncovered roughly the same width, so uncovering a
--- word leaves the rest of the text where it was.
local BLOCK_RATIO = 0.55

--- Cached per text-and-seed pair. The order never changes for a given entry, so it is worked out on
--- the first draw of that entry and never again -- repainting the index is otherwise a shuffle per
--- card per refresh.
local OrderCache: { [string]: { number } } = {}
local WordCache: { [string]: { string } } = {}
local WeightCache: { [string]: { Weights: { number }, Total: number } } = {}

--- A stable integer for a string, so an entry id can seed a shuffle without a hand-kept table of
--- numbers. FNV-1a, truncated to stay inside the range `Random.new` takes.
local function hashString(text: string): number
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 16777619) % 4294967296
	end
	return hash % 2147483647
end

--- Splits on whitespace, keeping punctuation attached to the word it belongs to. A redacted word
--- covers its own full stop, which is what stops the shape of the sentence leaking through the gaps.
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

--- What each word of `text` costs, and what the whole of it costs. A word is worth its own length in
--- characters plus the space that follows it, so the cost of a word is the width it takes up on the
--- page -- which is what makes "half discovered" mean half the paragraph rather than half its words.
--- Counted in codepoints so an accented character costs one rather than two.
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

--- The order the words of `text` are revealed in, as positions into `Redaction.Words`. A seeded
--- Fisher-Yates over the positions: deterministic for a given seed, and a permutation rather than a
--- roll per word, so every word is revealed exactly once and none is revealed twice.
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

--- Which word positions are visible at `progress`, as a set.
---
--- Words are bought in reveal order out of a budget of `progress` of the description's total width,
--- so a player at 0.4 can read about four tenths of the paragraph regardless of how its words happen
--- to be sized. A word is taken once the budget reaches the middle of what it costs rather than the
--- whole of it -- rounding to the nearest word rather than down, so the visible share tracks the
--- number instead of trailing half a word behind it forever.
---
--- Progress above zero always reveals at least one word. The first scrap of knowledge about an enemy
--- should show up as something rather than as an unchanged wall of blocks; whether the entry is worth
--- opening at all is what progress zero says, and that is the index's own question rather than this
--- one's. Progress 1 is the only value that reveals the last word.
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
	-- The running total is a prefix sum over a fixed order, so this is a prefix of the reveal order
	-- and can only grow as `progress` does -- which is the monotonicity the whole module rests on.
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
	--- Wrap the output in `<font>` tags, for a label with `RichText` on. Without it the blocks are the
	--- same colour as the text, which is legible but flat.
	Rich: boolean?,
	HiddenColor: Color3?,
	--- Per-word colour overrides, keyed by word position. A position listed here is drawn in that
	--- colour whether it came out as a word or as a run of blocks, which is what lets the reveal
	--- animation light a word's blocks up before they break and cool the word down afterwards without
	--- this module knowing anything about either.
	Colors: { [number]: Color3 }?,
	--- Words at these positions are drawn as blocks even where `progress` would have shown them, which
	--- is how the reveal animation holds a word back for its own moment.
	Suppress: { [number]: boolean }?,
	--- Blocks drawn per character covered. Defaults to `BLOCK_RATIO`; see the note there for why it is
	--- not one.
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

--- RichText is markup, so a description carrying an ampersand or an angle bracket would otherwise be
--- read as a tag and swallow the rest of the paragraph. Only the words actually drawn need it; a run
--- of blocks can never contain anything to escape.
local function escape(word: string): string
	return (word:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

--- One word's worth of blocks. Counted in codepoints rather than bytes so a description with an
--- accent in it is not covered by twice as many blocks as it has letters.
local function blocksFor(word: string, ratio: number): string
	local length = utf8.len(word) or #word
	return string.rep(BLOCK, math.max(math.round(length * ratio), 1))
end

--- The description as it should read at `progress`: the visible words as written, everything else
--- covered.
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
			-- An override beats the hidden colour, so a word being charged up is lit rather than left
			-- sitting in the redaction grey. A visible word with no override is drawn in the label's own
			-- colour, which is what it should be once it has settled.
			local color = (colors and colors[index]) or (not shown and hidden or nil)
			if color then
				piece = '<font color="' .. toHex(color) .. '">' .. piece .. "</font>"
			end
		end

		pieces[index] = piece
	end

	return table.concat(pieces, " ")
end

--- The positions `after` shows that `before` did not. What the reveal animation walks through, and
--- empty whenever a gain was too small to uncover anything.
function Redaction.NewlyVisible(text: string, seed: string, before: number, after: number): { number }
	local was = Redaction.VisibleSet(text, seed, before)
	local now = Redaction.VisibleSet(text, seed, after)

	local gained = {}
	-- Walked in reveal order rather than in word order, so the animation uncovers them in the order
	-- they were earned rather than left to right across the label.
	for _, position in Redaction.Order(text, seed) do
		if now[position] and not was[position] then
			table.insert(gained, position)
		end
	end
	return gained
end

return Redaction
