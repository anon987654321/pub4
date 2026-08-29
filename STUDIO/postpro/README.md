# postpro

**Film is a physical process, and postpro models the process rather than
imitating the result.** It is the house grade for stills, and its entry point is
`STUDIO/postpro/postpro.rb`.

Give it `--input`, `--output` and `--preset` and it runs headless. Give it
nothing and it opens the interactive menu — presets, random effects, or a custom
JSON recipe. Call it positionally and you get the menu too, which in a script
reads as a hang, so the three flags are not optional in anything automated.

Check the path before you trust it. This file once named a script location five
days out of date, and the script's own `require_relative` pointed at a directory
the move had removed, so every invocation aborted with a LoadError until somebody
tried to run one. Paths in documentation rot exactly the way paths in code do,
and neither announces it.

### The check that catches what does not raise

`--vocab-check` is the one to run after touching any table, and it takes under a
second. It verifies that every preset names an effect with an implementation and
a stock, lens and print stock that exist; that a stock has a row in every
per-stock table its chain reads; that every key a preset declares — `stops:`,
`age:`, `lens:`, `print_stock:`, `exposure_secs:`, `k1:`, `f_number:` — has a
step in that chain that reads it; that every recipe-allowed effect is callable
the way `recipe()` calls it; that every H&D curve is monotonic; and that nothing
is defined which neither a preset nor a recipe can reach. It exits non-zero on a
problem.

It exists because none of those failures raise. An effect name with no
implementation returned the image unchanged while the log reported the step as
done. Five presets declared a lens no chain applied. Every stock carried a colour
matrix nothing read. The failure mode of a table-driven pipeline is not a crash.
It is a picture that came out slightly wrong and a log that agrees with the
preset.

The other introspection flags process no image and are equally cheap:
`--list-presets`, `--list-stocks`, `--list-lenses`, `--describe-preset`,
`--export-lut`, `--css-filter` and `--capabilities`.

### The model

A preset is an ordered chain of effects plus the film it is shot on — `noir`, for
instance, runs optical blur, tonemap, push-pull, film curve, bleach bypass,
desaturate, shadow lift and grain over `tri_x` at 5600 K, intensity 0.90, pushed
two stops.

Per-stock data lives in six tables keyed by the same symbol: `STOCKS`, carrying
grain sigma, box speed, colour matrix and per-channel H&D curve, then
`GRAIN_CHAN_SCALE`, `FILM_BASE`, `PUSH_RESPONSE`, `RECIPROCITY_SHIFT` and
`C41_STOCKS`. A stock missing from one of them does not fail. It quietly becomes
a different stock, which is why `--vocab-check` refuses a gap.

Grain rates film against its own box speed: at box speed a stock comes out at its
own sigma, and each stop of push costs sqrt(2) more grain. Cell size scales with
image width from a 2048 px reference, so a newsletter hero and a 4K print share
an emulsion. The finishing pass uses the preset's own stock and box speed rather
than a second Portra-400 layer. `stock_matrix` normalises its rows so the matrix
does dye crosstalk and the H&D offsets do the colour cast, instead of both doing
cast.

A preset that sets `temp:` without a `spectral_temp` or `color_temp` step in its
chain is a `--vocab-check` failure, under the same unread-key rule as `stops:`,
`lens:` and `age:`. A Kelvin figure `--describe-preset` prints and the render
never applies is a lie, not a look.

### Which stock, and what for

`--list-stocks` prints the names. What it cannot print is judgement, and this is
the one part of this file not derivable from the tables. The numbers here are
read from `STOCKS` rather than copied from the older document the prose came
from: a stock is now a per-channel H&D curve of Dmin, Dmax, pivot and gamma, and
the simpler parameterisation that document used no longer exists. The prose
survives a model change; the constants do not. Gamma is contrast, per channel.
Grain is the emulsion's own sigma, not a percentage. ISO is box speed, which is
what `push_pull` rates against.

For skin, reach for `kodak_portra` — ISO 400, grain 15, gamma 1.10, the lowest
contrast of the colour negatives here, which is why it flatters faces and why it
is the default — or `fuji_pro400h` at 400/16/1.05, flatter still and cooler
through the greens. They are the two halves of the wedding-photography pair.

For landscape and product, where there is no face to protect, `kodak_ektar100`
at 100/6/1.34 is the finest grain in the table with high contrast, and
`fuji_velvia` at 50/8/1.45 has the most contrast of anything here — saturated
slide film, never skin. `ektachrome_100` at 100/10/1.30 has Velvia's discipline
with less of its violence, and runs cooler. `kodachrome` at 64/12/1.42 is for
reds and for archival mid-century work; its blue gamma is notably low, 1.20
against 1.42 red, and that split is the look.

