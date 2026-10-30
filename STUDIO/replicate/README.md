# Replicate

The earlier Repligen versions and the decisions behind this stricter runtime are mapped in [ARCHAEOLOGY.md](./ARCHAEOLOGY.md), including which historical workflows are preserved, evolved or intentionally not revived.

**A photograph is a set of decisions, and replicate makes each of them nameable.** Film
stock, lens, light, weather, hour, distance and focus become words the tool knows, so a house
style is a handful of flags and not a paragraph someone has to remember. The tool refuses what
a model cannot do, and nothing leaves it ungraded unless you say so.

Replicate is STUDIO's noninteractive boundary to the Replicate image service. It generates
images, downloads a result when an output path is asked for, searches the provider catalog,
synchronises a bounded local copy of it, and reports statistics on that copy. It never
installs gems, scrapes the website or stores credentials in the repository. Credentials come
from `REPLICATE_API_TOKEN`, `REPLICATE_API_KEY` or `~/.config/replicate/config.json`, and the
catalog cache defaults to `~/.cache/replicate/models.json`. MASTER usually chooses the tool
from natural language, so nobody needs to type these commands; they stay useful for
diagnostics, and the last section lists them.

The entry point is `replicate.rb`. Beside it, `craft.rb` holds the vocabularies and the
composers and makes no request, so a rented GPU with only the repository can still compose a
prompt. The file `client.rb` is the provider client, with retries, spending caps and the
billed-seconds ledger. The file `chain.rb` runs several models in a row, and `chains/` holds
the chains that ship: `flux2_consistency.yml`, `relight_portrait.yml` and
`structure_ladder.yml`. The `atomic_write.rb` and `script_dispatch.rb` files are small helpers
for safe writes and for handing a finished file to another STUDIO tool. The `lora/` folder
beside them has its own README.

## Structured fields

The free-text `--prompt` is the subject. Everything else about the photograph composes onto it
from named vocabularies. `vocab-check` reports the current sizes, and at the time of writing
there are twenty-three film stocks, fourteen lenses, twenty lighting setups, twelve kinds of
weather, eleven times of day, eight distances, seven camera heights, six compositions and four
focus modes. Spelling is normalised for case, hyphens and spaces, so `--time-of-day
Golden-Hour` finds `golden_hour`. An unknown value aborts and prints the valid ones, because a
silent no-op once produced a prompt with no film stock in it after the generation had been
paid for.

The distance also decides the aspect ratio unless `--aspect-ratio` overrides it, so a close-up
is 4:5 and an establishing shot is 16:9. Two fields that describe incompatible light, such as
golden hour at night, produce a warning and not a refusal, because a neon sign at midday is a
real photograph. A prompt that says "8k", "artstation" or "flawless" is also warned about,
since those words pull a picture toward concept art and retouched skin.

The command `vocab-check` verifies all of this without an API call. Every key must be
reachable after normalisation, every distance must map to a ratio, every model's negative
prompt key must exist among its own input keys, and every declared input must be fillable by
something in the request builder. It prints a count of models and problems and fails on any
problem.

## Generative audiovisual direction

The creative direction extends beyond still-image prompting. Generative typography,
real-time audiovisual instruments, procedural motion and experimental filmmaking
are first-class research directions. The reference is the creator profile and
description supplied by the operator: TouchDesigner-based systems, audio-reactive
typography, reusable project files, generative AI, computer vision and experimental
film. This is inspiration for original work, not a request to copy paid project files
or reproduce an individual artist's work.

A generated sequence should be treated as a temporal composition rather than a
stack of unrelated frames. A scene brief should name its subject, visual motif,
typographic role, motion behaviour, camera movement, lighting evolution, sound
relationship and transition intent. The compiler should preserve those decisions
as structured fields and provenance, not bury them in an opaque prompt paragraph.

Prefer reusable instruments over one-shot tricks: expose bounded controls for
particle fields, feedback, displacement, typography, optical motion, depth and
audio response. Audio analysis should drive intentional parameter curves and
events, not merely add random pulsing. A system should remain coherent when its
duration, tempo, aspect ratio or input reference changes.

