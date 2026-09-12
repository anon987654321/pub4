# postpro

**Film is a physical process, and postpro models the process rather than
imitating the result.** A filter is a lookup table with an opinion. This is an
emulsion: crystals with a size and a statistics, a base that reflects light back
into the layer it came through, a curve that spends contrast instead of adding
it, and a print stock after that. It is the house grade for stills, and its
entry point is `STUDIO/postpro/postpro.rb`.

Give it `--input`, `--output` and `--preset` and it runs headless. Give it
nothing and it opens the interactive menu — presets, random chains, or a custom
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
`age:`, `lens:`, `print_stock:`, `exposure_secs:`, `k1:`, `f_number:`,
`tonemap:` — has a step in that chain that reads it; that every recipe-allowed
effect is callable the way `recipe()` calls it; that every H&D curve is
monotonic; that no stock is quoted at a granularity no scan has ever measured;
and that nothing is defined which neither a preset nor a recipe can reach. It
exits non-zero on a problem.

It exists because none of those failures raise. An effect name with no
implementation returned the image unchanged while the log reported the step as
done. Five presets declared a lens no chain applied. Every stock carried a colour
matrix nothing read. The failure mode of a table-driven pipeline is not a crash.
It is a picture that came out slightly wrong and a log that agrees with the
preset.

The other introspection flags process no image and are equally cheap:
`--list-presets`, `--list-stocks`, `--list-lenses`, `--describe-preset`,
`--fit-grain`, `--export-lut`, `--css-filter` and `--capabilities`.

### The model

A preset is an ordered chain of effects plus the film it is shot on — `noir`, for
instance, runs optical blur, tonemap, push-pull, film curve, bleach bypass,
desaturate, shadow lift and grain over `tri_x` at 5600 K, intensity 0.90, pushed
two stops.

Per-stock data lives in six tables keyed by the same symbol: `STOCKS`, carrying
granularity, box speed, colour matrix and per-channel H&D curve, then
`GRAIN_CHAN_SCALE`, `FILM_BASE`, `PUSH_RESPONSE`, `RECIPROCITY_SHIFT` and
`C41_STOCKS`. A stock missing from one of them does not fail. It quietly becomes
a different stock, which is why `--vocab-check` refuses a gap.

`stock_matrix` normalises its rows so the matrix does dye crosstalk and the H&D
offsets do the colour cast, instead of both doing cast. A preset that sets
`temp:` without a `spectral_temp` or `color_temp` step in its chain is a
`--vocab-check` failure, under the same unread-key rule as `stops:`, `lens:` and
`age:`. A Kelvin figure `--describe-preset` prints and the render never applies
is a lie, not a look.

### Grain, which is the argument

Grain is a Boolean model. Silver halide crystals are disks dropped by a Poisson
process whose density respects the local gray level, and the developed picture is
what you see when you filter that binary field. Two things follow from it, and
this file had both backwards until a reader said the grain looked thin and the
measurement agreed with him.

The filtered field has variance proportional to the gray level times one minus
the gray level, so the amplitude, being a standard deviation, follows its square
root. The envelope here was that variance curve used directly as an amplitude,
which charged a highlight roughly three times the grain it should carry against a
midtone, where film charges it 1.7. And the crystal radius and the blur it is
observed through are independent — one belongs to the emulsion, the other to the
enlarger, the scanner and the eye — while this file derived both from one cell
size, so the filter always sat at about half the width of the grain it was
filtering and no amplitude could survive it. Measured before the change, Portra
at preset strength laid a quarter of a level of luma sigma on flat grey, against
the three to eight a real 35 mm scan carries.

Both are fixed at the mechanism rather than by turning a knob up. The crystal
field is generated, clumped, made slightly anisotropic along the transport axis,
blurred by the observer, and then normalised by its own measured deviation, so
whatever the filter takes out the measurement puts back and the two constants
stop fighting. Chroma grain is drawn correlated with luma grain rather than three
independent times, because one crystal layer shadows the next.

What this buys is a number that means something. `STOCKS[:grain]` is now the
stock's peak luma sigma in eight-bit levels at mid-grey, times one scale factor:
Portra reads 3.6, Tri-X 6.0, Delta 3200 9.1. Those are quantities an instrument
can check, and `--fit-grain` is the instrument. Point it at a flat frame and it
reports the sigma per tone, the correlation radius that implies a crystal size,
and a set of knots ready to paste into a stock that disagrees with the model.
Run against this file's own output at a known strength it reads about fifteen
percent low, because its residual is a high-pass and the grain's coarsest octave
goes out with the picture, so read the figures as a floor.

Rated film keeps its own box speed. At box speed a stock comes out at its own
granularity and each stop of push costs the square root of two more. Cell size
scales with image width from a 2048 px reference, so a newsletter hero and a 4K
print share an emulsion. And the finishing pass now stands down for any chain
that grains itself, which is 57 of the 61 presets; two passes add in quadrature,
and a stock quoted at six levels was arriving at eight and a half.

Random chains ask for a third to two thirds of a stock's granularity rather than
all of it, which is where the grain of a print sits rather than the grain of a
negative seen at 1:1.

