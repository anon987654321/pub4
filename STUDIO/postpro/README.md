# postpro

Historical source and behavioral decisions from `pub`, `pub2`, `pub3` and the Git history of `pub4` are indexed in [ARCHAEOLOGY.md](./ARCHAEOLOGY.md). It distinguishes restored effects from intentionally retired mechanisms.

Startup diagnostics, dependency probing and the explicit opt-in dependency-installation path live in `bootstrap.rb`; optional per-effect texture/contrast diagnostics live in `explain.rb`. Loading the entrypoint is observational; `rake postpro:bootstrap` is the intentional installation command.

**Film is a physical process, and postpro models the process rather than imitating the
result.** A filter is a lookup table with an opinion. This is an emulsion: crystals with a
size and a statistics, a base that reflects light back into the layer it came through, a
curve that spends contrast instead of adding it, and a print stock after that. It is the house grade for stills and bounded, constant-rate MP4 clips. Its entry point is
`STUDIO/postpro/postpro.rb`; the video path uses the same grade in-process under explicit frame,
pixel, temporary-storage and runtime budgets. Variable-frame-rate and display-rotated inputs are
refused rather than silently retimed; odd dimensions are rejected rather than cropped or resized.
See [the video archaeology record](./ARCHAEOLOGY.md).

Give it `--input`, `--output` and `--preset` and it grades one image headless. Give it bare
paths and each is a subject: an image goes through ten random takes, a directory gives a
few random picks from it, and a path that is neither is named and refuses the whole batch
before anything renders. Every render lands in the folder of its source photograph, inside
the checkout or out of it; the root `.gitignore` keeps `postpro_*` renders out of git
wherever they land. Give it nothing and it asks what to grade.
The command `postpro.rb --help` lists every flag. `--capabilities` reports the analogue
direction catalogue and its readiness state; a catalogue entry is not a promise that the
corresponding effect is implemented or enabled on this machine.

The code spans several files. The file `postpro.rb` is the entry point: it boots, runs the
early modes and loads `lib/`, whose files hold the grade, the presets, the film tables and the
command line, one subject per file in the load order `POSTPRO_LIB` names. Video is split across
`motion.rb` (the grade contract and CLI) and `motion_process.rb` (bounded frame IO and child
processes), so neither file becomes another entrypoint monolith. `--vocab-check` reads
`postpro.rb`, `uncanny.rb`, `motion.rb`, `motion_process.rb` and every `lib/` file as one source.
`legacy_effects.rb` holds creative effects recovered from the older `pub/postpro` line, and
`LEGACY_RESTORE.md` records which of them already had current equivalents. The file `dilla_analog.rb` translates mechanisms
from dilla's analog chains into still images, so that temporal wow and flutter become spatial
registration error. The file `uncanny.rb` measures whether a picture looks rendered,
`rescue.rb` diagnoses a bad photograph, `frame_set.rb` reads a folder as a set, and `depth.rb`
supplies a real depth map when its model is installed.

The file `constitution.rb` is the boundary where MASTER's laws
become image-generation invariants, `analog_capabilities.rb` backs `--capabilities`, and
`camera_profiles.json` carries the sensor data. Its 200 stable catalogue entries describe
intended analogue directions. Entries remain `unverified` with a null `enabled` value until a
concrete code path and regression test establish readiness; the report's `catalog_complete`
means the inventory is present, while `complete` means all reported directions are verified
and enabled. These are separate questions by design. A log file named `postpro.log` also sits
in the folder; it is output, and git should not carry it.


## Restored historical creative vocabulary

The `pub` v12.9/v13.3.14 and `pub2` v14.2.0 generations are preserved as a behavioral lineage, not as competing runtimes. Their 29 named creative effects are all accounted for: five already had current equivalents (`light_leaks`, `lens_distortion`, `bleach_bypass`, `day_for_night`, `chromatic_aberration`); the other 24 are implemented through `legacy_effects.rb` and the current dispatcher. The restored names are `film_grain`, `film_halation`, `bloom_effect`, `cross_process`, `golden_hour_glow`, `lomo`, `sepia`, `teal_and_orange`, `anamorphic_simulation`, `vhs_degrade`, `color_fade`, `soft_focus`, `double_exposure`, `polaroid_frame`, `tape_degradation`, `frame_distortion`, `super8_flicker`, `cinemascope_bars`, `halftone_print`, `film_scratches`, `film_stock_emulation`, `sprocket_holes`, `lens_flare` and `glitch`. See [LEGACY_RESTORE.md](./LEGACY_RESTORE.md) for the full mapping and [ARCHAEOLOGY.md](./ARCHAEOLOGY.md) for the repository-by-repository source trail.

