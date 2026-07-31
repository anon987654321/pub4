# Dilla

A beat engine in Ruby. One file, `dilla.rb`, with helpers under `lib/`. It
generates harmony, programs drums, plays sampled loops against them, mixes,
masters, and writes an mp3 or wav. Everything runs locally through `ffmpeg` and
`fluidsynth` — nothing is uploaded and nothing is fetched at render time.

Tests: `cd MASTER && bundle exec ruby -Itest test/test_dilla.rb`

```sh
cd studio/dilla
ruby dilla.rb out.wav 18                 # one render, 18 bars
TRACK=kembara_rindu ruby dilla.rb out.wav 18
ruby dilla.rb                            # continuous stream
ruby dilla.rb help
```

---

## What happens during a render

```
progression  ──►  theory refine  ──►  pads · bass · leads ──┐
                                                            │
sampled loop ──►  varispeed · chop · vary · EQ ─────────────┤
                                                            ├──►  bus analog
drum grid    ──►  microtiming · swing · dirt · duck ────────┘      (saturation
                                                                    per channel)
                                                                        │
        sonitex tape ──► analog chain ──► loudnorm ──► tape hysteresis
                                       ──► tilt ──► dropout ──► mono bass
```

Four things are worth knowing about that order.

**Per-channel saturation happens before summing.** A desk saturates every
channel on the way in, so each source makes its own harmonics and those
harmonics then intermodulate in the bus. A single saturator on the master can
never do that, because by the time it runs the sources no longer exist
separately. `BUS_ANALOG` drives each bus into a limiter and takes the level back
out, hardest on drums, lightest on bass.

**Tape hysteresis runs on the finished master**, because it is per-sample DSP in
Ruby and is by a wide margin the slowest stage here. It is opt-in and reports
its own cost.

**Swell, tilt, dropout and mono-bass run after loudness normalisation.** Applied
before it, loudnorm simply removes them — a 3 dB musical swell is exactly what a
normaliser exists to flatten.

**The harmonic guard runs before arrangement**, so if it mutes the tonal layers
nothing downstream has to be unpicked.

---

## Samples

`TRACK_SAMPLE_LOOPS` holds the loops. Each carries its own tempo and its own
low-end and top-end correction, because the loops differ and one global value is
wrong for whichever loop it was not tuned against.

| track | source | tempo | key (fit) | hp / shelf / lp |
|---|---|---|---|---|
| `kembara_rindu` | 4-bar Ableton loop | 92 | C minor (0.71) | 90 / −7 / 5600 |
| `semua_untuk_mu` | 0:36–0:46 of the source | 96 | G minor (0.836) | 45 / 0 / 5200 |
| `lo_borges` | first 4 bars | 114 | D major (0.697) | 60 / −3 / 6000 |
| `rauingar` | own recording, 2 bars | 92 | C♯ minor (0.70) | 60 / −3 / 6200 |

Older ingest names (`four_seven`, `nightbus`, `dmaj_open`) still resolve through
`TRACK_SAMPLE_LOOP_ALIASES`, including for layer-profile lookup.

### Finding a loop's boundaries is a manual job

Onset and energy detection finds where something *changes*, which is not where a
musical phrase *starts*. It put `semua_untuk_mu` 22 seconds early, on the end of
a spoken intro. Given a boundary the analysis is reliable and will confirm or
refute it — key fit 0.27 for the detector's cut against 0.836 for the operator's.
Asked to find one, it is not.

Where two analyses disagree on tempo, loop the candidates and measure the seam:
a correct length rejoins itself quietly. On `lo_borges`, 8.421s (114 BPM)
rejoins at −1.1 dB and 8.000s (120) at −8.6 dB. That settled a disagreement
between the onset sweep and a self-similarity peak — self-similarity finds the
shortest thing that repeats, which is not necessarily the bar.

---

## Drums

~60 presets in `lib/producer_dna.rb`, in categories that are deliberately
kept apart. Being able to say which a grid is matters more than having more.

