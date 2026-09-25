# Preprompt

## Canonical contract

### Purpose

Construct governed image-generation requests from structured photographic
vocabularies, model capabilities, and explicit operator choices.

### Inputs

Prompt text, named photographic vocabularies, model selection, optional source
images for edits, deterministic batch settings, and provider credentials.

### Outputs

Provider results, downloaded local artifacts when requested, provenance
sidecars, capability reports, and explicit provider failures.

### Invocation

Use `ruby MASTER/tools/preprompt/preprompt.rb <command>`.

### Architecture

`preprompt.rb` is the request boundary. `lib/craft.rb` owns vocabulary and
composition; provider/model data is declared in the tool and verified against
live schemas when that check is deliberately run.

### Data and state

Prompts and manifests are source/provenance. Credentials, provider responses,
temporary downloads, and caches stay outside the repository unless explicitly
promoted.

### Security boundary

Treat provider schemas, URLs, prompts, images, and model identifiers as
untrusted. Validate redirects and destinations, bound downloads and request
size, use structured subprocesses, and never deserialize or execute remote data.

### Validation

Unknown vocabulary values, unsupported model inputs, missing source images,
missing credentials, and provider failures must be explicit failures. Schema
audits report inability to measure rather than passing silently.

### MASTER integration

Preprompt is a canonical MASTER tool. MASTER governs routing and lifecycle;
Preprompt owns photographic vocabulary, model mapping, request construction,
and artifact provenance.


**A photograph is a set of decisions, and preprompt makes each of them
nameable.** It is MASTER's noninteractive Replicate boundary: it generates
images, downloads a result when an output path is asked for, searches the
provider catalog, synchronises a bounded local one, and reports statistics on
it. It never installs gems, scrapes the website, or stores credentials in the
repository.

MASTER usually chooses it from natural language, so nobody needs to type these
commands. They stay useful for diagnostics, and the last section of this file
lists them.

Check the paths before you trust them. Every example in this file once named a
script location the file had left days earlier, and one it had never had at all.
The script's own requires were stale the same way and aborted it with a
LoadError on line 12 — which is why nobody noticed the README.

## Structured fields

The free-text `--prompt` is the subject. Everything else about the photograph
composes onto it from named vocabularies, so a house style is a set of flags
rather than a paragraph to remember:

`--stock` 23 values, `--lens` 14, `--lighting` 20, `--weather` 12,
`--time-of-day` 11, `--distance` 8, `--camera-height` 7, `--composition` 6 and
`--focus` 4. Focus defaults to nothing, but every drawn scenario asks for sharp
eyes, the feature portrait ratings follow most closely; composition names what
the frame does for the subject, and thirds is on offer without being a default,
because ratings barely follow it. A prompt that says "8k", "artstation",
"octane render" or "flawless" is warned about, since those pull a picture
toward concept art or retouched skin. Spelling is normalised
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

`--final` is `flux-2-max`. `--raw` / `--no-raw` reach the camera-look toggle
on `flux-1.1-pro-ultra`, the one model that has it; `--stock` or `--lens`
turns raw on there unless `--no-raw`. `--image PATH`
is required on `flux-kontext-pro` (text-instructed edit); generate without
one is a refusal, not a silent text-to-image fallback.

Both knobs were read by `build_input` long before either had a flag: three
declared capabilities with no way to reach them. `vocab-check` now fails on
that shape.

## Negative prompts

**No model in the table takes a negative prompt.** Every Flux model, including
the default `flux-2-pro`, has no such input, and `stable-diffusion-3.5-large`
dropped the one SD3 had — its live schema is prompt / aspect_ratio / cfg /
image / prompt_strength / steps / seed / output_format / output_quality, and
nothing else. The capability table is the place that gets this wrong: while it
claimed support for one model, that was the only entry whose positive fallback
was suppressed, so a `negative_prompt` key the model does not have went out and
the sidecar recorded `negative_prompt_sent: true` for it.

