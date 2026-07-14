# MASTER

Constitutional AI runtime in Ruby, OpenBSD-first. Models propose; the constitution validates before durable writes. The web face in `web/` mirrors pipeline state at `https://ai.brgen.no`.

Local boot: `bundle install`, then `bundle exec ruby bin/cli`. Pipeline stages are in `Now::RuntimeMode::PIPELINE_STAGES`; dump with `/orient`. Law is `data/soul.yml` and `data/rules.yml`. Deploy: `OPENBSD/RUNBOOK.md`. Licensed MIT.

Start with `START_HERE.md` (agent contract, runtime map, data file budget). Use `EXAMPLES.md` for patch shapes. Checks: `bin/check`, `--profile=agent`, `--profile=web`, `--profile=full`.

## Creative media, without command syntax

The chat router recognizes explicit creation requests before the normal agent turn. Ask in plain language: “generate a photo of Ragnhild in Bergen rain,” “make a Dilla beat,” “create a Bach-inspired instrumental,” or “give `/path/photo.jpg` a VHS look.” Ragnhild routes to the local FLUX LoRA and passes the exact prompt to its sampler; beats route to Dilla Lab; explicit grading requests route to Postpro; other image requests route to Replicate when `REPLICATE_API_TOKEN` is available. Generated media is local runtime state under `.master/media/`; no tool writes into the tracked source tree. A request will report a missing input, LoRA checkpoint, or provider token instead of silently substituting an unrelated result.

The implementation is intentionally narrow: discussing J Dilla or photography remains a normal chat turn. Advanced users can still use `/lora-generate`, `/repligen`, and `/postpro`.

Two spines share the `Master::` namespace intentionally. `lib/` is the application/runtime spine loaded by the gem and the CLI. `core/` is a small constitutional fold spine (`Master::Core::`) loaded on its own path by `bin/master-core` and the core tests. Because it lives under `Master::Core::` (not top-level `Master::`), it coexists with `lib/` in one process without constant collisions.