| category | examples | what it means |
|---|---|---|
| transcribed | `four_seven`, `dangelo_learned` | measured off a recording |
| constructed | `dilla_donuts`, `flylo_zodiac`, `boom_bap`, `soul_shuffle` | built to a described feel |
| pack import | `pack_729_1..6` | extracted from licensed MIDI |
| push pads | `push_four`, `push_sparse` | straight and sparse on purpose |
| expansion | `afro_clave`, `euclid_five`, `ghost_cloud`, … | more pockets, same backbeat rule |

Export every grid as GM MIDI clips: `ruby dilla.rb export-midi` → `samples/midi/`.
Re-import a pack folder: `ruby dilla.rb import-midi samples/midi/boom_bap`.

**The backbeat stays on 4 and 12.** Every transcription in the file says so.
What makes these records sound the way they do is `MICROTIMING_MS` — snare
10–28 ms early, hats 12–32 ms late, kick near the grid — measured in
milliseconds, not in 16ths. Moving the backbeat does not produce a drunk
hip-hop beat, it produces a beat that is not hip-hop. Snare on 8 is the one
legitimate exception: that is the backbeat when the bar is felt half-time.

**Swing is 53–56%, on eighth notes.** The off-kilter quality comes from
`NO_QUANTIZE=1` and per-voice lean, not from a large swing number. A forum
claim of "about 70%" sent this the wrong way once; better sources are specific
and lower.

**`SWING_ROLE_SCALE` leans each voice differently** — kick at 0, locked to the
grid, everything else against it, percussion furthest back. At SWING=54 and 82
BPM: kick 0.0, snare +12.4, hat +16.1, ghost +17.6, perc +21.2 ms. Take the
locked kick away and it stops reading as feel and starts reading as unsteady
tempo.

---

## Switches

Sample handling:

| switch | what |
|---|---|
| `HARMONIC_KEEP=1` | transpose generated pads onto the loop's detected key |
| `HARMONIC_SHUFFLE=1` | order chords so the top voice traces one arc |
| `ORGANIC_VARY=1` | rebuild the bed as N differing passes — `-stream_loop` is bit-identical, and nothing acoustic is |
| `LOOP_CHOP_SLICES=8` | cut each pass into slices and rotate them; the loop becomes material rather than a part |
| `SAMPLE_LOOP_VARISPEED` | pitch follows tempo, as a record does (default on) |
| `SAMPLE_LOOP_SEMITONES` | pitch **without** changing tempo |
| `SAMPLE_FM=1` | audio-rate vibrato = real FM sidebands, floored at 700 Hz so chord tones are untouched |
| `SAMPLE_SCALE=1` | layer the loop at degrees of its own key |
| `LOOP_WOW_CENTS` | tape instability on the loop only, never the kit |
| `LOOP_DELAY_BEATS` | tempo-synced echo (1.5 = dotted-8th) |

Two loops as one instrument — `DILLA_XSAMPLE` names the partner:

| switch | what |
|---|---|
| `DILLA_XCONVOLVE=1` | one loop becomes the room the other plays in |
| `DILLA_XGATE=1` | one loop's harmony driven by the other's rhythm (`amultiply`, not a gate) |

Drums:

| switch | what |
|---|---|
| `DRUM_PRESET` | any drum preset key (`ruby -e` / `DRUM_PRESET=boom_bap`) |
| `NO_QUANTIZE=1` | quantise off entirely |
| `SWING_ROLE_SPREAD` | how far the per-voice lean spreads |
| `FLYLO_DRUM_OVERLAY=1` | Camel dual-bus: sub at 55/110/180, top at 3.5k/6.5k/9k |
| `FLYLO_TOP_DIRT` | phaser/flanger/crush on cymbals, kick untouched |
| `FLYLO_HAT_DUCK` | duck the top bus by the kick bus |
| `DRUM_FIELD_LAYER` | room tone under the kit, ducked by it |

Movement and master:

