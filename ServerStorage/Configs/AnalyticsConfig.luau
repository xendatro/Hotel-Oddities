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
		Computers1 = { Number = 5, Name = "Computers1" },
		Computers2 = { Number = 6, Name = "Computers2" },
		Computers3 = { Number = 7, Name = "Computers3" },
		Computers4 = { Number = 8, Name = "Computers4" },
		Computers5 = { Number = 9, Name = "Computers5" },
		Escaped = { Number = 10, Name = "Escaped" },
	} :: { [string]: Step },
}
