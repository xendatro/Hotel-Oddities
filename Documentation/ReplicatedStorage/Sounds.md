# ReplicatedStorage / Sounds

Sound templates, found by name and played through `AudioService`. Most templates are described with the service that plays them; this page covers folders that need their own setup notes.

## LocationAmbience

Add one child folder for each POI name, then put its ambient templates in that folder. The client plays every template in the matching folder while the player is near a tagged POI with the same name. It fades each sound up over `AmbienceConfig.LocationAmbience.FadeDistance` studs before the POI bounds and fades it out while the player leaves. Multiple POIs with the same name share the folder, and only the closest matching POI sets the volume. Multiple templates in a folder play together as loops.

The template's `PlaybackRegion` stays intact when the service clones it, so an authored region loops as the location ambience. Supported templates are `AudioEmitter` with a child `AudioPlayer` named `Player`, a standalone `AudioPlayer` or a legacy `Sound`.

## ExtraAmbience

Put any one-shot templates in this folder. The client picks one at random every 45 to 90 seconds, using the `Ambience` bus. It skips an interval while ambience is suppressed, on the lobby floor or on the death screen. Supported templates are `AudioEmitter` with a child `AudioPlayer` named `Player`, a standalone `AudioPlayer` or a legacy `Sound`.

## IntroCutscene

The intro cutscene's twelve cues, and the swap sheet for them. They exist only in Studio (Edit), not on disk, so a swap is kept only once the place is saved or published. All values below were read from Studio. Nothing was listened to or play-tested.

### Shape and playback

- Every cue is an `AudioEmitter` at `ReplicatedStorage.Sounds.IntroCutscene.<Cue>`. It holds an `AudioPlayer` named `Player` (the `Asset` you swap) and a `Wire` from `Player` to the emitter, the same shape as the other templates in `ReplicatedStorage.Sounds`.
- Each emitter has a string attribute `Cue` describing when it plays, written for the team; the code never reads it.
- No cue carries the `RadioAllowed` tag. `AudioService` relays any played template with that tag (or whose emitter has it) to teammates' walkie-talkies, so a tagged cue would let other players hear someone's intro.
- `IntroCutsceneService` plays every cue except `Flicker` and `LightOut` as 2D sound with `AudioService:Play2D`. That clones only the `Player` AudioPlayer, so settings on the emitter itself do nothing for these cues.
- `LightSweep` plays `Flicker` and `LightOut` with `AudioService:Play3DSound`. That clones the whole emitter onto the dying lamp (its PrimaryPart, or the part holding its light) on the SFX bus, with the listener at the camera. The emitter's distance attenuation (the default curve on all of them) therefore applies to these two.
- The code reads `Asset`, `Volume`, `PlaybackSpeed` and `PlaybackRegion` from the template. It sets `Looping` itself: `Drone` and `Heartbeat` loop and nothing else does, whatever the template says.
- **Effective volume** = template `Volume` × `IntroCutsceneConfig.Sounds.Cues.<Cue>.Gain` × bus volume. `Type` has Gain 0.8; every other 2D cue has Gain 1. `Flicker` and `LightOut` have no Gain and play at the template Volume × the SFX bus. The buses are the `AudioFader`s in `workspace.Sounds`, and the place file has both `Music` and `SFX` at 0.5.
- `Drone` and `Heartbeat` are also multiplied every frame by their level curves (`Drone` and `Heart` in `IntroCutsceneConfig.Grade`). Each level is followed with an 8/s exponential ease (`Sounds.LevelSpeed`), so a step in a curve lands within about a quarter of a second. The heartbeat's cut at 18.0 is the one exception: it is instant.
- Times are **track seconds** from the take-over as the player walks out of the arrival elevator.
  - **Stalker beats skipped.** This happens when the corner has not streamed in within 1 s or the clip is not ready. The track jumps from 3.4 to 10.2, so `Notice`, `Dip` and `Whip` never play, `Heartbeat` starts at the jump, and every cue from 10.2 on plays 6.8 s sooner in real time.
  - **Player skips.** The cutscene's audio fades to silence over 0.3 s, even when the skip lands on the black card, and no later cue plays. `Flicker` and `LightOut` fade with it, and no new lamp starts to flicker once the skip is committed; a lamp already flickering still goes out, its `LightOut` at the faded level.
  - **The return (22.3–23.45).** A one-shot still sounding at 22.3, in practice the `Blackout` tail, fades linearly to silence by 23.45. Every player is stopped and destroyed on restore.

### The cues

