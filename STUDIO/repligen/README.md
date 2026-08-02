# Repligen

Repligen is MASTER's noninteractive Replicate boundary. It generates images,
downloads a result when an output path is requested, searches the provider
catalog, synchronizes a bounded local catalog, and reports catalog statistics.
It never installs gems, scrapes the website, or stores credentials in the
repository.

MASTER normally chooses it from natural language, so users do not need these
commands. The CLI remains useful for diagnostics:

```sh
ruby studio/repligen/repligen.rb generate --prompt "Bergen rain, 35mm documentary photograph" --output .master/media/bergen.webp
ruby studio/repligen/repligen.rb search flux --limit 100
ruby studio/repligen/repligen.rb sync --limit 250
ruby studio/repligen/repligen.rb stats
ruby studio/repligen/repligen.rb capabilities
ruby studio/repligen/repligen.rb vocab-check
```

Every example here said `MASTER/tools/repligen.rb` until 2026-07-30 — a path
the file left on 2026-07-25, and one it never had anyway (it was
`MASTER/tools/repligen/repligen.rb`). The script's own requires were stale in
the same way and aborted the whole file with a LoadError on line 12, which is
why nobody noticed the README.

## Structured fields

The free-text `--prompt` is the subject. Everything else about the photograph
composes onto it from named vocabularies, so a house style is a set of flags
rather than a paragraph to remember:

```sh
ruby studio/repligen/repligen.rb generate \
  --prompt "a fisherman on a dock" \
  --stock hp5 --lens 85mm --distance portrait --camera-height eye \
  --lighting rembrandt --weather drizzle --time-of-day blue_hour \
  --batch 6 --dry-run
```

`--stock` 23 values, `--lens` 14, `--lighting` 20, `--weather` 12,
`--time-of-day` 11, `--distance` 8, `--camera-height` 7. Spelling is normalised
for case, hyphens and spaces, so `--time-of-day Golden-Hour` finds
`golden_hour`. An unknown value **aborts and prints the valid ones**: it used to
be documented as "a no-op rather than a crash", which in practice meant
`--stock portra400` produced a prompt with no film stock in it, silently, after
the generation had been paid for and waited on.

`--distance` also decides the aspect ratio unless `--aspect-ratio` overrides it,
so a `closeup` is 4:5 and an `establishing` shot is 16:9.

Two fields describing incompatible light (`--lighting golden_hour` with
`--time-of-day night`, `--lighting overcast` with `--weather clear`) produce a
warning. Not a refusal — a neon sign at midday is a real photograph — but the
model resolves the contradiction by honouring one and discarding the other, and
does not say which.

`vocab-check` verifies all of the above without an API call: every key
reachable after normalisation, every `--distance` mapped to a ratio, every
model's `negative_prompt_key` present in its own `input_keys`, and the batch
diversity claim measured rather than asserted.

## Negative prompts

Every Flux model, including the default `flux-1.1-pro`, has no negative-prompt
input at all. Repligen assembles an anti-plastic-skin negative anyway, so for
those models it asks for the opposite in the affirmative
(`POSITIVE_SKIN_GUIDANCE`) and says on stderr that it is doing so. The
provenance sidecar records `negative_prompt_sent` alongside the text: before
2026-07-30 it recorded the negative as though it had been applied when
`build_input`'s `input_keys` filter had dropped it.

Models that do take one (`stable-diffusion-3.5-large`) get it as written.

## Batches

`--batch N` cycles expression, pose, wardrobe and background pools of different
lengths (7, 6, 8, 9) at strides coprime with each, so 20 consecutive indices
give 20 distinct combinations and the tuple does not repeat for 504 images. The
previous version read four same-length pools at the same index: `--batch 20`
returned each of five combinations four times, every time.

## Everything else

Credentials resolve from `REPLICATE_API_TOKEN`, `REPLICATE_API_KEY`, or
`~/.config/repligen/config.json`. Catalog state defaults to
`~/.cache/repligen/models.json`. MASTER routes explicit image-generation
requests through this boundary; it does not claim a separate local
identity-model path.

Generation returns provider URLs unless `--output FILE` is supplied. Missing
credentials, missing outputs, provider failures, cancellation, and timeouts are
explicit failures; the tool does not silently substitute a model or claim a
local file exists.

Each saved output gets a content-addressed blob, a checksum, a provenance
sidecar and a line in `.master/media/gallery.jsonl`. The gallery's alt text
describes the subject, the crop, the camera height and the background — not the
compiled prompt, which is how the image was made rather than what it is of.

`--postpro PRESET` hands the finished file straight to
`studio/postpro/postpro.rb`. The `capabilities` command emits the executable
60-item Repligen/LoRA contract as JSON.
