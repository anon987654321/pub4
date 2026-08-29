# Handoff: `loop.wav`, rendered repeatably

Temporary. Delete this file when the work lands.

## What was asked

dilla renders a full `loop.wav`, repeatably. Neither half exists yet, and the
two halves are independent — read them separately.

## Where dilla is now

The engine was 81 files under `lib/engine/` required in a hand-pinned order.
That order was load-bearing, so they are concatenated into `dilla.rb` in it.

```
ruby files   129 -> 48        dilla.rb   1158 -> 34310 lines
lib/engine/  gone             archive/   gone (1485 lines, unreferenced)
```

`DillaSources` in `lib/engine_sources.rb` is still the one definition of the
corpus; it is now `dilla.rb` plus the 41 support modules in `lib/*.rb`.
`STUDIO/gate.rb` guards the split coming back — `check_growth` fails if
`dilla/lib/engine/` reappears, and `DILLA_SUPPORT_CEILING = 41` caps the support
modules that could grow in its place.

Stage two — folding the 41 `lib/*.rb` into `dilla.rb` as well — has not been
done. Fourteen of them use `__dir__` or `__FILE__`, and those shift by one
directory level when the file moves, which is the exact bug that broke three
tests during stage one. Do that deliberately or not at all.

## Half one: `loop.wav` is the only audio file in `dilla/` root

That is the operator's rule, and it is why the root is empty right now.
`RELEASE.mp3`, `RELEASE.320kbps.original.mp3`, `demo.mp3`, `demo.wav` and
`demo_current.mp3` were deleted deliberately to clear it. None of them were in
git -- audio is gitignored here -- so they are gone rather than recoverable,
and that was the intent. The sidecars beside them are tracked and survive:
`RELEASE.mp3.dilla`, `demo.mp3.dilla` and `demo.mp3.quality.json` are in git
and hold the recipes.

So `loop.wav` is not one more output among several. It replaces them, and
anything that writes another mp3 or wav into `dilla/` root is now wrong.
`STUDIO/dilla/.gitignore` already grew `demo.mp3` and `demo.mp3.dilla` on the
way to this; `loop.wav` needs the same treatment, and the older render names
should stop being written at all rather than merely ignored.

Nothing renders a file by that name yet. The name is currently an *input*
convention: each chopped source sits at `samples/<slug>/loop.wav` with a row in
`samples/chopped/loops.json`, and `TRACK_SAMPLE_LOOPS` reads them. That does
not collide -- those are under `samples/`, not root -- but do not confuse the
two when grepping.

Decide the shape before writing it: how many bars, whether it must be seamless
at the loop point, and whether it is a new CLI verb or what the existing render
writes by default. `BARS` already exists as a knob. The nearest existing shapes
are `dilla demo` and the stem export that writes `<name>_stems/`.

## Half two: repeatability, and it is close

The engine is already deterministic by design. Measured over `dilla.rb`:

```
Random.new(seed)   62 sites
obj.rand(          91 sites
bare Kernel#rand    3 sites      <- the whole problem
srand               0 sites
```

`RENDER_SEED` is the operator's pin and `render_pinned?` (`dilla.rb:1680`)
reads it. Four sites escape it:

- `dilla.rb:2998` — `Random.new(seed || @render_seed || rand(1_000_000))`.
  The fallback draws from the unseeded global RNG, so an unpinned render is
  unreproducible even after the fact. Recording the drawn value is what the
  sidecar's `seed_was: "drawn and recorded"` is for; check it actually covers
  this one.
- `lib/seed_providers.rb:30` — same fallback shape in `render_seed`.
- `dilla.rb:15796` — `continuous_speech_text(talk_len, seed: idx + rand(100_000))`.
  Audio-affecting.
- `dilla.rb:12418` — a temp filename. Harmless; leave it.

**`SEED_TEXT` is broken and this is the one to fix first.**
`lib/seed_providers.rb:29` derives a seed as `text.hash.abs % 1_000_000`, and
Ruby randomises `String#hash` per process. Three runs of the same text:

```
479615   227034   205911
```

So `SEED_TEXT` names a seed that changes every run, which is the opposite of
what it exists for. `Digest::SHA256.hexdigest(text).to_i(16)` is stable across
processes; `text.hash` is not. `apply_text_seed!` at line 33 derives `SWING` and
`BPM` from the same unstable hash, so those move too.

Do not assume seeding the global RNG makes renders bit-identical. A previous
measurement found roughly 0.012 dB RMS spread run to run with `RENDER_SEED`
pinned, and the residue may be ffmpeg rather than Ruby. A/B with interleaved
distributions rather than comparing hashes.

## Verifying

```
cd STUDIO && rake gate        # parse, inventory, entry points boot
cd STUDIO && rake test:dilla  # 282 runs
cd STUDIO && rake isolation   # tests that only pass in company
```

`rake isolation` matters here. `test_provenance_separates_what_the_operator_pinned_from_what_the_engine_filled`
passes alone and fails in the suite — an order-dependent leak, still open, and
it renders audio to a tmpdir as part of its check.

Two other `test:dilla` failures are known and not from the consolidation. The
six `sonmi451_probe_*` loops with no preset are local crate state: the slugs
appear only in gitignored `scratch/`, so that test may be measuring one machine
rather than the repo.

## Traps

Renders are irreplaceable. Seeds and performers rotate per run and renders are
gitignored, so never render over a take that matters. Never change a
rendered-sound default on your own judgement — the defaults live in
`lib/engine/style_defaults.rb`, now inline in `dilla.rb`, and the recent ones
were operator decisions recorded in `e65f717be` and `0a77242dd`.

Drums default off. `drum_policy.rb`'s `ENV.fetch("DRUMS", "0") != "0"` is the
switch, and a test that asserts kicks exist without setting it measures the
default rather than its own subject.

Never pitch-shift rap vocals. Time-stretch instead.
