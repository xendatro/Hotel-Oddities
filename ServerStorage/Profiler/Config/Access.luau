-- Access is enforced on the server for every request. Copying the package to a
-- new game uses that game's creator/group, never a Hotel Oddities service.
return {
	Enabled = true,
	UserIds = {},
	GroupRoles = { owner = true, developer = true },
	AllowControlledInPublicServers = false,
}