| switch | what |
|---|---|
| `BUS_ANALOG` | per-channel saturation before summing |
| `TAPE_HYSTERESIS` | Jiles-Atherton, RK4 — path-dependent, unlike every other stage |
| `TAPE_WOW_MS` | Ornstein-Uhlenbeck flutter |
| `MASTER_TILT_DB` | negative = darker; lows up as highs come down |
| `MONO_BASS_HZ` | sum below N to mono |
| `ORGANIC_BREATH` / `ORGANIC_SWELL` | correlated loudness+brightness; phrase swell |
| `DILLA_DROPOUT_EVERY` | silence just before every Nth downbeat |
| `DILLA_DRONE` / `DILLA_TAPE_STOP` | stretched bed; platter brake |

Vocals (`RAP_VOCAL=<slug>`, `0` to disable):

| switch | what |
|---|---|
| `RAP_VOCAL_SNAP` | place sung lines on the grid instead of stretching |
| `RAP_VOCAL_LEAN_MS` | drag each line behind the beat, plus a fixed walk |
| `RAP_VOCAL_SWELL` | reverse pre-swell arriving on each line's downbeat |

Snapping exists because a freely-sung take has no tempo to stretch onto. Across
source BPMs 96–128 against a 92 beat, one take landed 31/20/19/18/25/14% of its
onsets on the grid against a ~20% random baseline — slowing it made alignment
*worse*. Placing lines instead took line starts to 87% on grid at a 5 ms median.

---

## Other commands

```sh
ruby dilla.rb crate                    # 38 synthesised one-shots and textures
ruby dilla.rb import-midi <dir>        # MIDI drum clips -> 16-step grids
ruby dilla.rb beauty <file>            # harmony score and recommendations
ruby dilla.rb quality <file>           # LUFS, true peak, harshness, sub/kick
ruby dilla.rb separate <file>          # demucs 4-stem
```

---

## Controls that are not what they look like

Each of these cost real debugging time. They are listed because the failures
were all silent — the code ran, returned success, and did nothing.

- **`DRUM_VOL` does nothing in the main render.** It is read inside
  `build_harmony_loud`, a different path. Muting the drums with it measures
  identically to pushing it to 0.72. Use `DRUM_MIX_WEIGHT`, `DRUM_BUS_VOL`,
  `DRUM_BUS_GAIN`.
- **`KICK_GAIN` will not fix a loud low end** if the loop is making it. Muting
  the kick moved the 40–100 Hz band by 0.0 dB; muting the loop moved it 4.0 dB.
  Reach for `SAMPLE_LOOP_HP` first.
- **`asoftclip` does not saturate** at any threshold tried. On a clean 200 Hz
  sine it produced −40.8 dB above 500 Hz against −40.1 clean. `acrusher` the
  same. Drive into a limiter gives −19.1 dB, i.e. real harmonics.
- **`equalizer` is a peaking filter, always.** Its `t` parameter sets the *unit*
  of the width, not the shape. Shelves are `bass` and `treble`.
- **Track profiles beat the command line** unless pinned; `USER_PINNED_ENV` is
  what lets a caller win.
- **`RAP_VOCAL=0` must be explicit** — `DILLA_STYLE_DEFAULTS` soft-fills it.
- **Measure with `STREAM_NORMALIZE=0`.** With normalisation on, removing a layer
  makes the rest *louder* and the measurement describes the normaliser.
- **Concat lists need absolute paths.** The demuxer resolves relative entries
  against the list file's directory, so a relative output path silently produced
  no effect at all.

## Three findings that keep recurring

**Making room beats adding gain.** Drums that seem absent are usually masked;
most of a 9 dB drum improvement came from lowering other buses, not raising the
drums. A loop with crowded mids cannot be beaten by pushing drums into them.

**A filter can be wired correctly, run without error, and be transparent.** Only
measuring the output catches it, and adjusting parameters never will, because
the parameters were never the problem.

**Sections were unreachable, not missing.** The arrangement cycle was floored at
16 bars while a 16-bar render has a 9-bar body, so breakdown and build never
fired below about 21 bars — every short render was intro, main, outro. The
machinery had been there all along.
