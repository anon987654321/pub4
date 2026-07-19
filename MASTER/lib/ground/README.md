# Ground

Axioms, law resolution, memory/evidence store, and sandbox policy rules.

- `rules.rb`, `law_resolver.rb` — kernel-tier rule concepts (not the removed `kernel/` dir)
- `axioms/` — Rails doctrine and platform pillars
- `repo_mining/` — reference cluster catalogs for audits

Loaded early by `lib/master.rb`; most rules are data-driven via `data/rules.yml`.