### Halation is a ring

Light that gets through the emulsion reflects off the rear face of the base and
re-enters the emulsion a base-thickness away, so it re-exposes an annulus around
a highlight rather than a halo centred on it. This summed a narrow and a wide
Gaussian, which puts the most returned light exactly where the highlight already
is, the one place it cannot land. Differencing them gives the ring, and the
narrow lobe stays on as the scatter that never left the emulsion. Per-channel
radii still model wavelength-dependent penetration, red furthest, which is why
`cinestill_800t` blooms red and why halation is the point of that stock.

### Light, and depth

A grade cannot move a shadow to the other side of a nose. It can move the light
that made the shadow, and until now this file could not do even that.

`relight` splits the picture into illumination and reflectance — a heavy blur of
the luminance is the light, and what is left over is the surface — then puts the
light back differently and leaves the surface exactly alone. The correction
rides as a ratio on all three channels, so texture, grain and hue survive it
untouched; only the modelling moves. Measured on a portrait at full strength it
deepens low-frequency contrast by twenty-one percent and moves texture by one.
That is a power window done by arithmetic, and it is the whole of what
relighting can honestly mean inside a grade. `shape` above one deepens the
falloff the light already made, which is depth with no new contrast anywhere.
`azimuth` swings the key around the frame. The ratio is bounded, because an
unbounded division by a blurred luminance will find a black background and
multiply it by four hundred.

`aerial_depth` is the oldest depth cue in painting. Distance costs contrast,
costs saturation and cools, because what sits between you and the far thing is
air full of scattered skylight. Every other depth cue here is optical — defocus,
vignette, tilt — and optics is where the amateur version lives, because a
blurred background reads as a filter while haze reads as a room. What is near is
what is sharp, so local high-frequency energy stands in for proximity. It is a
proxy and it is named as one: it will read a sharp cloud as near. The mask is
cubed before use, because straight off the acutance it covers half the frame at
a mean of 0.57 and that is a global wash wearing a depth cue as a name; cubed it
sits at 0.32 and lives where the detail is not. Over the sharpest fifth of a
portrait it reads zero either way, so the face was never at risk — what the
curve buys is the middle distance.

### The tone scale

`tonemap` carries five curves. The ACES one is the 2016 fit to the Academy's
first rendering transform, and its highlight desaturation is the "ACES look" the
Academy then spent years removing. Hable is Uncharted 2's S-curve and
Hejl-Burgess-Dawson lifts the toe. Two are new and are what a colourist would
expect today.

AgX rotates into a narrower set of primaries, log-encodes, runs a sigmoid there
and rotates back. The rotation is the point: it stops a channel reaching clip
from dragging hue with it, which is exactly what a per-channel curve does to a
saturated light source. The ACES 2 entry is that system's tone scale, a
Michaelis-Menten curve with a flare term, which places mid-grey where the current
standard places it. It is the tone scale alone — ACES 2 also carries chroma
compression and gamut mapping in an appearance model, which is a colour pipeline
rather than a curve, and AgX is the hue-preserving option here. A preset chooses
with `tonemap:` and gets the ACES 2 scale if it says nothing.

### Random chains, which are the opposite of a filter

`--random` renders three to five pictures per run, each through its own chain,
written beside the source — Downloads if there is one, the working directory
otherwise, with a JSON sidecar naming every effect and the seed, because a chain
nobody wrote down is a chain nobody can render again.

A chain is grown, not sampled. A random subset of seventy-three effects is the
Photoshop filter menu and it looks like one: tilt-shift and selenium toning and
teal-orange on the same frame, each at half strength, none of them agreeing
about what the picture is. What makes a chain read as a grade instead is that
its steps belong to one process — a stock, a development, a print, one way of
having been damaged.

Nobody declares those families. They are read off the sixty-one presets, which
are sixty-one colourists' answers to the same question: a step may join only
where some preset already puts it beside everything already picked, and it runs
at the position those presets on average give it. The graph is dense enough to
carry it, so the constraint buys coherence without costing variety.

Three rules do the rest, and they are the difference between a grade and a
stack. One or two steps carry the look, between 0.38 and 0.66, and everything
else sits under 0.16 — nine effects at half strength each is mud, and it is the
clearest tell of an amateur pass. Those numbers came down: a lead at 0.95
announces itself, and the honest reading of subtlety is that a viewer should not
be able to name the effect. Depth is not loudness.

The wear shelf — dust, scanner noise, tape dropouts, fogged fixer, gate weave —
is off entirely unless `--rough` asks for it. It may never lead, because dust at
0.94 is the artefact becoming the picture, but the deeper problem is that it is
loud by construction and reads as an effect where the rest of this file is
trying to read as a photograph. With `--rough` it comes back capped at two
marks, because two is a print that has been handled and five is a prop. The
backbone never leads either — most presets carry optical blur, so leading with
it is not a look, it is an out-of-focus photograph.

Every chain shapes the light. One of `relight` or `aerial_depth` runs in every
picture and it is one of the leads, because a chain that leaves the light alone
is a chain about texture, and texture is the shallow half of a photograph.

