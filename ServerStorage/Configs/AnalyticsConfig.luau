export type Step = {
	Number: number,
	Name: string,
}

export type Event = {
	Name: string,
	Fields: { string },
}

return {
	Enabled = true,
	LogInStudio = false,

	Funnel = "MazeRun",
	Onboarding = true,

	Steps = {
		Joined = { Number = 1, Name = "Joined" },
		Spawned = { Number = 2, Name = "Spawned" },
		EnteredElevator = { Number = 3, Name = "EnteredElevator" },
		ReachedMaze = { Number = 4, Name = "ReachedMaze" },
		Computers1 = { Number = 5, Name = "Computers1" },
		Computers2 = { Number = 6, Name = "Computers2" },
		Computers3 = { Number = 7, Name = "Computers3" },
		Computers4 = { Number = 8, Name = "Computers4" },
		Computers5 = { Number = 9, Name = "Computers5" },
		Escaped = { Number = 10, Name = "Escaped" },
	} :: { [string]: Step },

	StepField = "Step",
	NoStep = "None",

	Events = {
		Death = { Name = "Death", Fields = { "Enemy", "Step" } },
		EnemyEncounter = { Name = "EnemyEncounter", Fields = { "Enemy", "Outcome", "Step" } },
		ComputerHacked = { Name = "ComputerHacked", Fields = { "Computer", "Step" } },
		RunEscaped = { Name = "RunEscaped", Fields = {} },
		PlayAgain = { Name = "PlayAgain", Fields = {} },
		ItemPurchased = { Name = "ItemPurchased", Fields = { "Item", "Currency" } },
		KitPurchased = { Name = "KitPurchased", Fields = { "Kit", "Rarity" } },
		KitRolled = { Name = "KitRolled", Fields = { "Kit", "Rarity", "Duplicate" } },
		Revived = { Name = "Revived", Fields = { "Source" } },
		PlayerOddity = { Name = "PlayerOddity", Fields = { "Kind" } },
	} :: { [string]: Event },

	Encounter = {
		Enabled = true,
		SweepInterval = 0.5,
		Range = 30,
		Grace = 8,
		Outcomes = {
			Died = "Died",
			Escaped = "Escaped",
		},
	},

	Economy = {
		Enabled = true,
		Currencies = {
			Gems = "Gems",
			Coins = "Coins",
		},
		Transactions = {
			Award = Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			Purchase = Enum.AnalyticsEconomyTransactionType.Shop.Name,
			Refund = Enum.AnalyticsEconomyTransactionType.Shop.Name,
		},
	},
}
