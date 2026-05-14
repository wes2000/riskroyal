# Custom SFX overrides for SoundManager

Drop `.ogg` files into this directory to override the procedural cues
synthesized by `scripts/audio/sound_manager.gd`. SoundManager scans
this directory at startup; matching filenames swap the corresponding
cue's stream from the procedural generator to the file-backed stream.

## Expected filenames

| Filename | Cue | When it fires |
|---|---|---|
| `chip_transfer.ogg` | `play_chip_transfer()` | Chip delta animation (~150ms) |
| `bust.ogg` | `play_bust()` | Player ejected from event (~400ms) |
| `crown_win.ogg` | `play_crown_win()` | Crown awarded at resolution (~600ms) |
| `match_end.ogg` | `play_match_end()` | Match winner announced (~1.0s) |
| `button_press.ogg` | `play_button_press()` | Any UI button pressed (~50ms) |
| `twist_stinger.ogg` | `play_twist_stinger()` | House Twist announced (~500ms) |

Any file not matching one of the above names is ignored. Recommended
format: 22050 Hz mono OGG Vorbis; keep durations close to the
guidance above so the cue doesn't overlap the next game event.

If a file is missing, SoundManager falls back to procedural synthesis
(see `_synth_waveform` in `sound_manager.gd`).
