# postpro

Film emulation for stills — MASTER's image-grading media tool. Entry point:
`STUDIO/postpro/postpro.rb`.

## Run

```sh
ruby STUDIO/postpro/postpro.rb --input in.jpg --output out.jpg --preset portrait
```

Run with no arguments for the interactive menu (presets, random effects, or a
custom JSON recipe). The non-interactive path above needs all three of
`--input`, `--output` and `--preset`.

This file said `MASTER/tools/postpro/postpro.rb` until 2026-07-30, five days
after the script moved to `studio/`. That is the same staleness that left the
script's own `require_relative "../lib/io/..."` pointing at a directory which
does not exist, so every invocation aborted with a LoadError from the move until
somebody tried to run it. Paths in documentation rot exactly the way paths in
code do, and neither announces it.

## Introspection

None of these process an image; all take a second or less.

```sh
ruby STUDIO/postpro/postpro.rb --vocab-check           # are the tables consistent?
ruby STUDIO/postpro/postpro.rb --list-presets          # every preset and its chain
ruby STUDIO/postpro/postpro.rb --list-stocks
ruby STUDIO/postpro/postpro.rb --list-lenses
ruby STUDIO/postpro/postpro.rb --describe-preset noir
ruby STUDIO/postpro/postpro.rb --export-lut cinematic --output cinematic.cube
ruby STUDIO/postpro/postpro.rb --css-filter portrait
ruby STUDIO/postpro/postpro.rb --capabilities
```

`--vocab-check` is the one to run after touching any table. It verifies that
every preset names an effect with an implementation, a stock/lens/print stock
that exists, and a stock with a row in every per-stock table its chain reads;
that every key a preset declares (`stops:`, `age:`, `lens:`, `print_stock:`,
`exposure_secs:`, `k1:`, `f_number:`) has a step in that chain to read it; that
every recipe-allowed effect is callable the way `recipe()` calls it; that every
H&D curve is monotonic; and that nothing is defined which neither a preset nor a
recipe can reach. Non-zero exit on a problem.

It exists because none of those failures raise. An effect name with no
implementation returned the image unchanged while the log reported the step as
done. Five presets declared a lens no chain applied. Every stock carried a
colour matrix nothing read. The failure mode of a table-driven pipeline is not a
crash — it is a picture that came out slightly wrong and a log that agrees with
the preset.

## Model

A preset is an ordered chain of effects plus the film it is shot on:

```ruby
noir: { fx: %w[optical_blur tonemap push_pull film_curve bleach_bypass desaturate shadow_lift grain],
        stock: :tri_x, temp: 5600, intensity: 0.90, stops: 2.0 },
```

Per-stock data lives in six tables keyed by the same symbol — `STOCKS` (grain
sigma, box speed, colour matrix, per-channel H&D curve), `GRAIN_CHAN_SCALE`,
`FILM_BASE`, `PUSH_RESPONSE`, `RECIPROCITY_SHIFT` and `C41_STOCKS`. A stock
missing from one of them does not fail; it quietly becomes a different stock,
which is why `--vocab-check` refuses a gap.

Grain rates film against its own box speed: at box speed a stock comes out at
its own sigma, and each stop of push costs sqrt(2) more grain. Cell size scales
with image width from a 2048 px reference so a newsletter hero and a 4k print
share an emulsion. The finishing pass uses the preset's stock and box speed,
not a second Portra-400 layer. `stock_matrix` normalises its rows so the matrix
does dye crosstalk and the H&D offsets do the colour cast, rather than both
doing cast.

A preset that sets `temp:` without a `spectral_temp` or `color_temp` step in
its chain is a `--vocab-check` failure — the same unread-key rule as `stops:`,
`lens:`, and `age:`. A Kelvin figure `--describe-preset` prints and the render
never applies is a lie, not a look.

## Which stock, and what for

`--list-stocks` prints names. What it cannot print is judgement, and this is the
one thing in this file that is not derivable from the tables — restored from
`pub2/postpro/postpro_README.md`, which had it and which nothing in pub4
carried forward.

The numbers below are read from `STOCKS` rather than copied from that file. Its
figures — "Portra 400, gamma 0.65, highlight rolloff 0.88" — belong to a
simpler model that no longer exists here: a stock is now a per-channel H&D curve
`[Dmin, Dmax, pivot, gamma]`, and Portra's gammas are 1.10/1.10/1.05. Bringing
the old values across would have imported a parameterisation the code stopped
using. The prose survives the model change; the constants do not.

Gamma is contrast, per R/G/B. Grain is the emulsion's own sigma, not a
percentage. ISO is box speed, which is what `push_pull` rates against.

