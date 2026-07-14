# Dilla Lab

`MASTER/tools/dilla` is a full-length generative production engine: cyclic MPC microtiming, sampled/synthesized drums, voice-led harmony, bass, melodic chops, evolving song sections, analog degradation, mix buses, and mastered delivery. The normal MASTER path renders a 112-bar radio-length track under `.master/media/`; stems and short diagnostic renders are supporting tools, not the product.

The drum and transient-tone buses stream fixed-size PCM chunks into FFmpeg, while the low-passed pad bed is synthesized by FFmpeg at an efficient half-rate before the analog chain. A five-minute render therefore has bounded memory use rather than allocating the whole song as Ruby Float arrays.

## Entrypoints

- `../dilla.rb`: stable MASTER-facing generator for Dilla, FlyLo, baroque/Bach-informed, neo-soul, and jazz tracks.
- `dilla.rb`: production engine for arrangement, synthesis, source preparation, analysis, analog grading, mixing, mastering, and playback.
- `dilla_hiphop.rb`: ffmpeg synthesis of an MPC-style 86 BPM beat.
- `electronium.rb`: safe MIDI-only Raymond Scott / J Dilla Electronium generator inspired by the referenced gist. It requires `midilib` but does not auto-install gems, fetch the network, or shell out to render audio.
- `dilla_lab.html`: browser lab for microtimed pattern sketching.
- `play.html`: static player surface.

## Electronium

Generate a complete track through the same entrypoint MASTER uses:

```sh
ruby MASTER/tools/dilla.rb generate --style neo-soul --output .master/media/neo-soul.mp3
ruby MASTER/tools/dilla.rb generate --style baroque --bars 112 --output .master/media/baroque.mp3
ruby MASTER/tools/dilla/dilla.rb quality .master/media/neo-soul.mp3
ruby MASTER/tools/dilla/dilla.rb capabilities
```

The style is musical configuration, not a filename label. `baroque` uses an extended circle-of-fifths sequence with functional dominant resolution; `flylo` uses chromatic-mediant/tritone movement and a more displaced Madlib-derived pocket; `neo-soul` uses voice-led ninth chords and a dub-chamber analog chain. Every default render includes intro, groove, breakdown, build, peak cycles, outro, Sonitex treatment, an analog chain, an EBU R128 delivery target of -14 LUFS, and a -1 dBTP peak guard.

Generate an Electronium MIDI file:

```sh
ruby MASTER/tools/dilla/electronium.rb MASTER/tools/dilla/dilla_electronium.mid
```

Optional knobs:

```sh
BPM=84 BARS=16 ruby MASTER/tools/dilla/electronium.rb /tmp/dilla.mid
```

The gist at `https://gist.github.com/anon987654321/3831126ddcbc401c10b6c73435f776fe` contains two source sketches, `dilla_deepseek.rb` and `dilla_glm.rb`. The repo version keeps their core idea, but removes automatic dependency installation and renderer shell commands so the generator is predictable in deploy and audit contexts.

`quality` writes a reproducible mastering sidecar containing integrated loudness, true peak, loudness range, mono RMS, three-band spectral balance, delivery warnings, and optional regression deltas against a prior report.

## Cleanup Rules

- Keep generated audio artifacts intentional and named.
- Do not add auto-installing scripts.
- Keep external sampling/downloading behind explicit commands in `dilla.rb`.
- Prefer MIDI or manifest outputs for reviewable generative experiments.
