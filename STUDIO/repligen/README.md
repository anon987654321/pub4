# Repligen

Repligen is MASTER's noninteractive Replicate boundary. It generates images,
downloads a result when an output path is requested, searches the provider
catalog, synchronizes a bounded local catalog, and reports catalog statistics.
It never installs gems, scrapes the website, or stores credentials in the
repository.

MASTER normally chooses it from natural language, so users do not need these
commands. The CLI remains useful for diagnostics:

```sh
ruby STUDIO/repligen/repligen.rb generate --prompt "Bergen rain, 35mm documentary photograph" --output .master/media/bergen.webp
ruby STUDIO/repligen/repligen.rb search flux --limit 100
ruby STUDIO/repligen/repligen.rb sync --limit 250
ruby STUDIO/repligen/repligen.rb stats
ruby STUDIO/repligen/repligen.rb capabilities
ruby STUDIO/repligen/repligen.rb vocab-check
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
ruby STUDIO/repligen/repligen.rb generate \
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
model's `negative_prompt_key` present in its own `input_keys`, every declared
input key fillable by something in `build_input`, and the batch diversity claim
measured rather than asserted.

## Sampler knobs

`--guidance` and `--steps` are model-relative, because the models disagree on
both the spelling and the range. On `flux-dev` they are `guidance` (0–10) and
`num_inference_steps` (1–50); on `flux-schnell` the step ceiling is **4**; on
`stable-diffusion-3.5-large` they are `cfg` (0–20) and `steps` (1–50);
`flux-1.1-pro` and `flux-1.1-pro-ultra` have neither. A figure outside the
chosen model's range is a refusal, not a clamp — clamping silently is how
you pay for 28 steps on a four-step model and get four.

`--final` is Ultra (4 MP). `--raw` / `--no-raw` reach Ultra's camera-look
toggle; `--stock` or `--lens` turns raw on unless `--no-raw`. `--image PATH`
is required on `flux-kontext-pro` (text-instructed edit); generate without
one is a refusal, not a silent text-to-image fallback.

Both knobs were read by `build_input` long before either had a flag: three
declared capabilities with no way to reach them. `vocab-check` now fails on
that shape.

## Negative prompts

**No model in the table takes a negative prompt.** Every Flux model, including
the default `flux-1.1-pro`, has no such input, and `stable-diffusion-3.5-large`
dropped the one SD3 had — its live schema is prompt / aspect_ratio / cfg /
image / prompt_strength / steps / seed / output_format / output_quality, and
nothing else. The capability table said otherwise until 2026-08-11, and because
it was the only entry claiming support it was the only one for which the
positive fallback was suppressed, a `negative_prompt` key the model does not
have was sent, and the sidecar recorded `negative_prompt_sent: true`.

Repligen assembles an anti-plastic-skin negative anyway, so it asks for the
opposite in the affirmative (`POSITIVE_SKIN_GUIDANCE`) and says on stderr that
it is doing so. The provenance sidecar records `negative_prompt_sent` alongside
the text: before 2026-07-30 it recorded the negative as though it had been
applied when `build_input`'s `input_keys` filter had dropped it.

## Preview and final

`--preview` swaps in `flux-schnell` unless a model was named explicitly or
`REPLIGEN_MODEL` is set. `--final` forces `flux-1.1-pro-ultra` and **does**
override `REPLIGEN_MODEL`, which is the asymmetry it exists for: the
environment variable is how a session stays in preview, and `--final` is how
one image leaves it — now at 4 MP, with raw mode when the request is a
photograph. Until 2026-08-11 `--final` was parsed into an option nothing read.

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
`STUDIO/postpro/postpro.rb`. The `capabilities` command emits the executable
60-item Repligen/LoRA contract as JSON.

## Keeping the model table honest

`MODEL_CAPABILITIES` is a second source of truth. It exists so an unsupported
option is refused rather than accepted-and-ignored — a request that "works"
while dropping a setting is much harder to notice than a 422 — and the cost of
that is that it goes stale silently: the tests check the table against itself,
so provider drift surfaces in production or not at all.

```sh
cd STUDIO
rake repligen:schema_audit                                   # table vs. live schemas
rake repligen:schema_suggest MODEL=black-forest-labs/flux-2-max   # an entry to paste
```

Neither runs as part of `rake`. Both need the network and a token, and a check
that cannot run says so rather than passing.

**Surveyed 2026-08-25.** Nothing here is broken — `flux-1.1-pro` is live and
carries no deprecation notice. But the six declared models are a generation
behind what Replicate now leads with, and none of these is named here:

| model | why it might matter |
|---|---|
| `black-forest-labs/flux-2-max` | BFL's current highest-fidelity image model |
| `bytedance/seedream-5-pro` | flagship text-to-image **and** editing in one model |
| `google/nano-banana-2` | fast generation with conversational editing |
| `openai/gpt-image-2` | sharp text rendering inside the image |
| `krea/krea-2-medium` | expressive illustration, anime, painterly |
| `prunaai/p-image` | sub-second generation |

The shape of the field moved as well as the names: editing is now a mode of the
flagship models rather than a separate one, which is a different arrangement
from the single `flux-kontext-pro` path here that requires `--image`. Recraft V4
also emits editable SVG, which nothing in this tool can currently receive.

Adopting any of them decides what the pictures look like, so it stays an
operator call. `schema_suggest` is here so that when the decision is made, the
input keys come off the provider instead of out of somebody's memory — the one
thing that must never be guessed, since guessing them breaks the refusal that
makes the table worth keeping.