| Cue | Asset id | Asset, creator | Loop | Volume | Speed | Region (s) | Bus | Gain |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `Drone` | 9112795571 | Hollow Rumble 2 (SFX), ProSoundEffects | yes | 0.6 | 1 | whole (76.8 s file) | Music | 1 |
| `Heartbeat` | 9116795681 | Heart Beat, puszak; the same asset as `ReplicatedStorage.Sounds.Heartbeat` (the Blind heartbeat) | yes | 0.25 | 1, times the tempo curve | whole (0.72 s file) | SFX | 1 |
| `Type` | 9120300134 | Typewriter Key 2 (SFX), ProSoundEffects | no | 0.12 | 1, times a random 0.92-1.08 per tick | 0.04-0.32 | SFX | 0.8 |
| `Notice` | 9043342495 | DARK BRAAM 05, APMOfficial | no | 0.5 | 1 | whole (7.29 s file) | SFX | 1 |
| `Dip` | 9120720141 | Whoosh Giant Swish By 6 (SFX), ProSoundEffects | no | 0.4 | 1.2 | 0.75-2.09 | SFX | 1 |
| `Whip` | 9120698415 | Whoosh By Howling Wind Light Rumbling 12 (SFX), ProSoundEffects | no | 0.55 | 1 | 0.85-3.6 | SFX | 1 |
| `Flicker` | 166047422 | Shared_Ambients_Objects_Light_Flicker_Wave 2 1 0_1, Keyrut; the same asset as `ReplicatedStorage.Sounds.Flicker` (Volume 3.5 there) | no | 5 | 1, ±5 % per lamp | whole (1.41 s file) | SFX, 3D on the lamp, played by `LightSweep` | none |
| `LightOut` | 9113808115 | Circuit Breaker 1 (SFX), ProSoundEffects | no | 1.6 | 1, ±8 % per lamp | 0.12-0.85 | SFX, 3D on the lamp, played by `LightSweep` | none |
| `EyesOpen` | 9043335849 | SWELL 19, APMOfficial | no | 0.5 | 1 | whole (8.07 s file) | SFX | 1 |
| `Rush` | 9043343896 | REVERSE NOISE HARD END 17, APMOfficial | no | 1 | 1 | 1.05 to the end (2.12 s file) | SFX | 1 |
| `Blackout` | 9043338193 | BIG IMPACT HIT 14, APMOfficial | no | 0.7 | 1 | 0.07 to the end (7.42 s file) | SFX | 1 |
| `Toggle` | 138744734909383 | Hover Pls Donate [OLD], Villager0YT; the same asset as `ReplicatedStorage.Sounds.PlayerLocatorHover` | no | 1.5 | 1 | whole (0.50 s file) | SFX | 1 |

"Whole" means the region is the default 0-60000, so the file plays from its start. Loudest short-term level measured by the Studio build pass in Edit, after the cue's Volume and before the bus (not re-measured since): Drone -19.7 dB (average -26.4), Heartbeat -13.2 at full level, Type -27.4 per tick, Notice -13.9, Dip -19.3, Whip -17.5, Flicker -9.8 unattenuated, LightOut -2.7 unattenuated (about -24 at 20 studs and -31 at 45), EyesOpen -15.4, Rush -11.6 at the hard end, Blackout -9.2, Toggle -23.2. For comparison: StalkerSting -18.0, MimicSting -14.3, MadGuestSting -10.4, Ambience1 -23.3 (average -30.2).

### When each cue plays

The event names are entries of `IntroCutsceneConfig.Events`; the level and tempo curves are keys of `IntroCutsceneConfig.Grade`.