Preprompt assembles an anti-plastic-skin negative anyway, so it asks for the
opposite in the affirmative (`POSITIVE_SKIN_GUIDANCE`) and says on stderr that
it is doing so. The provenance sidecar records `negative_prompt_sent` alongside
the text, because recording the negative on its own says nothing about whether
`build_input`'s `input_keys` filter dropped it on the way out.

## Preview and final

`--preview` swaps in `flux-2-klein-4b` unless a model was named explicitly or
`PREPROMPT_MODEL` is set. `--final` forces `flux-2-max` and **does**
override `PREPROMPT_MODEL`, which is the asymmetry it exists for: the
environment variable is how a session stays in preview, and `--final` is how
one image leaves it for the highest-fidelity model in the table. `vocab-check`
covers it, because `--final` spent a while parsed into
an option nothing read.

## Batches

`--batch N` cycles expression, pose, wardrobe and background pools of different
lengths (7, 6, 8, 9) at strides coprime with each, so 20 consecutive indices
give 20 distinct combinations and the tuple does not repeat for 504 images. The
previous version read four same-length pools at the same index: `--batch 20`
returned each of five combinations four times, every time.

## Scenarios, and lora

The vocabularies, the pools and the composers live in `lib/craft.rb`, which makes no
request and loads nothing from MASTER, so lora can compose on a rented GPU that
has only the repository. lora's sittings go through `sitting_prompt` there, and
its token count against CLIP's 77 does too, so a subject adapter and a
generation read one vocabulary and one budget.

A scenario is a sitting drawn rather than written: expression, pose, wardrobe
and place from the batch pools, a light from `--lighting`, a portrait lens, a
distance of two metres or more, and a film stock by name. Each field turns at
its own stride, so neighbouring scenarios change the light and the place
together. A number is the same sitting on every run. A place never gets a light
it cannot have — no golden hour in a car park at night — because the model
keeps one of the two and drops the other. lora asks for them as a prompt
set named `scenarios`, twenty-four by default or any numbers you name.

A selfie is drawn the same way with the geometry refused: the framing, the
held gaze and the arm stay, the camera stands two or three metres back with the
lens that holds the crop, and the bare word never reaches the prompt, since it
asks for the distortion. Each draws an in-between moment, a place, a light the
place can have and the catchlight that light makes, and neighbours never share
a light. lora asks for forty-eight as `selfies`. The distance ladder is one
sitting at six stated distances, asked for as `distance`, and `vocab-check`
holds both tables to the questions it asks of the scenarios.

## Everything else

Credentials resolve from `REPLICATE_API_TOKEN`, `REPLICATE_API_KEY`, or
`~/.config/preprompt/config.json`. Catalog state defaults to
`~/.cache/preprompt/models.json`. MASTER routes explicit image-generation
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
`MASTER/tools/postpro/postpro.rb`. The `capabilities` command emits the executable
60-item Preprompt/LoRA contract as JSON.

## Keeping the model table honest

`MODEL_CAPABILITIES` is a second source of truth. It exists so an unsupported
option is refused rather than accepted-and-ignored — a request that "works"
while dropping a setting is much harder to notice than a 422 — and the cost of
that is that it goes stale silently: the tests check the table against itself,
so provider drift surfaces in production or not at all.

Neither runs as part of `rake`. Both need the network and a token, and a check
that cannot run says so rather than passing.

**Surveyed 2026-08-25.** Nothing here is broken — `flux-1.1-pro` is live and
carries no deprecation notice. But most of the declared models are a generation
behind what Replicate now leads with, and none of these is named here:

`black-forest-labs/flux-2-max` is BFL's current highest-fidelity image model.
`bytedance/seedream-5-pro` is flagship text-to-image and editing in one.
`google/nano-banana-2` generates fast and edits conversationally.
`openai/gpt-image-2` renders sharp text inside the image. `krea/krea-2-medium`
is expressive illustration, anime and painterly work. `prunaai/p-image`
generates in under a second.

