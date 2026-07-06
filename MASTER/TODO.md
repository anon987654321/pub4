# MASTER — remaining work

Actionable backlog for the constitutional runtime. Law is `data/soul.yml` + `data/rules.yml`;
verify against code before starting. Gate with `bin/ci`, `bin/probe all`, and `rake audit`.

## Constitution / rules alignment (`rules.yml` ↔ `lib/`)

- [ ] **`rake constitution` reports ~6368 self-scan violations against `lib/`.** These are MASTER's
      own maximalist rules scanning its own source (it even flags its SQL-injection *detector* as
      SQL injection). Not a release blocker — `bin/ci` excludes it by default — but the number hides
      real signal. Triage into: (a) true violations to fix, (b) rules that should exempt the scanner's
      own rule-definition files, (c) rules to retune. Track the count down over time; don't chase zero.
- [ ] **Enforce `soul.yml` `self_test` in CI.** `rules.yml.self_test` defines laws-apply-to-self
      checks (bare_rescue + timeouts for ROBUSTNESS, nesting_depth ≤ 4 for LINEARITY, god_class
      threshold for ABSTRACTION, etc.). Wire these as an explicit `rake selftest` gate so a
      self-violation fails loudly rather than only surfacing in the full scan.
- [ ] **`SINGULARITY` self-check: no two YAMLs define the same key.** `data/` has ~72 YAML files;
      add a lint that fails on duplicate top-level keys across them (the law already asks for it).

## Defragmentation (`PROXIMITY` / `SINGULARITY`)

- [ ] **`Converge` subsystem is dead weight.** `lib/converge/` + `data/converge_rules.yml` +
      `spec/converge/` is a standalone engine explicitly "not wired into Builder or the 11-stage
      pipeline" (see `lib/converge/converge.rb`); only its own spec loads `converge_rules.yml`.
      Decide: wire it into the pipeline (it duplicates scan/render concerns already in `lib/judge`)
      or delete all three. Deleting is the `DENSITY`-aligned default.
- [ ] **The "rules-like" data files are NOT duplication — leave them split, but document it.**
      `design_rules.yml`→`Master::Design`, `llm_output_rules.yml`→`Judge::OutputCheck`,
      `rule_deps.yml`→`FixLoop`, `rules/{line,file,unit,codebase}.yml`→scanner scopes. Each has one
      live consumer, so merging into `rules.yml` would *worsen* PROXIMITY. Add a short
      `data/rules/README.md` mapping each file → its consumer so the split reads as intentional.
- [ ] **Audit `data/` (72 files) and `knowledge/` (1291 files) for stale corpora.** `knowledge/`
      holds absorbed predecessor dumps; confirm what's still referenced by `lib/` vs. archival, and
      move pure archives out of the hot tree (they inflate scans despite being in `paths.skip_dirs`).
- [ ] **`output/` (371 files) is generated media/artifacts** — confirm it's gitignored and not
      shipped in the gem (`master.gemspec`).

## Web face (`web/`) — the recurring "tap to start does nothing" class

- [ ] **Structural WebGL guard is now in place** (`chat/index.html.erb`: `getContext` returns null
      for `webgl*` until `_primerFired`). This enforces the deferred-boot contract so a stale/eager
      asset can't wedge the main thread before the tap. **Verify it in a real browser** (the sandbox
      headless Chrome can't drive the SSE-holding face page) and keep it — the tap has regressed
      ~5× (930a35ca5, 2faa2ffcd, a9aa0a6f6, f9b6aa57e, …).
- [ ] **Broaden the asset-drift test.** `test_web_ui.rb#test_public_asset_manifest_matches_source_files`
      only checks 5 critical files. Extend it to every JS in the boot manifest (the
      `javascript_include_tag(*%w[...])` list + `particle_kernel` + face parts) so a stale digest
      fails CI. It currently ERRORs (not fails) on a fresh checkout with no precompiled assets —
      make it skip cleanly when `public/assets/.manifest.json` is absent.
- [ ] **TTS end-to-end audio** depends on `edge-tts`/`espeak` on the host (see DEPLOY/TODO.md). The
      web wiring (`/chat/tts*`, jobs, phrases, viseme stream) is correct and returns proper async
      job responses; only synthesis needs the binary.

## Quality debt

- [ ] **`nsaudit` now eager-loads and skips the kernel entrypoint** — keep it in `bin/probe all`.
- [ ] Kernel spine (`kernel/`) and lib spine (`lib/`) both define a `Master::` namespace on
      separate load paths. Document this two-spine design in `IDENTITY.md`/`README.md` so it isn't
      mistaken for a bug (it trips namespace tooling — see the nsaudit skip).
- [ ] Run `rake test:web` and `rake test:integration_web` against a live Falcon in CI (they need a
      running server on `MASTER_WEB_PORT`), not just the static `test_web_ui.rb` source scans.
