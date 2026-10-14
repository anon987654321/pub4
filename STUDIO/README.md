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
`photograph.rb`, turns a sentence into a still and, with `--film`, a short clip, written to
`~/ideas`.

MASTER governs these tools and reaches each through its canonical path
`MASTER/tools/<tool>/<tool>.rb`. Those paths are compatibility symlinks into this tree, and new
automation should name the STUDIO path. Each tool is standalone: the entry points load without
the MASTER process booted, and a gate refuses any file here that requires from MASTER, RAILS or
OPENBSD. Read the README beside a tool before changing it.

The tools hand work to each other by file. Replicate grades what it generates through
postpro by default, and lora grades its renders the same way. Postpro's bulk renders default to
`${XDG_DATA_HOME:-~/Documents}/dilla-renders/<UTC date>`, outside the repository; set
`POSTPRO_OUTPUT_DIR` to choose another destination. Takes are irreplaceable: Dilla's WAV and
MIDI writers refuse existing paths by default, stage new bytes before publish, and require the
explicit `--replace` option to replace a take.

The folder `test/` holds every suite, one file per subject, and `Rakefile` runs them with one
process per subject because the tools define constants at top level and would collide in a
shared process. Running `rake` in this folder runs the gate and then every suite. The script
`gate.rb` parses every Ruby file, checks the boundary rule above and loads each entry point
without running it, and `isolation.rb` reruns each test file alone to find the ones that only
pass in company. The folder `visual/` holds the generator behind `photograph.rb`.
