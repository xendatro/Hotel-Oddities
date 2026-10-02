# Hotel Oddities trailer

Everything that makes the trailer: the shots are scripted in Studio, captured off
the screen, retimed onto each shot's own clock, then cut, graded, titled and mixed
from one file, `edit.yaml`. Swap a shot, a sound, a line of text or the grade by
editing that file and rebuilding. Nothing is hand-edited in a video editor.

```
Studio shot (ReplicatedStorage.Playtest.Trailer.Shots.<Name>)
   -> tools/capture.py   screen capture of the Studio monitor (GPU encoder, any frame rate)
   -> tools/conform.py   reads the burned-in timecode, retimes to 60 fps, crops 16:9, 1080p
   -> clips/<Name>.mkv
edit.yaml -> tools/mix.py   -> out/audio/master.wav (+ stems)
          -> tools/build.py -> out/HotelOddities_Trailer.mp4
```

## Setup

- Python venv: `python -m venv .venv` then
  `.venv/Scripts/python -m pip install numpy scipy soundfile pillow opencv-python-headless pyyaml pedalboard "cupy-cuda12x[ctk]"`.
  CuPy is optional; without an NVIDIA GPU the build composites on the CPU.
- ffmpeg 7.1 or newer (needs `ddagrab` with `dup_frames`). `project.yaml` points at
  a portable build in `%LOCALAPPDATA%/TrailerTools`; any ffmpeg on PATH works too.
- `tools/gameaudio.py` copies the game's own sounds out of Studio's local asset
  cache into `audio/game/` by matching each sound's length (`audio/game_sounds.yaml`).
  Play a sound once in Studio if it is reported missing.
- `tools/sfx.py` synthesizes the sound design (braams, impacts, risers, whooshes,
  drones, crackle, pulses) into `audio/gen/`.

`takes/`, `clips/`, `out/`, `audio/game/` and `audio/gen/` are generated and not
committed.

## Shooting a shot

The shots live in Studio under `ReplicatedStorage.Playtest.Trailer` (see
`PLAYTESTING.md`). They only run when a playtest is started and the trailer
director is called through the Playtest bridge, so normal playtests never trigger
them.

1. Start a playtest, then from a Server snippet call
   `TrailerServer.Prepare("@player")` through `ServerStorage.PlaytestCall`
   (clears enemies, pauses the director, vents and ambient oddities).
2. Start a capture long enough for warm-up plus the shot:
   `python tools/capture.py <Shot> --seconds 15 --take <name>`.
3. From a Client snippet call `Trailer.Director.Play("<Shot>")` (or
   `Trailer.Director.Sequence({...})` to run several back to back in one take).
4. `python tools/conform.py <Shot> --take <name>`, or for a sequence take
   `python tools/conform.py All --take <name> --split Arrival,Rotunda,...`.
5. Check it: `python tools/sheet.py <Shot>`.

Every shot holds its first frame for a few seconds before it starts, so lighting,
streaming, animations and images finish loading. The director preloads every
asset the stage uses before that hold. Studio renders at about 15 fps when its
window is not focused; that is fine for previews, and `conform.py` still places
every frame on the right moment, but final takes should be shot with Studio
focused.

## The edit

`edit.yaml` has four parts.

- `timeline`: shots in order. `clip` names a file in `clips/`, `in`/`out` are
  seconds on that shot's own clock, `black` is a black card of that length,
  `fade_in`/`fade_out`/`dissolve` shape the joins, `grade` overrides the global
  grade for one shot. Every entry has an `id`.
- `text`: typed captions (`type: typewriter`, typing sounds are added
  automatically), fading text, and images such as the logo (`type: image`).
- `effects`: camera shake, punch zoom, flash and glitch, placed in time.
- `audio`: every sound cue. `at` and `until` accept times like `stalker+1.3` or
  `title.end-0.5`, so cues follow their shot when the cut changes. A cue can set
  `gain`, `start`, `length`, `speed`, `fade_in`, `fade_out`, `lowpass`,
  `highpass`, `reverb`, `pan`, `loop`, `repeat` (accelerating hits) and
  `tape_stop`. Add `mute: true` to audition a mix without one cue.

Time expressions resolve against the timeline, so changing a shot's length moves
every caption, effect and sound attached to it.

## Building

```
python tools/mix.py                    # audio master and stems
python tools/meter.py                  # loudness per section
python tools/build.py --still 9.7,23.6 # PNG stills to check a look
python tools/build.py --draft          # full quality picture, fast GPU encode
python tools/build.py                  # final master (x264, slow preset)
```

All rendering runs at idle priority with a small number of workers, and must not
run while a capture is recording or a playtest is open.

## Swapping things

- A sound: point its cue's `file` somewhere else in `edit.yaml`, or replace the
  file in `audio/`.
- A line of text or a font: edit the `text` entry.
- The look: edit `grade`, or give a shot `grade: { lut: path/to/look.cube }` to
  use a LUT from any grading tool.
- A shot: re-shoot it, conform it to `clips/<Name>.mkv`, adjust `in`/`out`.
- The logo: replace `art/logo.png` (RGBA).

Fonts are Special Elite (Apache 2.0) and IM Fell English SC (OFL); their licences
are in `fonts/`.