The cinema negatives are made to be graded afterwards. `kodak_vision3` is
500/20/1.15, daylight, with wide latitude. `kodak_vision3_50d` at 50/8/1.08 is
the same family at box speed 50 — clean, slow, bright exteriors.
`kodak_vision3_500t` at 500/20/1.18 is tungsten-balanced, for interiors and night
without a correction filter. `cinestill_800t` at 800/22/1.20 is 500T with the
remjet removed, so highlights bloom red; it scatters more than anything else in
the table, and halation is the point of it.

In black and white, `tri_x` at 400/25/1.30 is the classic — prominent grain, hard
contrast, street and reportage. `ilford_hp5` at 400/22/1.22 is its rival and
softer, kinder to a face. `ilford_delta3200` at 3200/38/1.08 is the grainiest and
flattest by a distance, for available darkness, where the grain is the reason
rather than something you tolerate. `polaroid_sx70` carries no ISO, grain or
gamma at all: its character is in the frame and the dye, not the curve.

Two things follow from those gamma figures that are easy to get wrong. A
high-gamma stock does not flatter a portrait however good the light was, so
`fuji_velvia` on a face is a choice you have to mean. And the black-and-white
stocks carry equal gammas across all three channels by definition, so a colour
cast applied before them is thrown away — put `spectral_temp` after the curve, or
leave it out of a monochrome chain entirely.

### Config, and the camera bodies

postpro reads `config.multimedia.postpro` from `master.json` for presets and
defaults. There is no `master.json` in the repo, so `CONFIG` is empty and every
read of it takes a built-in fallback. `--vocab-check` reports that as a note
rather than a problem.

Camera profiles load from `STUDIO/postpro/multimedia/camera_profiles`, and they
exist: 121 bodies across Canon, Sony, Nikon, Fujifilm, Leica and Olympus, each a
3×3 sensor matrix recovered from a VSCO DCP archive. The pass matches on EXIF
Make and Model and applies the body's own colour response before anything else
touches the picture.

It is on by default, and that is deliberate. The pass used to be guarded by
`CONFIG["apply_camera_profile_first"]` against a CONFIG that is always empty, and
pointed at a directory that had never existed — fifty lines of matching and
matrix application that had never once run, aimed at data that was not there. Two
inert halves, each making the other invisible. A default of off would have kept
the data as decorative as the code. The pass no-ops on anything without EXIF Make
and Model, so generated images are unaffected and photographs are corrected.

The same archive holds ten film stocks per body and none of their emulation data.
`ToneCurve`, `LookTable` and `HueSatDeltas` are empty in all 1,250 profiles, and
the matrices distinguish only colour from black and white — Portra 400 and Fuji
400H are byte-identical for a given body. DCP matrices are sensor calibration,
not emulsion. It is worth stating plainly so nobody re-opens that tarball
expecting film curves.

### Who calls it

`MASTER/web/app/services/image_presenter.rb` grades web photos through it. The
Rails apps reach it through `Pub4::DeployPaths#postpro_script` for newsletter
heroes and TV thumbnails, by way of `Shared::NewsletterVisuals` and brgen's
`PostproJob`. `STUDIO/repligen/repligen.rb --postpro PRESET` hands a fresh
generation straight here.

Programmatic invocation goes through `Master::Io::ScriptDispatch` under the tool
name `postpro`, which resolves the script and runs it from the tool's own
directory. Natural-language routing goes through `Io::MediaIntent` as `/postpro`;
it is a slash-command tool rather than an LLM-native one, which `AGENTS.md`
explains. Route any new path reference through `ScriptDispatch` or `DeployPaths`
instead of hardcoding the file location.

### Running it

```sh
ruby STUDIO/postpro/postpro.rb --input in.jpg --output out.jpg --preset portrait
ruby STUDIO/postpro/postpro.rb --vocab-check          # are the tables consistent?
ruby STUDIO/postpro/postpro.rb --list-presets         # every preset and its chain
ruby STUDIO/postpro/postpro.rb --list-stocks
ruby STUDIO/postpro/postpro.rb --list-lenses
ruby STUDIO/postpro/postpro.rb --describe-preset noir
ruby STUDIO/postpro/postpro.rb --export-lut cinematic --output cinematic.cube
ruby STUDIO/postpro/postpro.rb --css-filter portrait
ruby STUDIO/postpro/postpro.rb --capabilities
```
