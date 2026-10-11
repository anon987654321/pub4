# postpro

**Film is a physical process, and postpro models the process rather than imitating the
result.** A filter is a lookup table with an opinion. This is an emulsion: crystals with a
size and a statistics, a base that reflects light back into the layer it came through, a
curve that spends contrast instead of adding it, and a print stock after that. It is the
house grade for stills, and its entry point is `STUDIO/postpro/postpro.rb`.

Give it `--input`, `--output` and `--preset` and it grades one image headless. Give it a bare
path and the path is the subject: an image goes through several random chains written beside
it, a directory gives a few random picks from it, and a path that is neither is named and
refused. Give it nothing and it asks what to grade. The command `postpro.rb --help` lists every
flag, and `--capabilities` says what the current build can do on this machine.

The code is a handful of files. The file `postpro.rb` holds the grade, the presets, the film
tables and the command line. The file `legacy_effects.rb` holds the creative effects recovered
from the older `pub/postpro` line, and `LEGACY_RESTORE.md` records which of them already had
current equivalents. The file `dilla_analog.rb` translates mechanisms from dilla's analog
chains into still images, so that temporal wow and flutter become spatial registration error.
The file `uncanny.rb` measures whether a picture looks rendered, `rescue.rb` diagnoses a bad
photograph, `frame_set.rb` reads a folder as a set, and `depth.rb` supplies a real depth map
when its model is installed. The file `constitution.rb` is the boundary where MASTER's laws
become image-generation invariants, `analog_capabilities.rb` backs `--capabilities`, and
`camera_profiles.json` carries the sensor data. A log file named `postpro.log` also sits in
the folder; it is output, and git should not carry it.

## The checks that catch what does not raise

The command `--vocab-check` is the one to run after touching any table. It verifies that every
preset names an effect with an implementation and a stock and lens that exist, that a stock has
a row in every per-stock table its chain reads, that every key a preset declares has a step in
its chain that reads it, that every film curve is monotonic, and that nothing is defined which
neither a preset nor a recipe can reach. It exits non-zero on a problem.

It exists because none of those failures raise. An effect with no implementation once returned
the image unchanged while the log reported the step as done, and a colour temperature that
`--describe-preset` printed but no step applied is a lie and not a look. Table-driven
pipelines fail by producing a picture slightly wrong beside a log that agrees with the preset.
At the last run the check reported the current vocabulary as eighty-two presets, fourteen
stocks, eleven lenses and a hundred and eight effects, and it also reported twenty problems:
a number of the recovered `legacy_` and `dilla_` presets declare a temperature, a print stock
or a lens that no step in their chain reads. Those are open defects in the restore, and the
check is doing its work by naming them.

The other introspection flags process no image and are equally cheap: `--list-presets`,
`--list-stocks`, `--list-lenses`, `--describe-preset`, `--fit-grain`, `--export-lut` and
`--css-filter`.

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
filter removes the measurement puts back. Chroma grain is correlated with luma grain because
one crystal layer shadows the next. The grain figure of a stock is its peak luma deviation in
eight-bit levels at mid-grey, a quantity an instrument can check, and `--fit-grain` is that
instrument: point it at a flat scan and it reports the deviation per tone and the crystal size
that implies. Treat its figures as a floor, since its residual is a high-pass and the coarsest
octave goes out with the picture. Rated film keeps its own box speed, each stop of push costs
more, cell size scales with image width, and the finishing grain pass stands down for any
chain that already grains itself.

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

## Random chains and heavy mode

A bare path, or `--random`, renders several variations of a photograph, each through its own
chain, written beside the source with a JSON sidecar naming every effect and the seed. Heavy
mode is the standing default: five variations dealt from subtle to bleeding edge, with long
chains. `POSTPRO_HEAVY=0` returns to the lighter taste. Each run draws a fresh seed and prints
it, and `POSTPRO_SEED` renders a family again.

A chain is grown and not sampled. A random subset of the whole effect list is the Photoshop
filter menu and looks like one. A step may join only where some preset already places it
beside everything already picked, so the steps belong to one process. One or two steps carry
the look and the rest sit quietly beneath them. The wear shelf of dust, scanner noise and tape
dropouts stays off unless `--rough` admits it, and grain is never optional, because a chain with
no crystals in it is a colour filter with opinions. Within a run each picture is drawn against
the others and takes a stock no other picture used.

Other modes grade in bulk. The `--watch` flag grades every new photo that lands in a folder,
`--auto` grades the default globs, and `--from-replicate` grades what replicate wrote last.
The `--stock-sheet` flag tiles one frame through every stock.

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
`Shared::NewsletterVisuals` and brgen's `PostproJob`, and `RAILS/master_web` grades web photos
through `image_presenter.rb`. The replicate tool hands every fresh generation here by default,
and lora grades its renders the same way. Programmatic invocation goes through
`Master::Io::ScriptDispatch` under the tool name `postpro`, and natural-language routing goes
through `Io::MediaIntent` as `/postpro`. Route new path references through those, and do not
hardcode the file location. `MASTER/tools/postpro` is a compatibility symlink into this folder.

The file `video.yml` is the one video-facing piece. Postpro remains an image engine and never
runs once per video frame, but dilla's audiovisual renderer reads the same recipes in a single
ffmpeg pass after capture. Geometry is dilla's; postpro supplies the photographic substrate
and the controlled damage. `DILLA_VIDEO_POSTPRO=0` gives an untreated export.

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
```