The old interactive workflow is retained as an operating concept: professional/experimental intensity lanes, random variations, 1–5 effect chains, recursive batch selection, custom JSON recipes, retries, progress and aggregate statistics. In the current engine these responsibilities are deliberately split between named presets, bounded `--random`/`--rough`/`--heavy` chains, checked recipes, batch processing, per-variation failure reporting and provenance sidecars. The historical prompt flow and its old retry/bootstrap code are not reintroduced: loading Postpro stays observational, dependency installation stays explicit, and every recipe still resolves through the one measured grade dispatcher.

The `pub2` 14.2 preset vocabulary (Portrait, Landscape, Street and Blockbuster), Repligen handoff, Portra/Vision3/Velvia/Tri-X looks, camera-profile correction, skin protection, highlight shoulder, micro-contrast and film grain are all represented in the current preset, stock, profile and effect systems. Historical parameter examples are not treated as calibrated physical measurements; current stock tables and measured implementations remain authoritative.

## The checks that catch what does not raise

Run `--vocab-check` after touching a preset, an effect dispatch arm, a stock table, or a recipe
adapter. The check uses Prism's Ruby AST rather than stopping at the first textual `end`:
nested blocks cannot truncate method bodies, and comments or strings cannot masquerade as
executable effects or calls. It checks that every preset step has a real `case fx` arm; stocks,
print stocks and lenses exist and remain reachable; every stock has the required per-stock
table rows; every film curve is monotonic; recipe adapters match callable effects; and effects
are reachable from a preset or a recipe.

Preset fields have a closed vocabulary. Built-in fields and `iso` are explicit; every other
declared field must have an effect-reader contract. For each declared reader, the checker
proves that the corresponding `case fx` arm passes that value into the matching effect call.
Merely mentioning `p[:temp]` in a comment, string, disconnected expression, or neighboring
effect arm does not satisfy the contract. It also follows executable call paths from every
rendering entry point to `apply_finishing_grain`, then runs a tiny in-memory 8×8 probe through
representative colour, monochrome and print presets to catch failures that table inspection
cannot see. A problem produces a non-zero result.

These guards exist because table-driven failures rarely raise by themselves: an effect with no
implementation once returned the input unchanged while the log reported the step as done, and a
temperature that `--describe-preset` printed but no step applied was a lie and not a look. A
historical run found twenty key-reader gaps across the recovered presets; those preset chains
were subsequently repaired. That historical count is not current verification. The live
`--vocab-check` and pinned Ruby/libvips regression suites still need to pass before the current
vocabulary or rendered behavior can be called clean.

The table/list flags `--list-presets`, `--list-stocks`, `--list-lenses` and
`--describe-preset` do not need an input photo. `--fit-grain` measures an image, while
`--export-lut` builds a LUT and `--css-filter` emits a CSS approximation.

## The model

A preset is an ordered chain of effects plus the film it is shot on. Per-stock data lives in
several tables keyed by the same symbol: `STOCKS`, which carries granularity, box speed, colour
matrix and the per-channel characteristic curve, then `GRAIN_CHAN_SCALE`, `FILM_BASE`,
`PUSH_RESPONSE`, `RECIPROCITY_SHIFT` and `C41_STOCKS`. A stock missing from one table does not
fail; it quietly becomes a different stock, which is why the vocabulary check refuses a gap.
The matrix of each stock is normalised so that it does dye crosstalk and the curve offsets do
the colour cast, and not both doing the cast.

The fourteen stocks are Kodak Portra, Vision3 in three speeds, CineStill 800T, Ektachrome,
Velvia, Tri-X, Kodachrome, Ilford HP5 and Delta 3200, Kodak Ektar, Fuji Pro 400H and the
Polaroid SX-70. For skin, Portra and Pro 400H are the low-contrast pair, and a high-contrast
slide stock on a face is a choice you have to mean. The black-and-white stocks carry equal
gamma across all three channels, so a colour cast applied before them is thrown away; put the
colour temperature step after the curve or leave it out of a monochrome chain.

## Grain, halation and the tone scale