Then one step is allowed to disagree with the family, quietly, because a chain
that is only coherent is a template and the interest is in the one thing that
should not be there. Effects may repeat, a quarter of the way further along the
process rather than back to back: two passes of halation at different radii is
what a bright window through a thick base does, and the interest is in what
happened between them. Grain is never optional. A chain with no crystals in it
is a colour filter with opinions.

Within a run, each picture is drawn against the ones already made — distinctive
effects only, since sharing a backbone is not a resemblance — and each takes a
stock no other picture in that run used. Every run picks a fresh seed and prints
it, so the next run differs and any run can be had again by setting
`POSTPRO_SEED`. `uplift` still stacks two presets over every file in the folder,
which asks a different and narrower question.

### What this does not model

It is not a spectral simulation. The published work that is — agx-emulsion and
the `filmsim` module that follows it — starts from measured spectral
sensitivities and dye density spectra read off manufacturer datasheets, and
carries the negative through an enlarger, a paper stock and a scan. That is a
different program, not a feature, and it needs data this repository does not
have. What is modelled here is the emulsion's statistics, its curve, its
crosstalk and its base. Where those two disagree, the datasheet wins.

### Which stock, and what for

`--list-stocks` prints the names. What it cannot print is judgement, and this is
the one part of this file not derivable from the tables. Gamma is contrast, per
channel. Granularity is the emulsion's own sigma in levels. ISO is box speed,
which is what `push_pull` rates against.

For skin, reach for `kodak_portra` — ISO 400, granularity 15, gamma 1.10, the
lowest contrast of the colour negatives here, which is why it flatters faces and
why it is the default — or `fuji_pro400h` at 400/16/1.05, flatter still and
cooler through the greens. They are the two halves of the wedding-photography
pair.

For landscape and product, where there is no face to protect, `kodak_ektar100` at
100/6/1.34 is the finest grain in the table with high contrast, and `fuji_velvia`
at 50/8/1.45 has the most contrast of anything here — saturated slide film, never
skin. `ektachrome_100` at 100/10/1.30 has Velvia's discipline with less of its
violence, and runs cooler. `kodachrome` at 64/12/1.42 is for reds and for
archival mid-century work; its blue gamma is notably low, 1.20 against 1.42 red,
and that split is the look.

The cinema negatives are made to be graded afterwards. `kodak_vision3` is
500/20/1.15, daylight, with wide latitude. `kodak_vision3_50d` at 50/8/1.08 is
the same family at box speed 50 — clean, slow, bright exteriors.
`kodak_vision3_500t` at 500/20/1.18 is tungsten-balanced, for interiors and night
without a correction filter. `cinestill_800t` at 800/22/1.20 is 500T with the
remjet removed, so highlights bloom red; it scatters more than anything else in
the table.

In black and white, `tri_x` at 400/25/1.30 is the classic — prominent grain, hard
contrast, street and reportage. `ilford_hp5` at 400/22/1.22 is its rival and
softer, kinder to a face. `ilford_delta3200` at 3200/38/1.08 is the grainiest and
flattest by a distance, for available darkness, where the grain is the reason
rather than something you tolerate. `polaroid_sx70` carries no ISO, granularity
or gamma at all: its character is in the frame and the dye, not the curve.

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
Rails apps reach it through `Operator::DeployPaths#postpro_script` for newsletter
heroes and TV thumbnails, by way of `Shared::NewsletterVisuals` and brgen's
`PostproJob`. `STUDIO/repligen/repligen.rb --postpro PRESET` hands a fresh
generation straight here.

Programmatic invocation goes through `Master::Io::ScriptDispatch` under the tool
name `postpro`, which resolves the script and runs it from the tool's own
directory. Natural-language routing goes through `Io::MediaIntent` as `/postpro`;
it is a slash-command tool rather than an LLM-native one, which `AGENTS.md`
explains. Route any new path reference through `ScriptDispatch` or `DeployPaths`
instead of hardcoding the file location.

## Running it

```sh
ruby STUDIO/postpro/postpro.rb --input in.jpg --output out.jpg --preset portrait
ruby STUDIO/postpro/postpro.rb --random              # three to five chains, into Downloads
ruby STUDIO/postpro/postpro.rb --random --rough      # the same, with the wear shelf in
ruby STUDIO/postpro/postpro.rb --vocab-check         # are the tables consistent?
ruby STUDIO/postpro/postpro.rb --fit-grain scan.tif  # what grain does this scan carry?
ruby STUDIO/postpro/postpro.rb --list-presets        # every preset and its chain
ruby STUDIO/postpro/postpro.rb --list-stocks
ruby STUDIO/postpro/postpro.rb --list-lenses
ruby STUDIO/postpro/postpro.rb --describe-preset noir
ruby STUDIO/postpro/postpro.rb --export-lut cinematic --output cinematic.cube
ruby STUDIO/postpro/postpro.rb --css-filter portrait
ruby STUDIO/postpro/postpro.rb --capabilities
```
