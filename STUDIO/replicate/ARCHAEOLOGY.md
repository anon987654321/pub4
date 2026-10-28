# Replicate / Repligen archaeological recovery record

Scope: `anon987654321/pub`, `pub2`, `pub3`, and the live `pub4/STUDIO/replicate` line. The earlier product name was **Repligen**. In `pub4` history it was renamed wholesale to **Preprompt**, then the current tool settled as **Replicate**. The live directory and executable are `STUDIO/replicate/replicate.rb`. This record preserves the old product ideas and exact lineage while distinguishing implemented behaviour from old assumptions that are no longer safe.

## Historical wording and product intent

`pub2` opened with:

> This is creativity at the speed of thought. Every prompt becomes a cascade of visual possibilities. Every chain unlocks exponential creative potential.

`pub3` described Repligen as a “Universal AI workflow engine” for model discovery, LoRA training, chained generation, local search and cost tracking. Its user journey was to generate, save, optionally post-process and deliver the final output. These phrases describe the ambition; old pricing claims, provider model names and counts were examples from their time, not reliable current data.

## Archaeological trail

### `pub`: early Replicate use

The older repository has Replicate references in the assistant code and older media/model integrations, but no dedicated current Repligen product tree comparable to the later versions. It establishes upstream usage rather than a fully separate implementation.

### `pub2`: Repligen v7.3.0 — creative pipeline and durable local index

