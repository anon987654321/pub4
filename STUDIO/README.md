# STUDIO

**STUDIO is the media workshop: sound, images and video, made by tools that can say how they
made them.** Every take carries its seed, every grade names its chain, and every paid call
leaves a line in a ledger, so a result can be heard or seen again and a bill can be read.

Four tools live here. `dilla/dilla.rb` is a thin executable over `dilla/lib/dilla/`; it reads
progressions and runtime choices from `dilla/data/dilla.json` and harmonic references from
`dilla/data/music_theory.json`. It builds its own oscillators, voicings, arpeggios, drums and
effects without samples, and can render WAV/MIDI or play continuously. The tool
`postpro/postpro.rb` grades and transforms still images through film emulation. The tool
`replicate/replicate.rb` generates images through the Replicate service from a named
photographic vocabulary. The tool `replicate/lora/lora.rb` trains and renders a LoRA of one
person, and animates a still into a short clip, through the same client. A small script,
`photograph.rb`, turns a sentence into a still and, with `--film`, a short clip. The source
still and clip live in `~/ideas`; the returned graded still lives in the dated render directory
owned by `output_paths.rb`.

MASTER governs these tools and reaches each through its canonical path
`MASTER/tools/<tool>/<tool>.rb`. Those paths are compatibility symlinks into this tree, and new
automation should name the STUDIO path. Each tool is standalone: the entry points load without
the MASTER process booted, and a gate refuses any file here that requires from MASTER, RAILS or
OPENBSD. Read the README beside a tool before changing it.

The tools hand work to each other by file. Replicate grades what it generates through
postpro by default, and lora grades its renders the same way. Postpro's bulk grades, stock
sheets and LUT exports use the shared `output_paths.rb` contract: a dated folder under
`${XDG_DATA_HOME:-~/Documents}/dilla-renders`, outside the checkout by default.
`POSTPRO_OUTPUT_DIR` redirects Postpro, and `DILLA_OUTPUT_DIR` redirects Dilla's
default renders. Reference-analysis artifacts share the same XDG data home as MASTER.
Explicit `--output`, `--out` and `--video` paths remain operator-controlled. The `photograph.rb` workflow uses a per-job
folder under the same dated directory for its returned graded still.

Dilla's default showcase preserves existing takes: it tries the familiar filenames, then the
ignored `out/` directory, then a fresh timestamped WAV/MP4 pair. Its WAV and MIDI writers
refuse existing paths by default, stage new bytes before publish, and require the explicit
`--replace` option to replace a take.

The folder `test/` holds every suite, one file per subject. The `Rakefile` runs the gate,
then starts each suite in its own process because the tools define constants at top level and
would collide in a shared process. The script `gate.rb` parses every Ruby file, checks the
sibling-import boundary and verifies the entry points have load guards. The tests keep each
tool isolated as they run. The folder `visual/` holds the generator behind `photograph.rb`.
