export type Step = {
	Number: number,
	Name: string,
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
		FirstComputer = { Number = 5, Name = "FirstComputer" },
		ExitUnlocked = { Number = 6, Name = "ExitUnlocked" },
		Escaped = { Number = 7, Name = "Escaped" },
	} :: { [string]: Step },
}