Grain is a Boolean model. Silver halide crystals are disks dropped by a Poisson process whose
density follows the local grey level, and the developed picture is that binary field filtered
by the observer. The crystal field is generated, clumped, made slightly anisotropic along the
film transport, blurred, and then normalised by its own measured deviation, so whatever the
filter removes the measurement puts back.

Chroma grain is correlated with luma grain because
one crystal layer shadows the next. The grain figure of a stock is its peak luma deviation in
eight-bit levels at mid-grey, a quantity an instrument can check, and `--fit-grain` is that
instrument: point it at a flat scan and it reports the deviation per tone and the crystal size
that implies. Treat its figures as a floor, since its residual is a high-pass and the coarsest
octave goes out with the picture. Rated film keeps its own box speed, each stop of push costs
more, cell size scales with image width, and the finishing grain pass stands down for any
chain that already grains itself.

Every graded picture then passes through a tone anchor before its last grain. Stacked lifts leave
the darkest pixel at fifteen percent grey and the frame reads as milk, so the anchor stretches
the picture's own 0.5th and 99.5th luma percentiles to a printed black and white with one gain on
all three bands, which holds hue, and bends the midtones with a gentle S-curve.
`POSTPRO_ANCHOR=0` returns the unanchored grade.

Halation is a ring. Light that passes through the emulsion reflects off the rear of the base
and re-exposes an annulus around a highlight, not a halo centred on it. The radii differ per
channel because red penetrates furthest, which is why CineStill blooms red.

The `tonemap` effect offers five curves: the ACES fit, Hable, Hejl-Burgess-Dawson, AgX and the
ACES 2 tone scale. AgX rotates into narrower primaries before the sigmoid so that a clipping
channel does not drag hue with it. A preset chooses with `tonemap:` and receives the ACES 2
scale if it says nothing.

## Light and depth

A grade cannot move a shadow to the other side of a nose. The `relight` effect splits the
picture into illumination and reflectance, with a heavy blur of luminance standing for the
light, then puts the light back differently and leaves the surface alone. The correction rides
as a bounded ratio on all three channels, so texture, grain and hue survive. The `aerial_depth`
effect applies the oldest depth cue in painting: distance costs contrast and saturation and
cools the colour. Without a depth map it estimates nearness from local sharpness, a proxy that
will read a sharp cloud as near.

When the `onnxruntime` and `numo-narray` gems and the model weights are present, `depth.rb`
runs Depth Anything V2 small locally and both effects use its map instead. The weights are
fetched out of band into `STUDIO/postpro/models/depth/`, never committed, and each frame's
plane is cached there. That directory does not exist on a fresh checkout. Without the gems or
the weights everything falls back to the proxies, with one quiet log line.

The weights are the fp16 export of `onnx-community/depth-anything-v2-small-ONNX` (Apache-2.0),
a 180 KB graph and 50 MB of external data; the fetch command is under Commands below.

A first estimate takes about twelve seconds a frame on a laptop CPU; later takes of the same
frame read the cached plane. onnxruntime aborts in its native teardown at exit on macOS, so a
command-line run that loaded the model leaves by `exit!` with its own status. `POSTPRO_DEPTH=0`
keeps the proxies, and the test suites set it.

## Bounded video grading

A short, constant-rate clip can use the house grade without launching a new Ruby process for
every frame:

