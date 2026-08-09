--- Everything the enemy index reads: which enemies it lists, what it says about each one, and how
--- each one is framed inside a headshot viewport. Shared rather than server-side because the index
--- is drawn entirely on the client and `ServerStorage.Configs.EnemyConfigs` cannot be reached from
--- there -- so the ids are repeated here by hand rather than derived.
---
--- `Id` matches an `EnemyConfigs` key, which is the same id `EnemyService:Spawn` stamps onto every
--- enemy it puts in the world and the same id a death is reported under. Keeping them equal is what
--- lets discovery be recorded against "the thing that just killed you" without a translation table.
--- `Model` names the template under `ReplicatedStorage.Enemies`, exactly as `EnemyConfigs.Model`
--- does.
---
--- Descriptions are flavour rather than instruction: the death screen already owns telling a player
--- what they should have done, and repeating a hint here would make the index a place to read
--- strategy off rather than a record of what you have met. They are placeholders for now. They are
--- also drawn into a small `TextScaled` label, so two short sentences is about the ceiling before
--- the text shrinks past reading.
---
--- A description is also what discovery is spent on. Entries are not on or off: each carries a
--- progress from 0 to 1, and the words of its description are uncovered a few at a time as that
--- climbs -- so write them as a handful of independent observations rather than as one sentence
--- whose second half is meaningless without its first. Half of a description is a state a player
--- will spend real time looking at, and it should still say something.

--- One part of a stand-in. Built at the origin, in studs, and framed as a whole.
export type StandinPart = {
	Size: Vector3,
	Offset: Vector3?,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
}

export type Headshot = {
	Focus: string?, -- part the shot is centred on; defaults to `Head`, then the model's primary part
	Yaw: number?, -- degrees around the model, from straight-on; positive swings to its left
	Pitch: number?, -- degrees the camera sits above the focus and looks down by
	Zoom: number?, -- multiplier on the fitted distance; below 1 is closer in
	Offset: Vector3?, -- studs the aim point is nudged by, in the model's own space
	--- Transparency forced onto every part of the shot, for an enemy that is not solid in the world
	--- either. Never makes anything *more* opaque, so a rig's already-invisible root stays invisible.
	Transparency: number?,
	--- Rebuilds the shot on a rig wearing one of the local player's friends, replacing the authored
	--- model once the avatar has loaded. The friend is rolled once per entry and kept, so a card and
	--- the info panel always agree about whose face it is.
	WearFriendAvatar: boolean?,
	--- Drawn instead of the enemy's own model, for the enemies that do not have one to draw. Creep
	--- and Chaos are each a single fully transparent part carrying particle emitters, and a
	--- `ViewportFrame` renders no particles at all -- so cloning their template gives a blank card.
	--- These are placeholders built from the emitters' own colours and spacing: what a player
	--- actually sees of a Creep is two red points a couple of studs apart, and that is what this is.
	--- Swap in real art and delete the field.
	Standin: { StandinPart }?,
}

export type Entry = {
	Id: string,
	Name: string,
	Model: string,
	Description: string,
	Headshot: Headshot?,
}

