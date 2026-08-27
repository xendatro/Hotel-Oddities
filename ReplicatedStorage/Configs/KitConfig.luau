local KitCatalogConfig = require(script.Parent.KitCatalogConfig)
local ItemShopConfig = require(script.Parent.ItemShopConfig)
local SprintConfig = require(script.Parent.SprintConfig)

export type Rarity = {
	Id: string,
	Name: string,
	Order: number,
	GemPrice: number,
	Weight: number,
	Budget: number,
	Color: Color3,
	Accent: Color3,
}

export type Kit = KitCatalogConfig.Kit

local Rarities: { Rarity } = {
	{
		Id = "Common",
		Name = "Common",
		Order = 1,
		GemPrice = 150,
		Weight = 45,
		Budget = 12,
		Color = Color3.fromRGB(168, 166, 158),
		Accent = Color3.fromRGB(84, 82, 78),
	},
	{
		Id = "Uncommon",
		Name = "Uncommon",
		Order = 2,
		GemPrice = 350,
		Weight = 27,
		Budget = 24,
		Color = Color3.fromRGB(126, 176, 122),
		Accent = Color3.fromRGB(56, 96, 56),
	},
	{
		Id = "Rare",
		Name = "Rare",
		Order = 3,
		GemPrice = 750,
		Weight = 16,
		Budget = 40,
		Color = Color3.fromRGB(104, 148, 196),
		Accent = Color3.fromRGB(56, 92, 140),
	},
	{
		Id = "Epic",
		Name = "Epic",
		Order = 4,
		GemPrice = 1500,
		Weight = 8,
		Budget = 60,
		Color = Color3.fromRGB(158, 116, 196),
		Accent = Color3.fromRGB(100, 64, 140),
	},
	{
		Id = "Legendary",
		Name = "Legendary",
		Order = 5,
		GemPrice = 3000,
		Weight = 3.2,
		Budget = 85,
		Color = Color3.fromRGB(214, 164, 84),
		Accent = Color3.fromRGB(152, 106, 40),
	},
	{
		Id = "Mythic",
		Name = "Mythic",
		Order = 6,
		GemPrice = 6000,
		Weight = 0.8,
		Budget = 115,
		Color = Color3.fromRGB(206, 96, 106),
		Accent = Color3.fromRGB(144, 48, 60),
	},
}

export type Stat = {
	Id: string,
	Name: string,
	Base: number,
	Mode: string,
	Apply: string,
	HigherIsBetter: boolean,
	Cost: number,
	Minimum: number,
	Maximum: number,
	Order: number,
}

local Stats: { Stat } = {
	{
		Id = "MaxHealth",
		Apply = "Humanoid",
		Name = "Health",
		Base = 100,
		Mode = "Absolute",
		HigherIsBetter = true,
		Cost = 0.25,
		Minimum = 40,
		Maximum = 260,
		Order = 1,
	},
	{
		Id = "WalkSpeed",
		Apply = "Humanoid",
		Name = "Speed",
		Base = 16,
		Mode = "Absolute",
		HigherIsBetter = true,
		Cost = 4,
		Minimum = 10,
		Maximum = 26,
		Order = 2,
	},
	{
		Id = "JumpPower",
		Apply = "Humanoid",
		Name = "Jump",
		Base = 50,
		Mode = "Absolute",
		HigherIsBetter = true,
		Cost = 0.4,
		Minimum = 30,
		Maximum = 90,
		Order = 3,
	},
	{
		Id = "DetectionRadius",
		Apply = "Attribute",
		Name = "Stealth",
		Base = 1,
		Mode = "Scale",
		HigherIsBetter = false,
		Cost = 60,
		Minimum = 0.55,
		Maximum = 1.6,
		Order = 6,
	},
	{
		Id = "Stamina",
		Apply = "Attribute",
		Name = "Stamina",
		Base = SprintConfig.Stamina.Max,
		Mode = "Absolute",
		HigherIsBetter = true,
		Cost = 0.12,
		Minimum = 40,
		Maximum = 220,
		Order = 4,
	},
	{
		Id = "SprintMultiplier",
		Apply = "Attribute",
		Name = "Sprint",
		Base = SprintConfig.SpeedMultiplier,
		Mode = "Scale",
		HigherIsBetter = true,
		Cost = 55,
		Minimum = 1.15,
		Maximum = 2.2,
		Order = 5,
	},
}

local RaritiesById: { [string]: Rarity } = {}
for _, rarity in Rarities do
	RaritiesById[rarity.Id] = rarity
end

local StatsById: { [string]: Stat } = {}
for _, stat in Stats do
	StatsById[stat.Id] = stat
end

