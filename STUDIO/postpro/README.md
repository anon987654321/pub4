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

## Config

Reads `config.multimedia.postpro` from `master.json` (presets, defaults).
Optional camera profiles load from `STUDIO/postpro/multimedia/camera_profiles`;
that directory does not exist in the repo today, and its absence is a warning
rather than an error.

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