\`ruby STUDIO/postpro/postpro.rb --video input.mp4 --output graded.mp4 --preset portrait\`

The output contract is MP4. The reader probes the streams, preserves rational frame rates, and
refuses ambiguous/variable-rate inputs because silently normalising their timestamps would
change the edit. Per-frame presentation timestamps are read from ffprobe JSON rather than CSV:
Every frame must have a finite presentation timestamp; missing values and numeric overflow such as `1e999` are inconclusive input, not usable timing evidence. H.264 side-data can be appended to the first CSV timestamp line and otherwise make a valid frame
look missing. The focused motion tests include that side-data shape. Audio is copied instead of re-encoded. Grain moves deterministically by frame
by default; `--grain-hold` pins it for a scanned-print texture. Work is bounded before decoding
(600 frames, 500 million pixel-frames, a 300-second budget and a 1 GB graded-frame spool by
default); `POSTPRO_VIDEO_MAX_FRAMES`, `POSTPRO_VIDEO_MAX_PIXELS`,
`POSTPRO_VIDEO_MAX_SECONDS`, `POSTPRO_VIDEO_MAX_TEMP_BYTES` and
`POSTPRO_VIDEO_SECONDS_PER_FRAME` allow a validated operator adjustment within hard maxima.
The time estimate is a preflight estimate, not a performance claim. Runtime is checked between
frames and during ffmpeg decode/mux; a single native libvips frame operation cannot be forcibly
interrupted. The video and `.mp4.json` sidecar are published with same-directory atomic links
only after successful muxing. The sidecar records source/output SHA-256, preset, seed/grain,
frame dimensions/rate/count, audio-copy status and measured duration/temporary bytes. The focused test suite is
`cd STUDIO && rake test:motion`.

## Random chains and heavy mode

A bare path, or `--random` with a path (`--random photo.jpg` or `--random --count 10
photo.jpg`), renders several variations of that photograph, each through its own chain, with a
JSON sidecar naming every effect, the seed, the take number, the look and the lane. `--random`
with no path draws from the downloads folder instead. Several paths on one line get one family
each. A take is named for what it is, in draw order:
`postpro_photo_03_neon_night_artistic_analog_v1.jpg`. A family of two or more also gets
`postpro_photo_contact.jpg`, every take tiled with its number and look beneath it, so the
family is judged side by side; `POSTPRO_CONTACT=0` leaves it out. The media, sidecars and
contact sheet always sit beside the source photograph. A new run
first removes the earlier renders of the same source, since renders are replaceable. If a
generated name still exists, Postpro preserves it and chooses a timestamped sibling.

A take is graded exactly as a preset is. Every step, drawn or from a preset, goes through one
dispatch, `grade_step`, which mixes each effect down from the look intensity by its own
factor, scales the subtractive steps by what the source arrived with, and runs the chain in
float with one clamp at the end. Random takes used to call each effect at its raw number with
none of that, and measured on nine photographs (2026-10-27) 69% of them lost the source's
colour or shapes, against 10% of the lighter takes.

Light takes are the default: short chains grown from the presets, ten of them. `--heavy` (or
`POSTPRO_HEAVY=1`) starts each take from a named look instead (noir, neon night, Technicolor,
cross process, infrared and a dozen more), runs that look as its preset does, with its own
stops, exposure time, print stock and lens, and adds at most a few supporting steps, ten in
all. No two takes of a heavy run share a look, and no two share a stock while an unused one
remains.

Every take is then judged against its source on what a colourist protects. It must keep the
source's shapes, its black and white points and at least half its tonal spread. Colour may
move within the look's own budget: how far colourfulness may rise, how far neutral greys may
be tinted, and how far skin may turn in hue, held tightest. The default budgets sit at the
90th percentile of measured light takes, and the palette looks (day for night, cross process,
the night stocks) get more. A take that drains colour on purpose is judged on shapes and
tones alone. Every bound is relative to the source, so a low-key photograph is judged against
its own darkness. A refused take is drawn again, up to three times.

Each run draws a fresh seed and prints it, and `POSTPRO_SEED` renders a family again.

A chain is grown and not sampled. A random subset of the whole effect list is the Photoshop
filter menu and looks like one. A step may join only where some preset already places it
beside everything already picked, so the steps belong to one process. One or two steps carry
the look and the rest sit quietly beneath them. A random take is a clean film grade: nothing
that softens (lens and defocus simulations, diffusion, cross-fades, faded prints), nothing that
prints a relief or a halo (band lifts, edge effects, local contrast), no fringes or distortion,
no frames or overlays, and none of the wear shelf of dust, scanner noise and tape dropouts.
`RANDOM_UNCLEAN` lists them, they are dropped from a look's own steps too, and only `--rough`
admits them. Grain is never optional, because a chain with no crystals in it is a colour filter
with opinions, but it runs at no more than 0.45, felt rather than seen. Black-and-white stocks
develop a panchromatic luminance image, so their looks come out monochrome. Within a run each
picture is drawn against the others and takes a stock no other picture used.

Other modes grade in bulk. The `--watch` flag grades every new photo that lands in a folder,
`--auto` grades the default globs, and `--from-replicate` grades what replicate wrote last.
The `--gallery` flag writes an `index.html` contact page of every render in a folder, beside the
renders it lists. The `--stock-sheet` flag tiles one frame through every stock. Bulk grades and
stock sheets sit beside their source like every other render. A LUT export has no source
photograph, so it goes to the shared dated directory, which `POSTPRO_OUTPUT_DIR` can move; pass
`--output` where the command accepts an explicit destination.

## Reading a frame, and a set

A photograph fails in four independent ways: geometry, light, expression and optics. A grade
can fix only the optical layer and part of the light, and `--rescue` names what it fixed and
what it could not, where a quieter tool would claim success. The `--measure` flag reads texture
numbers and a palette, or with `--against` shows how a grade moved them. It also prints two
readings borrowed from MASTER's laws: the finest octave, which tells a frame at its own
resolution from an upscaled one, and the squint, which reports how much tonal separation
survives a heavy blur. Neither diagnoses anything yet, since their thresholds were drawn on
synthetic frames.

The `--set DIR` flag reads a folder as one set. It names every pair of frames that are one
photograph taken twice and states each frame's exposure in stops from the set's median. It
changes nothing, because moving a frame toward the median changes the look, and that step
belongs to the operator.

## What it does not model

It is not a spectral simulation. Published work that is one starts from measured spectral
sensitivities and dye densities and carries the negative through an enlarger and a paper
stock. That is a different program and needs data this repository does not have. What is
modelled here is the emulsion's statistics, its curve, its crosstalk and its base.

## Config and camera bodies

Presets and defaults come from built-in tables unless `POSTPRO_CONFIG` or a `master.json`
beside the script names more. There is no such file now, so every read takes its built-in
fallback and the default preset is `house`. The camera-profile pass reads
`camera_profiles.json`, which holds sensor matrices for bodies from Canon, Fujifilm, Leica,
Nikon, Olympus and Sony, recovered from a VSCO archive. It matches on EXIF make and model, runs
before anything else touches the picture, and does nothing to a file without EXIF, so
generated images are unaffected. The archive's film entries carry no emulation data; the
matrices are sensor calibration and not emulsion.

## Who calls it

The Rails apps reach postpro through `Operator::DeployPaths#postpro_script`, by way of
`Shared::NewsletterVisuals` and brgen's `PostproJob`, and `RAILS/master` grades web photos
through `image_presenter.rb`. The replicate tool hands every fresh generation here by default,
and lora grades its renders the same way. Programmatic invocation goes through
`Master::Io::ScriptDispatch` under the tool name `postpro`, and natural-language routing goes
through `Io::MediaIntent` as `/postpro`. Route new path references through those, and do not
hardcode the file location. `MASTER/tools/postpro` is a compatibility symlink into this folder.