return {
	--- Cards per page. The authored `UIGridLayout` is four cells across and the `Cards` frame is two
	--- rows tall, so anything other than 8 will either leave a hole or overflow the frame.
	EntriesPerPage = 8,

	--- Where `Entry.Model` is looked up. Named rather than hardcoded because `EnemyService` reads the
	--- same folder out of `ReplicatedStorage`, and the two should never drift apart.
	TemplateFolder = "Enemies",

	--- Progress every entry starts at for a player with nothing saved. Zero in the shipped game;
	--- raise it to see the partly-redacted states without having to earn them.
	StartProgress = 0,

	--- What an entry at zero progress looks like. Undiscovered entries keep their slot in the grid
	--- rather than being skipped: a gap where something will go is the point of a bestiary, and a
	--- list that reshuffles as it fills makes the pages meaningless.
	Locked = {
		Name = "UNDISCOVERED",
		CardName = "???",
		CardTextColor = Color3.fromRGB(202, 202, 202),
		Description = "You have not met this one yet.",
		ShowSilhouette = true, -- render the model anyway, tinted flat; false hides the viewport
		--- The headshot viewport, taken to black outright. `ImageColor3` multiplies the rendered shot,
		--- so anything above zero leaves the enemy's real colours showing through as a dim version of
		--- itself -- which reads as a badly-lit photograph of the thing rather than as a silhouette.
		--- Black is the whole point: an undiscovered entry gives away a shape and nothing else.
		Tint = Color3.fromRGB(0, 0, 0),
		--- The card itself -- the photograph it is all pinned to. Dimmed rather than blacked out,
		--- because this is the thing the player has to find and click on: a card as dark as its own
		--- viewport reads as a hole in the board rather than as an entry waiting to be filled. Grey
		--- rather than tinted, so the paper looks unlit instead of coloured.
		CardTint = Color3.fromRGB(108, 104, 118),
	},

	--- How knowing more about an enemy is shown.
	---
	--- Discovery is a fraction rather than a flag: an entry is somewhere between never having been
	--- seen and fully written up, and the description fills in as that number climbs. Which words go
	--- first is fixed per entry by `Modules.Redaction`, so an entry always reads the same way at the
	--- same progress and can only ever gain words -- see that module for why both of those matter.
	---
	--- What earns the progress is not here. That is the server's business and lives in
	--- `ServerStorage.Configs.DiscoveryConfig`; this file only decides how the result is drawn.
	Discovery = {
		--- Above this, an entry is discovered: its real name on the card, its portrait lit, and as much
		--- of its description as has been earned. At or below it the entry is drawn as `Locked` --
		--- UNDISCOVERED, no description, black viewport.
		---
		--- This is the *only* threshold the board draws. Brightness used to be walked up with progress,
		--- which made the grid a row of half-lit photographs whose dimness said nothing the description
		--- underneath was not already saying, and left an entry a player had genuinely met still
		--- looking like one they had not. Meeting something is a thing that either has or has not
		--- happened, so it is drawn as one.
		NamedAbove = 0,

		--- Colour of the blocks covering a word not yet learned. Close enough to the panel that it
		--- reads as damage to the page rather than as a second body of text.
		HiddenColor = Color3.fromRGB(64, 60, 72),

		--- Colour a word is drawn in for the beat after it arrives, before it cools to the body colour.
		--- Only ever seen during a reveal.
		NewColor = Color3.fromRGB(255, 236, 150),

		--- Blocks drawn per character of a covered word. Below one because a full block is far wider
		--- than an average letter, and the description is `TextScaled` -- see `Modules.Redaction` for
		--- the whole of why. Raise it towards 1 for a heavier redaction, at the cost of the paragraph
		--- visibly resizing as it fills.
		BlockRatio = 0.55,

		--- The animation played when a death has just taught the player something.
		---
		--- Each newly-earned word runs its own little sequence rather than the panel running one big
		--- one: its blocks brighten to `ChargeColor`, break into the word itself at the peak of that,
		--- and then cool from `NewColor` down to the body colour over `SettleTime`. Words are started
		--- `WordInterval` apart and are *not* waited on, so several are always somewhere in that
		--- sequence at once and the paragraph reads as a page coming back rather than as a queue being
		--- worked through one item at a time.
		Reveal = {
			--- Held after the death screen has finished and torn itself down, before the index is
			--- opened. Nothing is drawn during it -- the point is a clear beat of the world back, so
			--- the board arriving reads as a second thing happening rather than as part of the death.
			--- Without this the index opens under a screen that is still typing its hint and fading,
			--- and the two animations cover each other.
			AfterDeathDelay = 1,
			--- Ceiling on waiting for that screen, in case something leaves it up. The reveal is worth
			--- showing late; it is not worth never showing.
			DeathScreenTimeout = 20,

			OpenDelay = 0.8, -- beat after the index opens before the first word starts charging
			WordInterval = 0.19, -- between one word starting and the next

			--- How long a word's blocks spend brightening before they break into letters. This is the
			--- part that makes a word landing feel like something happening to the page rather than a
			--- character swap: the redaction lights up first, so the eye is already on it.
			ChargeTime = 0.16,
			ChargeColor = Color3.fromRGB(255, 255, 255),

			--- How long the word then takes to cool from `NewColor` to the body colour, and how much of
			--- that is spent dropping out of `ChargeColor` into `NewColor`. The flash is short and the
			--- cool is eased, so a word snaps to warm and then lingers there before letting go.
			SettleTime = 0.85,
			FlashFraction = 0.18,

			--- Held after the last word has finished cooling, before the panel is handed back to the
			--- ordinary paint. Long enough that the reveal has an end rather than just stopping.
			SettleDelay = 0.4,

			--- Cap on how long the words take to *start*. A death that fills a long description would
			--- otherwise hold the player in a menu for an unreasonable stretch; past this the interval
			--- is compressed to fit. Each word still gets its full charge and cool.
			MaxDuration = 4,
		},
	},

	--- Shown in the info panel when nothing is selected at all -- only reachable if every entry is
	--- hidden, which cannot happen while `HideUndiscovered` is false.
	Empty = {
		Name = "INDEX",
		Description = "Select an entry.",
	},

	--- Undiscovered entries are listed as locked placeholders by default. Set this to true instead to
	--- drop them from the index entirely, which also shortens the page count.
	HideUndiscovered = false,

	--- The page arrows have `AutoButtonColor` off, so a page arrow that would do nothing -- Prev on
	--- the first page, Next on the last, both when there is only one page -- is dimmed by hand.
	Pagination = {
		Enabled = Color3.fromRGB(255, 255, 255),
		Disabled = Color3.fromRGB(150, 148, 155),
	},

	--- How the board answers being used.
	---
	--- Every card now sits inside a holder frame of its own. The `UIGridLayout` lays out the holder
	--- and never the card, so a card is free to grow past its cell, lift out of it and tilt without
	--- the layout snapping it back on the next frame -- which it did, and which is why the holders
	--- exist. Scales and lifts below are fractions of that holder. The page arrows have the same
	--- arrangement for the same reason: they sit in a `UIListLayout`, which positions each of them
	--- from the other's size, so scaling one in place shoved the other along the row.
	---
	--- Nothing animates on its own. Every value here is a rest state and a time to reach it, so a
	--- board nobody is touching is doing no work at all.
	Animation = {
		Card = {
			HoverScale = 1.08,
			HoverLift = 0.05, -- fraction of the cell's height the card rises by
			HoverTilt = 2.5, -- degrees. These are photographs pinned to a board, not buttons.

			PressScale = 0.95,
			PressTilt = 0, -- a press squares the card up again, which reads as it being pushed flat

			-- A selected card holds a smaller version of the same pose, leaning the other way: enough
			-- to be found at a glance across the grid, not enough to compete with whatever is hovered.
			SelectedScale = 1.04,
			SelectedLift = 0.02,
			SelectedTilt = -1.5,

			HoverTime = 0.18,
			PressTime = 0.07,
			SettleTime = 0.26, -- coming back to rest, slower than going out to it

			Style = Enum.EasingStyle.Back, -- overshoots slightly, which is what makes it feel physical
			Direction = Enum.EasingDirection.Out,
			PressStyle = Enum.EasingStyle.Quad, -- no overshoot on the way down; a press should be flat
			PressDirection = Enum.EasingDirection.Out,
		},

		--- The page arrows and the close button, which are chrome rather than content and so move less.
		Button = {
			HoverScale = 1.15,
			PressScale = 0.9,
			DisabledScale = 0.92, -- an arrow with nowhere to go sits back as well as dim

			HoverTime = 0.14,
			PressTime = 0.06,
			SettleTime = 0.2,

			Style = Enum.EasingStyle.Back,
			Direction = Enum.EasingDirection.Out,
		},

		--- Cards arriving on a page, dealt out rather than appearing all at once.
		Page = {
			EnterScale = 0.86,
			EnterDrop = 0.06, -- starts this far under its resting place, as a fraction of the cell
			EnterTime = 0.34,
			Stagger = 0.035, -- seconds between one card starting and the next
			--- Run it again each time `IndexGui.Enabled` goes true. Nothing here opens or closes the
			--- window -- this only notices that it happened, so the board is dealt out rather than
			--- already sitting there whenever it is shown.
			ReplayOnOpen = true,
		},

		--- The info panel swapping from one entry to the next.
		Info = {
			FadeTime = 0.22,
			Rise = 0.02, -- fraction of the panel's height the text comes up from
		},
	},

	--- Defaults for every headshot camera; an entry overrides what it needs in its own `Headshot`.
	Headshot = {
		FieldOfView = 40, -- narrow, so the framing reads as a portrait lens rather than a fisheye
		--- Slack around the focus part's largest axis. A head is about 1.2 studs across and a hat or a
		--- mask is not, so the fitted distance is padded rather than measured tight.
		Padding = 1.7,
		Yaw = 0,
		Pitch = 6,
		Zoom = 1,
		Tint = Color3.fromRGB(255, 255, 255), -- what a discovered entry's viewport is tinted with
	},

	--- Authored order, which is also grid order: pursuit enemies first, then the ambient ones. Twelve
	--- entries at eight a page is two pages, the second of them half empty -- adding a thirteenth is
	--- free, a ninth was not.
	Entries = {
		{
			Id = "Chaser",
			Name = "Chaser",
			Model = "Chaser",
			Description = "Something that used to work here. It still walks the halls it was hired to keep.",
		},
		{
			Id = "CeilingDweller",
			Name = "Ceiling Dweller",
			Model = "Ceiling Dweller",
			Description = "It lives above the tiles and comes down wherever the vents let it.",
		},
		{
			Id = "Blind",
			Name = "Blind",
			Model = "Blind",
			Description = "Eyeless, and listening. The hotel is as quiet as it is because of this one.",
		},
		{
			Id = "WeepingAngel",
			Name = "Weeping Angel",
			Model = "Weeping Angel",
			Description = "Stone, every time anyone checks. Nobody has ever watched one take a step.",
			-- Its head is a 2x1x1 block rather than a normal one, so the fit runs wide off the X axis
			-- and pulls the camera back further than the face needs.
			Headshot = { Zoom = 0.82 },
		},
		{
			Id = "Mimic",
			Name = "Mimic",
			Model = "Mimic",
			Description = "It wears a guest's face badly. Watch it long enough and the seams show.",
			-- In the world it takes the face of another player in the server, which the index has no
			-- way of knowing about. A friend's is the nearest thing to that and lands harder anyway.
			Headshot = { WearFriendAvatar = true },
		},
		{
			Id = "Stalker",
			Name = "Stalker",
			Model = "Stalker",
			Description = "It keeps station behind you and never closes the gap, right up until it does.",
		},
		{
			Id = "Sisters",
			Name = "The Sisters",
			-- One rig. The pair is two copies of it, and a headshot only has room for the one.
			Model = "Sister",
			Description = "Two of them, walking abreast and unhurried. They have all the time there is.",
		},
		{
			Id = "Chaos",
			Name = "Chaos",
			Model = "Chaos",
			Description = "It comes down the corridor at speed. The hotel warns you first, in red.",
			-- Its part is invisible and everything you see of it is fire. Stood in for by a ball the
			-- size of that fire, in the colour its emitters run at.
			Headshot = {
				Standin = {
					{
						Size = Vector3.new(5, 5, 5),
						Color = Color3.fromRGB(255, 60, 20),
						Material = Enum.Material.Neon,
					},
				},
			},
		},
		{
			Id = "Watcher",
			Name = "Watcher",
			Model = "Watcher",
			Description = "It waits at the far ends of corridors, leaning out just far enough to be caught.",
		},
		{
			Id = "Ghost",
			Name = "Ghost",
			Model = "Ghost",
			Description = "A guest who never checked out. It drifts the floors and wants nothing from anyone.",
			-- Both of these are what it already is in the world: `GhostRenderService` swaps the rig
			-- for a random friend's avatar and renders the whole thing at 0.5. The card matches it
			-- rather than inventing its own look, so the index and the hallway agree.
			Headshot = { WearFriendAvatar = true, Transparency = 0.5 },
		},
		{
			Id = "Creep",
			Name = "Creep",
			Model = "Creep",
			Description = "The lights go out around it. That is usually the whole of what you get.",
			-- Same problem as Chaos, and the same answer: its two sparkle emitters sit two studs apart
			-- on an invisible slab, so the stand-in is the pair of red points they draw.
			Headshot = {
				Pitch = 0,
				Standin = {
					{
						Size = Vector3.new(0.55, 0.55, 0.55),
						Offset = Vector3.new(-1, 0, 0),
						Color = Color3.fromRGB(255, 0, 4),
						Material = Enum.Material.Neon,
					},
					{
						Size = Vector3.new(0.55, 0.55, 0.55),
						Offset = Vector3.new(1, 0, 0),
						Color = Color3.fromRGB(255, 0, 4),
						Material = Enum.Material.Neon,
					},
				},
			},
		},
		{
			Id = "Eye",
			Name = "Eye",
			Model = "Eye",
			Description = "It hangs in the dark and holds the room's attention. Staring back is expensive.",
			Headshot = { Focus = "Eyeball", Pitch = 4 },
		},
	} :: { Entry },
}
