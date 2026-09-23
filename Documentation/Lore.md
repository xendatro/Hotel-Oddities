# Lore

The story Hotel Oddities tells so far and where each piece comes from. It is written as a reference for anyone adding text, enemies or cutscenes, so new work does not contradict what players have already been told.

Every item below carries one of three marks:

- **Team decision** — the team chose it.
- **Existing text** — something the game already says to players, with the file it lives in.
- **Invented for the intro, canon for now** — made up while building the intro cutscene, because the cutscene had to say something. These items stand until the team decides otherwise; change them freely, then update this page and the strings in `ReplicatedStorage\Configs\IntroCutsceneConfig.luau` (`Text`).

Open questions for the team are at the end.

## Team decision

- **The player is a new guest checking in.** This was the team's answer when the intro cutscene was specified. The intro treats walking out of the arrival elevator as the moment of check-in.
- **The hotel speaks in a few short typed lines.** It speaks in writing only, with no voice acting and no speaker shown.

## Existing text the intro builds on

- **The hotel acts on its own.** Deaths with no enemy are credited to "The Hotel". The hint reads "Nothing was chasing you. The hotel got you all by itself." (`DeathConfig`). The shop's flashlight is for "when the hotel decides the ceiling lights are optional" (`ItemShopConfig`).
- **Other guests never left.** The Ghost is "A guest who never checked out" and the Mad Guest checked in "long ago and never checked out". The Mimic "wears a guest's face badly" (`IndexConfig`).
- **The goal is five computers and one exit.** Each computer has a chip colour (blue, yellow, red, green, purple). The exit elevator's panel reads "EXIT ACCESS / COMPLETE ALL 5" and stays locked until all five are hacked (`Workspace.Maze15.ExitElevator`, `ElevatorService`).
- **Escaping is not the end.** The win screen reads "THIS IS NOT THE END" and "You walked out of the hotel. The hotel is not finished with you.", with "CHAPTER TWO" marked coming soon (`EndingConfig`).
- **The Stalker** "leans out of the far end of a corridor to be caught looking" and then follows you (`IndexConfig`). Its rig is all black with neon red eyes (`ReplicatedStorage.Enemies.Stalker`).
- **The Creep:** "The lights go out around it. That is usually the whole of what you get." (`IndexConfig`). In play it is a stationary pair of red eyes that kills the hallway lights, and it is drawn against a black backdrop with a distortion that sweeps past (`CreepRenderService`).
- **Arrival.** The maze's start elevator carries a sign reading "ARRIVAL" (`Workspace.Maze15.StartElevator.Identification`). The exit elevator's sign reads "EXIT".

## Invented for the intro, canon for now

### The hotel's voice

**Invented for the intro, canon for now.** The speaker is the hotel itself: not a receptionist, not a manager, not a recording. It appears as typed text in the SpecialElite typewriter face, the same hand as the win screen's typed line. It is polite, brief and hospitable, and never threatens anyone. The threat is in what the intro shows while it talks. It knows the guest's display name without being told.

It has three lines, plus a variant of the first for returning guests:

| When | Line |
| --- | --- |
| First visit, as the guest steps out of the arrival elevator | "Welcome, {DisplayName}. Your room is ready." |
| A replay (from the Replay pill, or an admin `/intro` for someone who has seen it) | "Welcome back, {DisplayName}. Your room is still ready." |
| The title card after the smash cut to black | "Five computers. One way out." |
| Under the title, just before control returns | "Enjoy your stay." |

"Your room" is never shown or explained. It is there to make the welcome sound like a real check-in, and to hint that the hotel expects the guest to stay.

### Why the elevator is "Arrival"

**Invented for the intro, canon for now.** The lobby is where players gather, shop and choose kits. Their stay starts when the Arrival elevator lets them out onto the floors. That is where the hotel greets them, so walking out of Arrival is check-in. The intro plays there, and only the first time. "Arrival" is how the hotel names the moment a guest arrives, and "Exit" is the only other door it admits to.

### The five computers and the exit, from the hotel's side

**Invented for the intro, canon for now.** The hotel states the terms of the stay openly, the way a front desk states checkout time: five computers, one way out. The hotel is not hiding the exit and does not pretend there is none. It knows about the computers and the locked exit and tells every new guest. It follows the terms at once with "Enjoy your stay.", because it does not expect them to matter. Canon so far is only this: the hotel knows the rules, states them, and is unconcerned. What the computers are to the hotel, and why they open the exit, is left open (see below).

### The Stalker, as the intro shows it

**Invented for the intro, canon for now; consistent with its Index text.** The Stalker leans out from the far corner of the corridor to the west of the arrival elevator, about 55 studs away. The camera catches it looking, and its eyes flare red at the moment it is noticed. Then it dips back behind the corner and is gone. It never approaches in the intro, which shows only the first half of its Index line: it is caught looking. The eye flare is a staging touch for the intro; the in-game Stalker's eyes are neon red but do not flare.

### The Creep, as the intro shows it

**Invented for the intro, canon for now; consistent with its Index text.** The lamps of the corridor north of the arrival die one after another, far to near, each with a flicker and a breaker clunk. The lamp over the arrival goes last, and only a pair of red eyes is left in the dark. The eyes open slowly, blink once, and a distortion rushes the camera. The smash cut to black comes as it arrives, so the intro never says what it does to the guest. The lamps going out around it is its Index line played literally. The eyes opening and blinking are staging for the intro; the in-game Creep does not animate its eyes this way.

### Only these two

**Invented for the intro, canon for now.** The intro shows only the Stalker and the Creep, never Ghosts or any other enemy, so the first thing a guest learns is two rules: something watches from the corners, and the dark is not empty. The lights going out are the hotel's own doing as much as the Creep's, matching the shop's line about the hotel deciding the ceiling lights are optional.

## Open questions for the team

- **Who is the voice?** The hotel itself, as written now, or someone who works there? Does it speak again later, when a computer is hacked, at the exit or on death, and in the same typed style?
- **What is "your room"?** Does each guest have a room? Is it one of the maze's rooms, and does it matter for escaping?
- **What are the computers to the hotel?** Its register, its locks, its eyes? Does hacking one hurt the hotel, or does it want them hacked?
- **Why does the exit need all five, and does the hotel really let guests go?** The card says "One way out", and the win screen says the hotel is not finished with you. How does Chapter Two pick this up?
- **How did the guest come to be here?** A booking, an invitation, no memory of arriving? Why do guests reach the floors by elevator rather than through a front door?
- **What are the Stalker and the Creep to the hotel?** Staff, other guests, or parts of the building?
- **Should returning guests hear something else?** For example, a line for players who have already escaped. Raising `IntroCutsceneConfig.Version` replays the intro once for everyone, which is the way to ship a rewritten intro.
