export type Entry = {
	Id: string,
	Name: string,
	Description: string,
	Image: string,
}

local Entries: { Entry } = {
	{
		Id = "Bell",
		Name = "Bell",
		Description = "A hushed belfry where a great bronze bell hangs waiting. Nobody has heard it ring, and nobody wants to.",
		Image = "rbxassetid://126740917312435",
	},
	{
		Id = "Chairs",
		Name = "Chairs",
		Description = "A waiting hall of empty chairs, every one of them facing a door that never opens.",
		Image = "rbxassetid://80010336201249",
	},
	{
		Id = "Circle Bridge",
		Name = "Circle Bridge",
		Description = "A rotunda crossed by a curving bridge over nothing at all.",
		Image = "rbxassetid://71907140310793",
	},
	{
		Id = "Endless Bridges",
		Name = "Endless Bridges",
		Description = "A shaft strung with bridges that stack upward and downward farther than the eye agrees to follow.",
		Image = "rbxassetid://94148745983958",
	},
	{
		Id = "Endless Paintings",
		Name = "Endless Paintings",
		Description = "A gallery tower whose portraits climb out of sight. The frames go on. The subjects do not stay put.",
		Image = "rbxassetid://88297021739093",
	},
	{
		Id = "Endless Pillars",
		Name = "Endless Pillars",
		Description = "A hall of pillars in every direction, each row hiding the next.",
		Image = "rbxassetid://81846755392454",
	},
	{
		Id = "Endless Room",
		Name = "Endless Room",
		Description = "A room stacked inside itself, again and again, without ever reaching a last one.",
		Image = "rbxassetid://83099754281311",
	},
	{
		Id = "Endless Stairs",
		Name = "Endless Stairs",
		Description = "Stairs that wander up, across and back on themselves. Count the steps twice and get two answers.",
		Image = "rbxassetid://110098807939406",
	},
	{
		Id = "Floating",
		Name = "Floating",
		Description = "An ascension chamber where the floor has its own opinions about gravity.",
		Image = "rbxassetid://114622707414221",
	},
	{
		Id = "Hallway",
		Name = "Hallway",
		Description = "A collapsed hallway, its runner carpet leading straight into the rubble.",
		Image = "rbxassetid://114985790927864",
	},
	{
		Id = "Hallways",
		Name = "Hallways",
		Description = "A chasm spanned by hallway bridges, where the hotel forgot to put down a floor.",
		Image = "rbxassetid://109440899727298",
	},
	{
		Id = "Mess",
		Name = "Mess",
		Description = "A flooded hall left in disarray, water and wreckage where the tables used to be.",
		Image = "rbxassetid://96145545532368",
	},
	{
		Id = "Mirror",
		Name = "Mirror",
		Description = "A mirror lounge. The chandelier's reflection is on the ceiling, and so, sometimes, is yours.",
		Image = "rbxassetid://123302207510173",
	},
	{
		Id = "Paintings",
		Name = "Paintings",
		Description = "A portrait gallery whose sitters watch the door more closely than the artist ever did.",
		Image = "rbxassetid://102083403926711",
	},
	{
		Id = "Pendulum",
		Name = "Pendulum",
		Description = "An octagonal room where a slow pendulum keeps a time the hotel does not follow.",
		Image = "rbxassetid://125516537606891",
	},
	{
		Id = "Pit",
		Name = "Pit",
		Description = "An atrium opening over an abyss. The railing is decorative.",
		Image = "rbxassetid://130848757577199",
	},
	{
		Id = "Pool",
		Name = "Pool",
		Description = "A pool room of tiles and still water. The deep end is deeper than the building.",
		Image = "rbxassetid://75414717754330",
	},
	{
		Id = "Rooms",
		Name = "Rooms",
		Description = "A dollhouse of rooms within rooms, each one furnished for someone smaller than you.",
		Image = "rbxassetid://88014319673587",
	},
	{
		Id = "Stairs",
		Name = "Stairs",
		Description = "A stairwell that promises another floor and keeps changing its mind.",
		Image = "rbxassetid://107887789170963",
	},
	{
		Id = "The Garden",
		Name = "The Garden",
		Description = "A rain conservatory where the weather is indoors and the plants have grown used to it.",
		Image = "rbxassetid://75207471646020",
	},
}

local EntriesById: { [string]: Entry } = {}
for _, entry in Entries do
	EntriesById[entry.Id] = entry
end

return {
	PageId = "Rooms",
	Gui = "RoomsGui",
	Columns = 3,
	Rows = 2,

	Locked = {
		CardName = "???",
		Name = "UNDISCOVERED",
		Description = "You have not found this place yet.",
	},

	Empty = {
		Name = "ROOMS",
		Description = "Select a room.",
	},

	CounterText = "%d / %d FOUND",

	Pagination = {
		Enabled = Color3.fromRGB(255, 255, 255),
		Disabled = Color3.fromRGB(150, 148, 155),
	},

	Animation = {
		Card = {
			HoverScale = 1.06,
			HoverLift = 0.03,
			HoverTilt = 2,
			PressScale = 0.95,
			SelectedScale = 1.03,
			SelectedLift = 0.015,
			SelectedTilt = -1.2,
			HoverTime = 0.16,
			PressTime = 0.07,
			SettleTime = 0.24,
			Stagger = 0.05,
			EnterScale = 0.82,
			EnterDrop = 0.05,
			EnterTime = 0.3,
		},
		Button = {
			HoverScale = 1.15,
			PressScale = 0.9,
			DisabledScale = 0.85,
			HoverTime = 0.14,
			PressTime = 0.06,
			SettleTime = 0.2,
		},
		Info = {
			FadeTime = 0.2,
			Rise = 0.02,
		},
	},

	Entries = Entries,
	EntriesById = EntriesById,
}
