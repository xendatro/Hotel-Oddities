--- Asset ids for the computer-hacking UI, uploaded via Open Cloud. 0 means "not available yet";
--- everything that reads this falls back to text.
---
--- Every icon is a 512x512 transparent PNG of chunky pixel art in the minigame Theme's palette
--- (cyan and neon green on near-black navy), drawn deliberately blocky so it still reads as itself
--- when the HUD shrinks it to 32px. Only ComputerIcon is required; consumers must tolerate the
--- optional keys being absent, so a rejected upload is deleted from this table rather than zeroed.
return {
	ComputerIcon = "rbxassetid://90130169839104", -- pixel-art CRT monitor icon, transparent bg, reads at 32px
	LockIcon = "rbxassetid://83099078507554", -- pixel-art cyan padlock, for the locked/unhacked state
	CheckIcon = "rbxassetid://140646860068178", -- pixel-art neon green check mark, for the hacked state
}
