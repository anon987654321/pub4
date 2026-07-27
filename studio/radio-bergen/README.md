# pub4 audio restore

This directory restores the useful parts of `pub2` without copying generated
MP3 binaries into the repo.

## What came back

- AKMD / Radio Bergen mastering chain.
- Track manifest format.
- Canvas/Web Audio visualizer controller.
- Explicit production cautions around external media.

## Mastering chain

`akmd_mastering_chain.rb` wraps the documented pub2 FFmpeg chain:

1. 60 Hz highpass.
2. 11.5 kHz lowpass.
3. EQ boost at 80 Hz.
4. EQ boost at 200 Hz.
5. EQ cut at 8 kHz.
6. Gentle compression.
7. Tanh soft clipping.
8. Pre-limiter volume lift.
9. Final limiter at broadcast-safe level.

Run:

```sh
ruby OPENBSD/audio/akmd_mastering_chain.rb input.wav output.mp3
```

Optional:

```sh
ruby OPENBSD/audio/akmd_mastering_chain.rb input.wav output.mp3 --bitrate 192k
```

## Track manifest

`radio_bergen_tracks.yml` is data only. It does not assert licensing or host
media. Production code must check:

## Playlist learnings (study pipeline)

`radio_bergen_study.rb` reads the full playlist.brgen.no manifest (local AKMD
MP3 metadata + YouTube reference rows), maps each artist to Dilla producer DNA,
and writes `radio_bergen_sonic.yml` for the stream engine.

```sh
ruby MASTER/tools/audio/radio_bergen_study.rb
ruby studio/dilla/dilla.rb radio-bergen-study
```

With local audio files on disk (optional ffprobe analysis):

```sh
ruby MASTER/tools/audio/radio_bergen_study.rb --audio-root /path/to/audio
```

Dilla stream uses `RADIO_BERGEN=1` (default) to bias `TRACK` rotation from
`stream_rotation_weights` in the learnings file.

Production code must still check:

- source ownership
- public performance rights
- takedown process
- cache policy
- attribution

## Visualizer

`radio_bergen_visualizer_controller.js` is a smaller extraction of the pub2
Radio Bergen idea:

- no external player dependency
- local audio element first
- Web Audio analyser
- reduced-motion aware
- canvas tunnel/stars
- safe teardown on disconnect

Use it as a Stimulus controller or standalone ES module seed.

## Do not restore

- generated MP3s
- iframe autoplay as core playback
- broad external track embeds
- monolithic one-file UI