The shape of the field moved as well as the names: editing is now a mode of the
flagship models rather than a separate one, which is a different arrangement
from the single `flux-kontext-pro` path here that requires `--image`. Recraft V4
also emits editable SVG, which nothing in this tool can currently receive.

Adopting any of them decides what the pictures look like, so it stays an
operator call. `schema_suggest` is here so that when the decision is made, the
input keys come off the provider instead of out of somebody's memory — the one
thing that must never be guessed, since guessing them breaks the refusal that
makes the table worth keeping.

## Running it

The last two commands, run from `STUDIO`, hold the model table against the live
schemas and print an entry to paste for a model the table does not have.

```sh
ruby MASTER/tools/preprompt/preprompt.rb generate \
  --prompt "Bergen rain, 35mm documentary photograph" --output .master/media/bergen.webp
ruby MASTER/tools/preprompt/preprompt.rb search flux --limit 100
ruby MASTER/tools/preprompt/preprompt.rb sync --limit 250
ruby MASTER/tools/preprompt/preprompt.rb stats
ruby MASTER/tools/preprompt/preprompt.rb capabilities
ruby MASTER/tools/preprompt/preprompt.rb vocab-check

ruby MASTER/tools/preprompt/preprompt.rb generate \
  --prompt "a fisherman on a dock" \
  --stock hp5 --lens 85mm --distance portrait --camera-height eye \
  --lighting rembrandt --weather drizzle --time-of-day blue_hour \
  --batch 6 --dry-run

cd STUDIO
rake preprompt:schema_audit
rake preprompt:schema_suggest MODEL=black-forest-labs/flux-2-max
```

## Security and trust boundaries

Preprompt is MASTER's provider boundary for image generation. The sensitive edges are credentials, remote API requests, provider-returned URLs, downloaded media, model metadata, and local artifact storage.

- Keep REPLICATE_API_TOKEN, REPLICATE_API_KEY, and equivalent credentials outside prompts, source files, git history, provenance text, and ordinary command output.
- Treat provider catalog entries and schemas as untrusted remote data. Validate identifiers and capabilities before using them to construct requests.
- If a provider returns an output URL that Preprompt downloads, validate the URL and every redirect before connecting. Restrict schemes, block private/link-local destinations, enforce response-size and timeout limits, and never let a provider-controlled URL become an internal network request.
- Never build shell commands from model IDs, prompts, filenames, or provider URLs. Use structured process arguments.
- Write generated artifacts and provenance atomically. Concurrent batches must not produce duplicate or truncated gallery records.
- Treat provider responses, downloaded images, and serialized sidecars as data. Never deserialize arbitrary Ruby objects or execute provider-supplied content.
- If Preprompt is behind a reverse proxy, the proxy and backend must agree on request framing; security controls must not depend on ambiguous HTTP/1.1 parsing.
- If browser authentication is ever added, prefer server-side sessions. If JWTs are introduced, pin the accepted algorithm and key type rather than trusting alg from the token.
- If GraphQL is introduced, bound depth and query cost, authorize fields, and rate-limit batched operations.
- Provider outages, cancellation, and timeouts must remain explicit failures. Security boundaries must not silently fall back to an unexpected endpoint or model.

Subdomain ownership is also part of deployment: hostnames used for generated-media callbacks, galleries, or provider integrations need lifecycle auditing so abandoned third-party DNS targets cannot become trusted-looking content origins.

## MASTER integration

Preprompt lives at MASTER/tools/preprompt and is the canonical image-generation boundary. MASTER owns governance and dispatch; Preprompt owns vocabulary, provider capability mapping, request construction, generation, and artifact provenance.

Canonical examples:

ruby MASTER/tools/preprompt/preprompt.rb capabilities
ruby MASTER/tools/preprompt/preprompt.rb vocab-check
ruby MASTER/tools/preprompt/preprompt.rb generate --prompt "Bergen rain" --dry-run

Use MASTER/tools/preprompt in new scripts and documentation. MASTER/tools/preprompt is a retired path.
