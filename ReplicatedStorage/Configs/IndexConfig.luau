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

	--- Every entry starts discovered while the index is being built out. Flip this to false once
	--- there is somewhere to persist discovery from, and the runtime API on `IndexUIService`
	--- (`SetDiscovered` / `SetDiscoveredSet`) becomes the only thing that unlocks an entry.
	DiscoveredByDefault = true,

	--- What an entry the player has not met yet looks like. Undiscovered entries keep their slot in
	--- the grid rather than being skipped: a gap where something will go is the point of a bestiary,
	--- and a list that reshuffles as it fills makes the pages meaningless.
	Locked = {
		Name = "???",
		Description = "You have not met this one yet.",
		ShowSilhouette = true, -- render the model anyway, tinted flat; false hides the viewport
		Tint = Color3.fromRGB(28, 26, 32),
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
