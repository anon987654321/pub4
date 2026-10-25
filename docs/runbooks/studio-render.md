# Runbook: Dilla render and postpro

Run on the target machine with the supported audio stack. Preserve existing
takes; do not overwrite an existing dilla.wav, dilla_norsk.wav, video or
render output as a side effect of a proof run. Choose a fresh output directory
using the engine’s documented output option.

    ruby OPENBSD/bin/evidence studio-tests -- sh -c 'cd STUDIO && rake test'

Generate the requested English and Norwegian renders, then inspect the files
and any live/postpro/three.js output with the current documented Dilla entry
point. If a tool requires installation, install dependencies only through its
documented bootstrap command; do not turn a check into an implicit package
install. Record the seed, BPM, source digest, engine version and output path.

## Objective acceptance

Record and verify:

- WAV/MP4 integrity, channels/sample rate, duration and expected section count;
- tempo against the requested 92 BPM pocket, noting that duration alone does
  not prove tempo or swing;
- peak, true peak if available, integrated loudness and clipping;
- deterministic seed behavior, overwrite/refusal behavior and failure cleanup;
- live playback, postpro/three.js output and audio-analysis report;
- kick/snare/hat balance, restrained effects/lead and overall musical quality,
  distinguishing objective measurements from human judgement.

Use operator-supplied reference material only through authorized paths.
Attach the measurement JSON and reviewed screenshots/audio metadata; do not
commit large generated audio or private source material merely to prove a
render occurred. A successful process exit without inspection is not quality
evidence. The seven historical dilla_test.rb failures remain open until the
fast/full suites are rerun on the current commit.