The file `video.yml` remains the video-generation recipe contract. Postpro no longer starts a
separate Ruby process per frame: `postpro.rb --video` streams frames through the live in-process
grade and then muxes them into MP4 under explicit limits. `DILLA_VIDEO_POSTPRO=0` still gives
a Dilla video export without its optional post-capture treatment.

## Trust

Images, EXIF fields, LUTs, camera profiles, preset names and filenames are untrusted data.
Subprocess calls take argument arrays and never a built shell string. Outputs are written to a
temporary file and moved into place once validated, and metadata may not select Ruby constants,
files or executables. The tool fetches no remote images; if it ever does, it needs an explicit
fetcher that restricts hosts, validates redirects and bounds size.

## Commands

Run these from the repository root.

```sh
ruby STUDIO/postpro/postpro.rb photo.jpg
ruby STUDIO/postpro/postpro.rb one.jpg two.jpg ~/Pictures/trip
ruby STUDIO/postpro/postpro.rb --input in.jpg --output out.jpg --preset portrait
ruby STUDIO/postpro/postpro.rb --random --rough
ruby STUDIO/postpro/postpro.rb --vocab-check
ruby STUDIO/postpro/postpro.rb --measure photo.jpg
ruby STUDIO/postpro/postpro.rb --rescue photo.jpg
ruby STUDIO/postpro/postpro.rb --set ~/Pictures/trip
ruby STUDIO/postpro/postpro.rb --list-presets
ruby STUDIO/postpro/postpro.rb --describe-preset noir
ruby STUDIO/postpro/postpro.rb --export-lut cinematic --output cinematic.cube
ruby STUDIO/postpro/postpro.rb --capabilities

# the depth model, once, into the gitignored models/depth/
mkdir -p STUDIO/postpro/models/depth
for f in model_fp16.onnx model_fp16.onnx_data; do
  curl -fL -o STUDIO/postpro/models/depth/$f \
    https://huggingface.co/onnx-community/depth-anything-v2-small-ONNX/resolve/main/onnx/$f
done
```