For image-to-video work, establish the visual anchor first, then plan the motion
and temporal events, generate a preview, inspect temporal consistency, and only
then spend on a final render. Grade the finished sequence through the existing
Postpro motion path so the still and video looks share one photographic authority.
Record model/version, seed, references, scene fields, motion controls, audio
analysis and post-production settings with each artifact. A technically valid
clip is not automatically a finished composition.

## Models and refusals

`MODEL_CAPABILITIES` in `replicate.rb` records what each model accepts, checked against live
schemas and not remembered. Its purpose is to refuse an unsupported option rather than accept
it and ignore it, because a request that works while dropping a setting is far harder to
notice than a rejection. The guidance and step knobs are model-relative: the models disagree
on both the spelling and the range, and a figure outside the chosen model's range is a refusal
and not a clamp. The edit model `flux-kontext-pro` requires `--image`, and a generate call
without one fails and does not fall back to text-to-image.

No model in the table takes a negative prompt. The tool asks for the opposite in the
affirmative and says so on stderr, and the provenance sidecar records whether a negative was
actually sent. The flag `--preview` swaps in a small fast model unless a model is named or
`REPLICATE_MODEL` is set. The flag `--final` forces the highest-fidelity model in the table and
overrides the environment variable, which is how one image leaves a preview session.

The table goes stale silently, because the tests check it only against itself. Two rake tasks
hold it against the network, `replicate:schema_audit` and `replicate:schema_suggest`, and
neither runs as part of the default `rake` because both need a token. A check that cannot run
says so and does not pass. Adopting a newer model decides what the pictures look like, so it
stays an operator call; the suggest task exists so that when the decision is made, the input
keys come off the provider and not out of somebody's memory.

## Batches, scenarios and chains

A batch cycles expression, pose, wardrobe and background pools of different lengths at strides
coprime with each, so twenty consecutive indices give twenty distinct combinations. A scenario
is a sitting drawn and not written: those pools, a light, a portrait lens, a distance of two
metres or more, and a film stock by name. A place never receives a light it cannot have, and
a number is the same sitting on every run. Selfies and the distance ladder are drawn the same
way, and lora asks for them by name, so a subject adapter and a plain generation read one
vocabulary and one budget against CLIP's seventy-seven tokens.

A chain passes a frame through several models that each hold a different invariant, such as
depth, edges or a character across references. The command `chains` lists the shipped chains
and their plans, and `chain NAME --dry-run` validates the whole chain before anything is spent,
because a failure at stage six that stage two could have predicted is a real bill. A failed
chain appends a row to a manifest with what it kept.

## Grading and provenance

Every output is graded by postpro unless you turn it off. The default preset is `portrait`,
because replicate mostly makes faces and generated skin is too clean; the grain is the
direct answer to that. Change it per run with `--postpro PRESET`, per shell with
`REPLICATE_POSTPRO`, and switch it off with `--no-postpro` when another tool will grade the
file later. The look itself is postpro's to define.

Generation returns provider URLs unless `--output FILE` is supplied. When saving to a path,
the extension controls the requested bytes: `.jpg`/`.jpeg` request `jpg`, `.png` requests
`png`, and `.webp` requests `webp`. Without an extension, WebP remains the default; unsupported
extensions are refused before the provider call. Chain stages derive the same setting from their
actual stage-output path so intermediate files are not mislabeled.

Each saved output gets a content-addressed blob, a checksum, a provenance sidecar and a line in
`.master/media/gallery.jsonl`. The sidecar stores the actual prediction ID, provider version,
status and provider metrics returned by Replicate; `owner/name` alone is not enough to reproduce
an image after the provider moves its `latest` pointer. The gallery's alt text describes the subject, the crop, the
camera height and the background, which is what the image is of, and not the compiled prompt,
which is how it was made. Missing credentials, missing outputs, provider failures,
cancellation and timeouts are explicit failures, and the tool never substitutes a model
silently.