Sources:
- [repligen.rb](https://github.com/anon987654321/pub2/blob/main/repligen/repligen.rb)
- [README](https://github.com/anon987654321/pub2/blob/main/repligen/repligen_README.md)
- [model scraper](https://github.com/anon987654321/pub2/blob/main/repligen/scrape_models.rb)
- [Explore-page scraper](https://github.com/anon987654321/pub2/blob/main/repligen/scrape_replicate_explore.rb)
- [bootstrap and fallback commit](https://github.com/anon987654321/pub2/commit/08ce8802f9374ed62e9d1be61c664d2bf6b53bb8)

The v7.3.0 material specified named `quick`, `video`, `full`, `creative` and `chaos` workflows; model-specific request formatting; output filenames with source/chain/time; cost checks; batch generation from prompt files; postpro handoff; LoRA training; SQLite operation history; caching/deduplication; retry/backoff and timeout handling; progress/webhook ideas; and a fallback when SQLite or Ferrum was unavailable. The README was duplicated at both `repligen/` and `multimedia/`; it is historical duplication, not a current directory contract.

The old setup could attempt to install gems at runtime and persisted a Replicate token under `~/.config/repligen/config.json`. Current Replicate deliberately keeps dependency installation out of an ordinary run and stores credentials only in user configuration or the environment.

The old model/scrape cost figures and model chain examples (Imagen3, Wan, MusicGen, Real-ESRGAN and others) were documented as estimates, not schema evidence. They must not be reintroduced as defaults: the present system's central rule is to refuse a parameter or stage it cannot substantiate before spending money.

### `pub3`: the interactive orchestrator and split tools

Sources:
- [Repligen README](https://github.com/anon987654321/pub3/blob/main/multimedia/repligen/README.md)
- [interactive usage and menu](https://github.com/anon987654321/pub3/blob/main/multimedia/repligen/USAGE.md)
- [interactive implementation](https://github.com/anon987654321/pub3/blob/main/multimedia/repligen/repligen.rb)
- [CLI wrapper](https://github.com/anon987654321/pub3/blob/main/multimedia/repligen/bin/repligen)
- [chain command](https://github.com/anon987654321/pub3/blob/main/multimedia/repligen/bin/repligen-chain)
- [sync command](https://github.com/anon987654321/pub3/blob/main/multimedia/repligen/bin/repligen-sync)
- [search command](https://github.com/anon987654321/pub3/blob/main/multimedia/repligen/bin/repligen-search)

The interactive menu had Generate with LoRA URL, Sync models, Search models, Show statistics, Run chain workflow and Exit. The README also documented scraping a very large catalogue, random 8–20 stage “masterpiece” chains, 5+ image LoRA training, SQLite full-text search and cost monitoring. The utility decomposition is valuable; the specific browser scraper and its historical count are not a source of truth.

### `pub4`: Repligen → Preprompt → Replicate

The intermediate rename is a substantive part of the history, not merely a spelling change.
The [rename commit](https://github.com/anon987654321/pub4/commit/f048de714a26ca972707b5abe8aafe8559aa21c3)
states that Repligen “named a service it called” while Preprompt named the tool's job of
composing prompts and the model chains they feed. It deliberately removed aliases across the
directory, entry point, module, tests, rake tasks, slash-command route, postpro handoff,
environment variables, cache/config paths, deployment path helper and CSS class. The rename
also warned that an old `REPLIGEN_*` setting left on the VPS would stop applying silently.
The current `Replicate` name describes the provider-facing tool; neither old name should
be revived as a second executable or hidden compatibility alias.

The [reference-upload fix](https://github.com/anon987654321/pub4/commit/f6de2e2d0b60c7225dbbfaacb51dad7d0c9f15bb)
is another important invariant: a local path is not a URL. A provider accepts remotely fetchable
HTTPS/data references, not a developer's filesystem path; upload local images exactly once,
pass already remote URLs and `data:` URIs through unchanged, and make dry-runs free. The
same requirement applies both to one-shot image editing and inherited images inside chains,
because discovering the defect after the first stage could leave a paid prediction behind.

The [chain-validator correction](https://github.com/anon987654321/pub4/commit/be7c57109a1883f332de9792a61e83dcf9347474)
records why stage validation must use each model's real input vocabulary: FLUX 2 accepts plural
`input_images`, while earlier editors used singular `input_image`. Refusal must be based on
the specific model schema, not a guessed universal key.


The present implementation lives at `STUDIO/replicate/replicate.rb`; `MASTER/tools/replicate` is a compatibility symlink. Main components:
- [replicate.rb](./replicate.rb): CLI, vocabularies, capability/request construction and offline `vocab-check`;
- [craft.rb](./craft.rb): structured prompt composition without a provider call;
- [client.rb](./client.rb): authenticated provider calls, request budget/retries, polling, uploads/downloads and billing ledger;
- [chain.rb](./chain.rb): whole-chain preflight and staged hand-off;
- [chains/](./chains/): reviewed YAML chain plans;
- [lora/README.md](./lora/README.md): subject-specific training and generation lanes.

The present README describes the supported `generate`, `vocab-check`, `capabilities`, `chains`, `search`, `sync` and `stats` paths. The catalogue sync/search supersedes scraping; the JSON cache supersedes a local SQLite catalogue; the billing ledger, atomic writes, content-addressed artifacts, checksums, provenance sidecars and gallery JSONL provide a better audit trail than a loose database row.

## Historical capabilities: present-day disposition

| Earlier capability / rule | Current disposition |
| --- | --- |
| Generate from prompts and a model URL | Preserved as a non-interactive CLI/API boundary; structured prompt composition is handled by `craft.rb`. |
| Interactive REPL/menu | Intentionally replaced by scriptable CLI commands and MASTER's natural-language routing. Do not put an interactive loop in a file that tests must be able to require. |
| Model discovery, sync, local search and stats | Preserved through provider-backed `sync`, local `search`, `stats` and a bounded JSON cache. The old Ferrum Explore-page scraper is not needed for the normal path. |
| SQLite model database and full-text search | Superseded by the bounded JSON catalogue cache and the explicit provider API. Historical SQLite ideas (incremental update, offline lookup and stats) remain the requirements to preserve. |
| Random 8–20 stage chains and named quick/creative/chaos profiles | Evolved into reviewed YAML chains and the `Chain.problems` preflight. Do not revive uncontrolled random model sequences; stage compatibility is validated before any paid request. |
| Video and full multimedia chains | Not a current Replicate CLI contract. The old model names and price estimates are stale, and a model's presence in an archive does not establish that its current API schema exists. Keep this as a future capability proposal with verified schema, output type, cost, and artifact tests before adding stages. |
| LoRA training from several photographs | Preserved in `STUDIO/replicate/lora`, with distinct hosted, Kaggle, Colab and local/RunPod lanes and their own budget/checkpoint rules. |
| Automatic Postpro handoff | Preserved as the default portrait grade; `--no-postpro` explicitly opts out. The grade belongs to Postpro, not another provider-specific effects engine. |
| Token discovery and config file | Preserved through `REPLICATE_API_TOKEN`, `REPLICATE_API_KEY` and user-scoped `~/.config/replicate/config.json`; no credentials in repo. |
| Retry, progress, timeout and cost controls | Preserved/evolved in the provider client and ledger. Do not blindly replay an ambiguous paid POST; retry policy must be status-aware. |
| Output naming and operation audit | Evolved into content-addressed blobs, checksums, per-output provenance, sidecars and gallery rows, with atomic writes and no partial artifact after failed download. |
| Prompt batches and variation diversity | Preserved through batch vocabularies and deterministic coprime strides; regression checks prove 20 consecutive combinations are distinct. |
| Browser-based scraping as a fallback | Not restored as the primary implementation: it depends on undocumented page markup, can drift, and must not be a credential or model-schema authority. The provider API is the intended catalogue source. |
| Runtime gem installation / shell download snippets | Intentionally not restored. Execution is observational unless an explicit setup command is invoked; shell arguments are not composed from prompts, filenames or model IDs. |

## Contracts that must not regress

1. **Refuse rather than silently drop.** Each model has its own input names and bounds. A successful HTTP response does not prove that a requested option reached the model.
2. **Preflight the whole chain.** Validate every stage and all inheritance/input keys before the first paid request. A later invalid stage must not be discovered after earlier stages spend.
3. **Treat metadata and provider output as untrusted.** Do not construct shell commands from model IDs or prompts. Restrict downloads to HTTPS and approved hosts; stream under byte caps and write atomically.
4. **Keep spend and provenance together.** Record the exact stage/model, input provenance, seed, schema/recipe revision, elapsed/billed time, output checksum and failure/cancellation status. Secrets never enter logs, prompts, manifests or sidecars.
5. **Make absence explicit.** Missing token, unsupported output type, unverified input schema, timeout, cancellation and empty provider output are distinct failures; do not substitute another model silently.
6. **Separate inventory from readiness.** A catalogue listing or historical README claim is not proof of a currently executable, verified model. Promotion requires schema evidence and a regression test.

## Validation boundary

Run from `STUDIO/`: `ruby replicate/replicate.rb vocab-check`, `ruby replicate/replicate.rb chains`, the Replicate client/chain and schema audit tests, and `rake check test`. A credentialed `rake replicate:schema_audit` is separate from offline validation; without a token the result is not “verified”. Do not run generation or LoRA training merely to prove the code path, because those requests spend credits.
