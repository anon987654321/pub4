# STUDIO

**STUDIO is the media workshop: sound, images and video, made by tools that can say how they
made them.** Every take carries its seed, every grade names its chain, and every paid call
leaves a line in a ledger, so a result can be heard or seen again and a bill can be read.

Four tools live here. The tool `dilla/dilla.rb` generates music from declared harmony, drum
grids and synthesised instruments, and plays it live or renders it to a file. The tool
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

The tools hand work to each other by file. Replicate grades what it generates through postpro by
default, lora grades its renders the same way, and dilla's video renderer reads recipes from
postpro's `video.yml`. Render output belongs beside the tool that wrote it, never at the
repository root, and renders are irreplaceable: nothing here should write over a take that
matters.

The folder `test/` holds every suite, one file per subject, and `Rakefile` runs them with one
process per subject because the tools define constants at top level and would collide in a
shared process. Running `rake` in this folder runs the gate and then every suite. The script
`gate.rb` parses every Ruby file, checks the boundary rule above and loads each entry point
without running it, and `isolation.rb` reruns each test file alone to find the ones that only
pass in company. The folder `visual/` holds the generator behind `photograph.rb`.