## Trust and MASTER

Provider schemas, catalog entries, URLs, prompts, images and model identifiers are untrusted
data. Downloads accept only HTTPS from an allowed host list, are streamed under a byte cap and
leave no partial file on failure. Shell commands are never built from model identifiers,
prompts or filenames. Tokens stay out of prompts, sidecars and command output, and artifacts
and gallery records are written atomically so concurrent batches cannot leave a truncated one.

MASTER governs routing and lifecycle, and STUDIO owns dispatch and media production. Replicate
owns vocabulary, model mapping, request construction and artifact provenance. The tool is
reached at `STUDIO/replicate/replicate.rb`, and `MASTER/tools/replicate` is a compatibility
symlink to it.

The `capabilities` subcommand reports STUDIO's shared catalogue of analogue directions; it is
not the provider-schema table for Replicate models. The catalogue distinguishes presence from
readiness: `catalog_complete: true` means the expected inventory is present, while
`complete: false`, `status: "unverified"` and `enabled: null` mean implementation support has
not been independently established for those entries. Do not treat a catalogue key as a usable
feature. Provider request support is defined separately by `MODEL_CAPABILITIES`, the offline
`vocab-check`, and the credentialed `rake replicate:schema_audit`.

## External discovery and creative providers

The model catalogue is deliberately provider-neutral. Two external resources are useful at different stages, but neither is a substitute for the existing Replicate client.

[OpenArt MCP and CLI](https://openart.ai/mcp/) exposes image and video generation, model discovery, references, result tracking, and an account library to an explicitly authenticated agent. The documented MCP endpoint is `https://mcp.openart.ai/mcp`; sign-in uses OAuth, and generations spend credits from the connected OpenArt account. Its [official CLI source](https://github.com/OpenArt-AI/cli) is another local integration route. Treat OpenArt as an optional, user-authorized creative provider for reference boards, consistent character exploration, image-to-video experiments, and music-video concepts—not as a hidden default or a free backend. Keep credentials outside the repository, make credit-bearing calls explicit, and preserve the user's reference assets and approval boundary. Review the installer and pin a reviewed release before adopting the CLI; do not pipe a remote install script directly into a shell on hardened hosts.

[GitHub Signals](https://githubsignals.io/) is a searchable open-source project index with topic pages, direct upstream links, and public CSV/RSS exports ([CSV](https://githubsignals.io/export.csv), [RSS](https://githubsignals.io/feed.xml)). Use it as a discovery feed for image, audio, video, 3D, agent, and model tooling—not as an authority on quality, licence, safety, or compatibility. The archive can suggest candidates for Replicate catalog and chain work, while the upstream repository remains the source of truth.

A safe intake path is: record the discovery URL and date; inspect the upstream source, licence, recent maintenance, dependency tree, and model/data terms; run a dry-run or schema test; pin the exact revision or model version; then add only verified capabilities to this tool's catalogue and provenance records. A listing, README, social video, or generated demo is a lead, not evidence that the software or model is ready for production. Discovery must not install or execute projects, spend credits, download model weights, or change the default provider by itself.

## Commands

Run these from the repository root. The last two need a token and the network.

```sh
ruby STUDIO/replicate/replicate.rb generate --prompt "Bergen rain" --dry-run
ruby STUDIO/replicate/replicate.rb generate --prompt "a fisherman on a dock" \
  --stock hp5 --lens 85mm --distance portrait --lighting rembrandt --batch 6 --dry-run
ruby STUDIO/replicate/replicate.rb vocab-check
ruby STUDIO/replicate/replicate.rb capabilities
ruby STUDIO/replicate/replicate.rb chains
ruby STUDIO/replicate/replicate.rb search flux --limit 100
ruby STUDIO/replicate/replicate.rb sync --limit 250
ruby STUDIO/replicate/replicate.rb stats
cd STUDIO && rake replicate:schema_audit
```