| Cue | Event | Plays at (s) | On screen |
| --- | --- | --- | --- |
| `Drone` | take-over | 0 to 23.45. Level: fades in to 1.0 over 0-1.5, holds 1.0 to 10.6, swells to 1.2 by 16.8 and 1.45 at 17.95, ducks to 0.35 at 18.0, holds 0.35 to 21.8, then fades to 0 over 21.8-23.45 | The whole cutscene, from the drift out of the doorway to the return at the player's head |
| `Heartbeat` | `Heartbeat` | Starts at 3.9, silent; at 10.2 when the Stalker beats are skipped. Volume: 30 % by 4.9, held to 6.1, 78 % at 6.5, 85 % by 13.0, 100 % by 16.8. Tempo (PlaybackSpeed, with an `AudioPitchShifter` at 1 / tempo keeping the pitch natural): 0.85 until 6.1, rising to 1.08 by 6.7, 1.12 by 13.0 and 1.25 by 17.0. Cut to silence at 18.0 | Faint through the pan west, up at the Stalker notice, full as the last lamp dies and the Creep stares |
| `Type` | caption typing | One tick on every second character typed, at most one per 0.035 s. Caption from 0.6 at 28 characters/s. The first-visit line is 30 characters plus the display name and the replay line 41 plus the name, so a 10-character name types until about 2.0 (2.4 for a replay). Card title 18.5-19.8 at 22/s, subtitle 20.3-21.3 at 16/s. Erasing is silent | The welcome caption; the card "Five computers. One way out." / "Enjoy your stay." |
| `Notice` | `Notice` | 6.1, Stalker beats only | The camera punches in on the Stalker at the corner of corridor A, with a shake; its eyes flare at 6.42 as the push-in lands |
| `Dip` | `Dip` | 8.5, Stalker beats only; crests about 0.25 s after play | The Stalker withdraws behind the corner (0.45 s) with a dark wisp puff |
| `Whip` | `Whip` | 9.6, Stalker beats only; peaks about 0.3 s after play | The whip pan back to face north up corridor B (9.6-10.2) |
| `Flicker` | `Lights`, `JunctionOut` | At each lamp's kill; stopped when the lamp dies. Lamps within 3 studs of the same distance form a group, and the groups, far to near, take the last N entries of `Lights.Steps` (10.8, 11.65, 12.4, 13.8, 14.55, 15.15). Extra groups are pushed earlier but never before 10.6; in practice they fire at 10.7, when the sweep is scheduled. Each extra lamp in a group adds 0.07 s. The junction lamp over the arrival flickers at 15.75. With all of corridor B streamed in (the Edit count, 11 lamps): 10.80, 11.65 and 11.72, 12.40 and 12.47, 13.80, 14.55 and 14.62, 15.15 and 15.22, junction 15.75 | Corridor B's lamps die toward the camera |
| `LightOut` | lamp death | 0.38 s after each `Flicker` (`Lights.Flicker`); the junction lamp 0.45 s after, at 16.2. With the Edit count: 11.18, 12.03 and 12.10, 12.78 and 12.85, 14.18, 14.93 and 15.00, 15.53 and 15.60, junction 16.20 | Each lamp goes dark; after the junction lamp only the Creep's eyes are left |
| `EyesOpen` | `EyesSwell` | 12.1; rises out of silence and crests about 1.05 s later | The Creep's eyes open at 13.0 (the `EyesOpen` event, with a slow shake) |
| `Rush` | `Rush` | 17.0; hard end about 1.03 s after play, on the 18.0 cut | The same event launches the distortion from the Creep at the camera (45 studs/s) |
| `Blackout` | `SmashCut` | 18.0; the leading 0.07 s of silence is trimmed so the hit lands on the cut; the tail carries under the card and fades out 22.3-23.45 | Smash cut to black; the same event cuts the heartbeat |
| `Toggle` | Replay pill | On each toggle of the Replay pill (T, gamepad X or a tap) during the elevator loading screen, before any cutscene | The pill flips between "Replay intro" and "Intro queued" |

The lamp count in a live server depends on what has streamed in by 10.7 s; with fewer groups, the ones found take the latest steps. With fewer than three lamps in the region there are no corridor kills at all, only the junction lamp and the darkening ambient.

### Swapping a cue

1. Select `ReplicatedStorage.Sounds.IntroCutscene.<Cue>.Player` and replace its `Asset`. Keep the emitter's name, the child named `Player` and the `Wire`: the code finds the cue by name (`IntroCutsceneConfig.Sounds.Cues.<Cue>.Name`) and plays the `Player` child. Never add the `RadioAllowed` tag.
2. Wait for the new asset to load (`IsReady` true and a `TimeLength` above 0). Use APM, PSE, Roblox-owned or the group's own audio so it plays in this universe.
3. Reset or retrim `PlaybackRegion`. The old region belongs to the old file. A region past the new file's end plays nothing, and a leftover start trim cuts into the new sound.
4. Re-level with the template `Volume`, remembering the Gain and bus multipliers above. `Type` plays at 0.8 of its Volume.
5. For `Flicker` and `LightOut`, also check the emitter's distance attenuation: they play 3D from lamps 20-80 studs away.
6. For the loops, pick a file that loops seamlessly. `Heartbeat` is sped up to 1.25x, with the pitch held by a shifter, so a slow single beat works best.
7. Update the `Cue` attribute if the description changes, then save the place.

**Timed cues.** `Dip`, `Whip`, `EyesOpen`, `Rush` and `Blackout` are timed by their `PlaybackRegion` against a fixed event. A replacement with a different envelope lands off the beat, so trim it with `PlaybackRegion` rather than moving the event:
- `Rush` needs the hardest care: its hard end must hit the 18.0 cut, about 1.03 s after it starts at 17.0. Moving `Events.Rush` to compensate would also move the distortion launch, which is the same event.
- `Dip` shares its event with the Stalker's withdraw, so its crest should land inside that 0.45 s.
- `EyesOpen` is played by its own event, `EyesSwell` at 12.1, so that it crests when the eyes open at 13.0. For a swell with a different rise, you can move `EyesSwell` without touching anything else.
- `Whip` is the only sound on its event, but the camera whip is keyed separately in `Camera.Keys` (9.6-10.2).
- `Blackout` must hit on its first frame: trim any leading silence with the region's start.
- `Notice` shares 6.1 with the camera shake, so a slow-attack replacement arrives after the punch.