| Stock | ISO | Grain | Gamma | Reach for it when |
|---|---|---|---|---|
| `kodak_portra` | 400 | 15 | 1.10 | Skin. The lowest contrast of the colour negatives here, which is why it flatters faces and why it is the default. |
| `fuji_pro400h` | 400 | 16 | 1.05 | Skin again, flatter still, cooler through the greens. The other half of the wedding-photography pair. |
| `kodak_ektar100` | 100 | 6 | 1.34 | Finest grain in the table and high contrast — landscape and product, where there is no face to protect. |
| `fuji_velvia` | 50 | 8 | 1.45 | The most contrast of anything here. Saturated slide film: landscape, never skin. |
| `ektachrome_100` | 100 | 10 | 1.30 | Slide film with Velvia's discipline and less of its violence. Cooler. |
| `kodachrome` | 64 | 12 | 1.42 | Reds and a notably low blue gamma (1.20 against 1.42 red) — the split is the look. Archival, mid-century. |
| `kodak_vision3` | 500 | 20 | 1.15 | Cinema negative, daylight. Wide latitude, made to be graded afterwards. |
| `kodak_vision3_50d` | 50 | 8 | 1.08 | The same family at box speed 50: clean, slow, bright exteriors. |
| `kodak_vision3_500t` | 500 | 20 | 1.18 | Tungsten-balanced. Interiors and night without a correction filter. |
| `cinestill_800t` | 800 | 22 | 1.20 | 500T with the remjet removed, so highlights bloom red. The most scatter in the table; halation is the point. |
| `tri_x` | 400 | 25 | 1.30 | The classic black-and-white. Prominent grain, hard contrast: street, reportage. |
| `ilford_hp5` | 400 | 22 | 1.22 | Tri-X's rival, softer. Kinder to a face than Tri-X is. |
| `ilford_delta3200` | 3200 | 38 | 1.08 | Grainiest and flattest by a distance. Available darkness — the grain is not a defect you are tolerating, it is the reason. |
| `polaroid_sx70` | — | — | — | Instant. Its character is in the frame and the dye, not the curve. |

Two things follow from the gamma column that are easy to get wrong. A stock with
high gamma will not flatter a portrait however good the light was, so
`fuji_velvia` on a face is a choice you have to mean. And the black-and-white
stocks carry equal gammas across R/G/B by definition, so a colour cast applied
before them is thrown away — put `spectral_temp` after the curve, or leave it
out of a monochrome chain entirely.

## Config

Reads `config.multimedia.postpro` from `master.json` (presets, defaults). There
is no `master.json` in the repo, so `CONFIG` is `{}` and every read of it takes
a built-in fallback — `--vocab-check` says so as a note rather than a problem.

Camera profiles load from `STUDIO/postpro/multimedia/camera_profiles`, and now
exist: **121 bodies across six vendors** (Canon, Sony, Nikon, Fujifilm, Leica,
Olympus), each a 3×3 sensor matrix recovered from a VSCO DCP archive. The pass
matches on EXIF Make/Model and applies the body's own colour response before
anything else touches the picture.

**On by default.** It was `if CONFIG["apply_camera_profile_first"]` against a
CONFIG that is always empty, pointed at a directory that had never existed —
fifty lines of matching and matrix application that had never once run, aimed at
data that was not there. Two inert halves, each making the other invisible.
Neither is inert now, and a default of off would have kept the data as
decorative as the code. It no-ops on anything without EXIF Make/Model, so
generated images are unaffected and photographs are corrected.

The same archive holds ten film stocks per body and **none of their emulation
data**: `ToneCurve`, `LookTable` and `HueSatDeltas` are empty in all 1,250
profiles, and the matrices distinguish only colour from black-and-white — Portra
400 and Fuji 400H are byte-identical for a given body. DCP matrices are sensor
calibration, not emulsion. Worth stating so nobody re-opens that tarball
expecting film curves.

## Callers

- `MASTER/web/app/services/image_presenter.rb` — web photo grading.
- Rails apps via `Pub4::DeployPaths#postpro_script` (newsletter heroes, TV
  thumbnails); see `RAILS` `Shared::NewsletterVisuals`, brgen `PostproJob`.
- `STUDIO/repligen/repligen.rb --postpro PRESET` hands a fresh generation
  straight here.

Invoked programmatically through `Master::Io::ScriptDispatch` (tool name
`"postpro"`), which resolves `STUDIO/postpro/postpro.rb` and runs it from the
tool's own directory. Natural-language routing goes through `Io::MediaIntent`
(`/postpro`); it is a slash-command tool, not an LLM-native one (see
`AGENTS.md`).

Move any future path references through `ScriptDispatch` / `DeployPaths` rather
than hardcoding the file location.
