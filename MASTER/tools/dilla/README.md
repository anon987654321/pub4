# Dilla Lab

`MASTER/tools/dilla/dilla.rb` is a full-length generative production
engine: real (not just looked-up) chord/progression generation over
scale-degree functional harmony, cyclic MPC-style microtiming (including
real 96-PPQ-quantized quintuplet swing), sampled/synthesized drums, a
fluidsynth pad+lead bed, voice-led harmony, bass, melodic chops,
fugue-structured song arrangement (hook stated -> development ->
hook return), analog degradation (Sonitex STX-1260 emulation + tape/vinyl
chain), and mastered delivery. `MASTER/tools/dilla.rb` is the stable,
thin MASTER-facing wrapper that shells out to it.

The drum and transient-tone buses stream fixed-size PCM chunks into
FFmpeg, while the pad bed is synthesized by real fluidsynth (GeneralUser
GS soundfont) rather than additive synthesis. A five-minute render
therefore has bounded memory use rather than allocating the whole song as
Ruby Float arrays.

## Entrypoints

- `../dilla.rb`: stable MASTER-facing generator (`generate --style ...`).
- `dilla.rb`: the actual engine — arrangement, synthesis, source
  preparation, analysis, analog grading, mixing, mastering, playback, and
  the live `stream` command.

## Harmony — generated, not just looked up

`TRACK=generated` (plus `GEN_STYLE=`) drives real algorithmic composition
instead of picking from a fixed chord list:

- `functional` — weighted-random walk over tonic/predominant/dominant
  scale-degree harmony (same circulation Bach's chorales run on).
- `planing` — J Dilla-style parallel/scalar chord-quality motion
  (Donuts/Fantastic Vol. 2's chromatic descents), not functional
  resolution.
- `chromatic_mediant` — Flying Lotus-style root motion by thirds with
  occasional tritone substitution (per "Never Catch Me"'s chord analysis).
- `polytonal` — Aydin Esen-style polychord stacking (a second triad a
  tritone/major-2nd above the primary root).
- `negative_harmony` — Ernst Levy/Jacob Collier-style pitch reflection
  around a tonic/dominant axis.
- `neapolitan` — half-step/tritone-dominated root motion, deliberately
  avoiding fifth-based motion.

Every render also applies **pedal point** (the bass anchors on the
opening root for ~30% of chords while the upper voicing keeps moving) and
is arranged as a **fugue**: the (generated or looked-up) progression is
stated 2-3x as a hook, developed via a fresh generative walk from its last
chord, then the hook returns to close — never a flat loop, never
unstructured wandering. A **build-up** (rising loudness + brightness) hits
the final ~18% of every track, landing as the hook returns.

Selectable fixed/curated progressions (`TRACK=<name>`) are named by the
harmonic technique they demonstrate, not by artist/song — see
`CHORD_PROGRESSIONS`/`TRACK_PRESETS` in `dilla.rb`.

## Drums

- Kick: four-layer synthesis (sample + 42->150Hz pitch-drop sub + 150Hz
  body punch + broadband click transient), single-pass saturation.
- Every drum role (`feel: :organic`) generates a fresh, per-bar
  probabilistic pattern from position weights measured across the file's
  curated pattern data, instead of rotating a small fixed set — genuinely
  different every bar, minimum-spacing enforced so it never reads as a
  mistake.
- A polyrhythm layer (bar/3 spacing) runs independently of the main groove.
- Quintuplet swing (`quintuplet: true` in a preset): the beat divides into
  5 equal parts (3:2 ratio), the actual MPC3000 mechanism per *Dilla
  Time* (Charnas), not the standard 4/16th or 6/triplet swing math.

## Lead

A fluidsynth sawtooth voice (GM Lead 2) arpeggiates a single **leitmotif**
per piece (seeded from the opening chord) through real **motivic
development** — stated, inverted, reversed, augmented across the piece —
plus a quieter **call-and-response** answer voice on alternating phrases.
Delay + phaser for movement, not a static sequencer demo.

## Pads

Blends two fluidsynth voices per render: an electric-piano voice (Rhodes/
DX EP — J Dilla's actual keyboard) and a warm analog-pad voice (randomly
picked from the GM Pad 1-8 family — Prophet/Moog-adjacent, matching Flying
Lotus's Prophet 6/CS-60/Minimoog gear) — a different pair each render.

## Mix

Complementary EQ carving between the drum and harmonic buses (not just
level matching), sub-bass mono-summing below 120Hz for real-speaker
translation, continuous analog pitch/tempo drift, and a mood-darkening EQ
stage. Sonitex STX-1260 tape/analog emulation is on by default
(`SONITEX=heavy|classic|extreme|0`).

## Speech

`SPEAK=1` has MASTER's own TTS (`MASTER/bin/tts-worker`) talk continuously
over the track — pitched down, slowed, beat-synced tremolo, with
talk/pause dynamics (not flat constant chatter). Content is either the
built-in phrase bank or a local word-bank generator (no `faker` gem
dependency).

## Streaming

```sh
ruby dilla.rb stream [bars_per_track]
```

Non-stop playback, cycling `STREAM_TRACKS`, starting from a random
rotation position each launch. Checks its own file's mtime before every
track and `exec`s a fresh process if it changed — edits to `dilla.rb`
apply automatically between tracks, no manual restart needed. Every
progression explored is appended to `.dilla_progressions_log.txt`
(track, BPM, timestamp, chord names + note names + Hz) so nothing
generated is lost.

## Other commands

```sh
ruby MASTER/tools/dilla.rb generate --style neo-soul --output .master/media/neo-soul.mp3
ruby dilla.rb quality .master/media/neo-soul.mp3
ruby dilla.rb capabilities
BPM=84 BARS=16 TRACK=generated_planing ruby dilla.rb dilla /tmp/test.mp3 16
```

`quality` writes a reproducible mastering sidecar (integrated loudness,
true peak, loudness range, mono RMS, spectral balance, delivery warnings,
optional regression deltas against a prior report).

## Cleanup Rules

- Keep generated audio artifacts intentional and named.
- Do not add auto-installing scripts.
- Keep external sampling/downloading behind explicit commands in `dilla.rb`.
- Prefer MIDI or manifest outputs for reviewable generative experiments.
