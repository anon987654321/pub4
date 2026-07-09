# Dilla Lab

`OPERATOR/dilla` is a small audio lab for Dilla-inspired groove sketches, sample cleanup, stem handling, and local render experiments.

## Entrypoints

- `dilla.rb`: main command surface for scan, source capture, stem separation, rhythm/chord study, render, cleanup, grading, and playback helpers.
- `dilla_hiphop.rb`: ffmpeg synthesis of an MPC-style 86 BPM beat.
- `electronium.rb`: safe MIDI-only Raymond Scott / J Dilla Electronium generator inspired by the referenced gist. It requires `midilib` but does not auto-install gems, fetch the network, or shell out to render audio.
- `dilla_lab.html`: browser lab for microtimed pattern sketching.
- `play.html`: static player surface.

## Electronium

Generate a MIDI file:

```sh
ruby OPERATOR/dilla/electronium.rb OPERATOR/dilla/dilla_electronium.mid
```

Optional knobs:

```sh
BPM=84 BARS=16 ruby OPERATOR/dilla/electronium.rb /tmp/dilla.mid
```

The gist at `https://gist.github.com/anon987654321/3831126ddcbc401c10b6c73435f776fe` contains two source sketches, `dilla_deepseek.rb` and `dilla_glm.rb`. The repo version keeps their core idea, but removes automatic dependency installation and renderer shell commands so the generator is predictable in deploy and audit contexts.

## Cleanup Rules

- Keep generated audio artifacts intentional and named.
- Do not add auto-installing scripts.
- Keep external sampling/downloading behind explicit commands in `dilla.rb`.
- Prefer MIDI or manifest outputs for reviewable generative experiments.