local KitConfig = {
	Rarities = Rarities,
	RaritiesById = RaritiesById,
	Stats = Stats,
	StatsById = StatsById,
	Entries = KitCatalogConfig.Entries,
	EntriesById = KitCatalogConfig.EntriesById,

	DefaultKit = KitCatalogConfig.DefaultKit,
	ItemPointDivisor = 10,
	MaxRefundFraction = 0.5,

	Roll = {
		GemCost = 400,
		DuplicateRefundFraction = 0.4,

		ReelLength = 42,
		WinnerIndex = 36,
		SpinTime = 3.4,
		SettleTime = 0.55,
		TickInterval = 0.06,
		RevealTime = 0.35,
		CardWidth = 0.2,
		CardPadding = 0.03,
		CardTilt = 9,
		MinScale = 0.74,
		MaxScale = 1.04,
		ShakeTime = 0.32,
		ShakeStrength = 0.0016,
		BackdropTime = 1.3,
		BackdropTransparency = 0.55,
		ResultPop = 1.45,
	},

	Viewport = {
		FieldOfView = 40,
		Padding = 1.55,
		Yaw = 20,
		Pitch = 5,
		Zoom = 1,
		Ambient = Color3.fromRGB(196, 192, 186),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -0.8, -0.45),
	},

	Animation = {
		Card = {
			HoverScale = 1.08,
			HoverLift = 0.04,
			HoverTilt = 2.5,
			PressScale = 0.94,
			SelectedScale = 1.04,
			SelectedLift = 0.02,
			SelectedTilt = -1.5,
			HoverTime = 0.16,
			PressTime = 0.07,
			SettleTime = 0.24,
			Stagger = 0.03,
			EnterScale = 0.82,
			EnterDrop = 0.05,
		},
		Button = {
			HoverScale = 1.08,
			PressScale = 0.92,
			HoverTilt = -1.5,
			HoverTime = 0.14,
			PressTime = 0.06,
			SettleTime = 0.2,
		},
		Info = {
			FadeTime = 0.2,
			Rise = 0.02,
		},
		Row = {
			Padding = 0.03,
			TextSize = 30,
			HeaderTextSize = 20,
			Stagger = 0.025,
			FadeTime = 0.18,
		},
	},

	Text = {
		Locked = "LOCKED",
		Owned = "OWNED",
		Equip = "EQUIP",
		Equipped = "EQUIPPED",
		Buy = "BUY",
		CannotAfford = "NOT ENOUGH",
	},
}

function KitConfig.GetRarity(kit: Kit): Rarity
	return RaritiesById[kit.Rarity] or Rarities[1]
end

function KitConfig.ItemPoints(itemId: string): number
	local entry = ItemShopConfig.EntriesById[itemId]
	if not entry then return 0 end
	return entry.CoinPrice / KitConfig.ItemPointDivisor
end

function KitConfig.StatPoints(statId: string, value: number): number
	local stat = StatsById[statId]
	if not stat then return 0 end
	local delta = value - stat.Base
	if not stat.HigherIsBetter then delta = -delta end
	return delta * stat.Cost
end

function KitConfig.Spend(kit: Kit): number
	local spent = 0
	local refunded = 0

	for statId, value in kit.Stats or {} do
		local points = KitConfig.StatPoints(statId, value)
		if points >= 0 then
			spent += points
		else
			refunded -= points
		end
	end

	for itemId, count in kit.Items or {} do
		spent += KitConfig.ItemPoints(itemId) * count
	end

	local rarity = KitConfig.GetRarity(kit)
	return spent - math.min(refunded, rarity.Budget * KitConfig.MaxRefundFraction)
end

function KitConfig.Validate(): { string }
	local problems = {}

	for _, kit in KitConfig.Entries do
		local rarity = RaritiesById[kit.Rarity]
		if not rarity then
			table.insert(problems, `{kit.Id}: unknown rarity "{kit.Rarity}"`)
			continue
		end

		for statId, value in kit.Stats or {} do
			local stat = StatsById[statId]
			if not stat then
				table.insert(problems, `{kit.Id}: unknown stat "{statId}"`)
			elseif value < stat.Minimum or value > stat.Maximum then
				table.insert(problems, `{kit.Id}: {statId} {value} outside {stat.Minimum}..{stat.Maximum}`)
			end
		end

		for itemId in kit.Items or {} do
			if not ItemShopConfig.EntriesById[itemId] then
				table.insert(problems, `{kit.Id}: unknown item "{itemId}"`)
			end
		end

		local spend = KitConfig.Spend(kit)
		if spend > rarity.Budget + 0.001 then
			table.insert(problems, `{kit.Id}: spends {string.format("%.1f", spend)} of a {rarity.Budget} {rarity.Id} budget`)
		end
	end

	return problems
end

return KitConfig
