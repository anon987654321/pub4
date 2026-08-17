# MASTER

Constitutional AI runtime in Ruby, OpenBSD-first. Models propose; the constitution validates before durable writes. The web face in `web/` mirrors pipeline state at `https://ai.brgen.no`.

Local boot: `bundle install`, then `bundle exec ruby bin/cli`. Work is a sentence. Slash set: `/through` `/status` `/undo` `/commit` `/model` `/pair` `/doctor` `/help`. Law is `data/soul.yml` and `data/rules.yml`. Deploy: `OPENBSD/RUNBOOK.md`. Licensed MIT.

Start with `AGENTS.md` (task-scoped agent entry) or `START_HERE.md` (full contract). Use `EXAMPLES.md` for patch shapes. Checks: `bin/check`, `--profile=agent`, `--profile=web`, `--profile=full`, `--format=brief`.

## Creative media, without command syntax

The chat router recognizes explicit creation requests before the normal agent turn. Ask in plain language: “generate a photo of Bergen in rain,” “make a Dilla beat,” “create a Bach-inspired instrumental,” or “give `/path/photo.jpg` a VHS look.” Image requests route to Repligen when `REPLICATE_API_TOKEN` is available; beats route to Dilla Lab; explicit grading requests route to Postpro. Outputs are written outside the tracked source tree. Missing input or provider credentials produce an explicit error.

The implementation is intentionally narrow: discussing J Dilla or photography remains a normal chat turn. Advanced users can invoke the Repligen and Postpro tools directly.

One spine, one loader. `lib/` is the application runtime; the constitutional fold lives inside it at `lib/core.rb` + `lib/core/` under `Master::Core::`, autoloaded by the same Zeitwerk loader as everything else. It depends on nothing in `lib/` outside its own namespace, which `test/core/test_no_lib_backedges.rb` holds. The two-spine split ended 2026-08-12 — see `DECISIONS.md`.
