# Handoff: Law authority, operational checks, and /fix RAILS

Updated 2026-10-22. The source review began from main at 6214949c1f402d94e8d44e3e895d43eb8e3440be. Always re-read main before continuing; other sessions commit frequently.

## Decision and rationale

A Law and a check are related, but they are not the same kind of thing.

- soul.yml is the constitutional authority.
- laws.yml is the canonical declarative Law catalogue and execution policy.
- MASTER/law/*.rb contains executable constitutional Law definitions and their bad/good fixtures.
- MASTER/lib/review/scan/laws/*.rb and LawDSL provide executable source detectors. LawRegistryAudit is already the reconciliation instrument; its yaml_only, law_only, registry_only, and source_drift populations need to be read rather than hidden.
- MASTER/checks/checks.yml is the operational check-execution registry. It says which class or script runs, in what order, with what preconditions, and which composite covers a leaf. Operator::CheckChain supplies attribution, foreign-dirt handling, staged orchestration, and honest skipped outcomes.

The check registry must not be treated as a competing policy catalogue. A check measures or enforces a requirement; the requirement must remain traceable to the constitutional Law system where it is normative. Some checks measure environment capability or collect evidence rather than encode policy. Do not invent a Law ID for those measurements. Where a check enforces a real expectation and no existing Law explains it, record a coverage gap and propose an evidence-backed Law change through the proper authority process.

On 2026-10-22 gate was renamed to check throughout: Gate/GateChain/GateResult, file names, environment variables and the bin/operator gate alias, which is gone. This adds no second runner or second registry.

The glossary lives at MASTER/docs/synonyms.yml rather than MASTER/data/synonyms.yml because soul.yml marks data/ as a sacred path. No constitutional override was requested, so even adding a new file under that protected subtree would violate the current write boundary. The glossary has no runtime loader and cannot alter authority, IDs, severity, tiers, or machine outcomes.

Do not flatten skipped, inconclusive, and gap into one machine state. Skipped means the instrument did not run or did not measure its target; inconclusive means available evidence cannot settle the result; gap means a required instrument, input, or coverage item is absent. The preferred word in prose can be concise, but machine truth stays precise.

## Architecture simplification follow-through (2026-10-25)

The first Law-reader tranche is committed to `main`:

- `28a39324417f6a8f2562abdd17a7b17bb7592205`: `Fix::ConstitutionalCheck` reads priority Law IDs through `Master.law_entries`, removes the hard-coded fallback list, and blocks clean completion when the catalogue cannot be resolved. A regression test compares the IDs against the canonical reader.
- `68b6ea269c7e24a1ea770f75e43e69ec52303201`: `Fix::LawParity` uses the shared loaders for the catalogue and enforcement overlay and refuses an empty catalogue. A regression test covers the empty case.
- `83a3a9b26b2e9ec704ad6f641d08271fccc68a7b`: `Operator::Ratchets` reads the law-trace ceiling through `Master.law("law_map")`; the existing ratchet test compares it to the declared value.
- `b398fb45fb8112534cddd127ee28d690c06f556c`: `Master::Face::LawField.catalog` delegates to `Master.load_laws`, normalizes the root, and uses an inode/precise-mtime cache fingerprint. Its new test proves the shared loader is called for a custom root.
- `622c8b5`, `c43df95`, `5074f1c`, and `a2864fd`: move the operator's full catalogue declaration lookup into `Operator::LawInventory.catalogue_declaration`; `bin/operator laws` now uses `Master.load_laws` instead of a second YAML read and a local recursive parser. Tests cover the canonical `laws` section, other catalogue sections, key-derived IDs, and empty-catalogue refusal.
- `40b7253` and `d3d0fab`: the derived inventory's council personas also use `Master.load_yaml` rather than opening `council.yml` through an independent YAML call; a focused regression case checks the loader and persona shape.

These are source changes with regression tests added, **not verified test passes**. The Ruby commands have not been run in this session. Run the focused `test_constitutional_check.rb`, `test_law_parity.rb`, `test_ratchets.rb`, `test_face_law_field.rb`, and `test_law_inventory.rb` suites, then reader-singularity and law-trace checks, and record exact output before treating the tranche as verified.

The architecture target is intentionally conservative: one canonical Law catalogue; executable Law definitions and scanner detectors that trace back to it; one scanner/finding contract; one repository-repair coordinator; one transaction path; and one operational check registry/runner. `Core::Fold` and `/fix` are different workflows today. Before merging or deleting any of `FixLoop`, `RepairLoop`, `Kernel`, `Mission`, `RunJournal`, `RunLedger` or `Transaction`, trace their callers and prove rollback, restart, delivery-failure and evidence semantics through tests. Do not edit the sacred `data/` or `lib/review/scan/` paths without the required authorization.

One concrete Kernel boundary needs a measured decision: `MASTER/bin/master replay` exposes `Kernel.replay_cli`, while `test_fix_kernel.rb` directly exercises `Kernel#fix` and the small `Master::Fix::Laws::LAWS` list. The identifier `CAPABILITY_STATUS_MUST_BE_TRUTHFUL` appears both in `law/interface.rb` (currently scoped to `MASTER/lib/operator/services.rb`) and in the primitive kernel's observation-level check over changed files. Those scopes differ, so treat the kernel predicate as defense-in-depth until tests demonstrate a safe shared implementation. This source pass has not proved `Kernel#fix` unreachable across the repository; do not remove it based on the CLI entrypoint alone.

## Verified source facts as of this review

- soul.yml declares version 2.9.1 and includes data/ among the sacred paths. Do not edit it or laws.yml as part of a terminology cleanup.
- laws.yml identifies the canonical Law catalogue and broader execution policy. It should not get a parallel rules: subtree or a new hard/soft/ops schema for this work.
- core/constitution.rb already provides Master::Core::Constitution#admit as the admission point for proposed Effects. It is not the same thing as Operator::CheckChain, which orchestrates repository checks.
- LawRegistryAudit already reconciles executable law definitions and scanner registry entries, and reports source_drift. Use that report to guide any future registry cleanup.
- Amber's checked-in schema currently has version 2026_10_21_230200, which matches the latest migration 20261021230200_add_guest_account_merges_to_amber.rb. The earlier report of schema drift is stale on the reviewed main. Do not touch schema.rb by hand; if later check output shows genuine drift, use the app's migration and schema-dump workflow.
- RAILS/__shared/app/assets/stylesheets/_components.scss is already a short wrapper which imports base and six component partials. Its former 541-line size is stale; the old 541 debt entry has been removed from file_length_ratchet_test.rb. Do not repeat the split. Re-run the real CSS and file-length checks before splitting any other stylesheet.
- Current CSS source still has other historical ratchet rows. Names and old measured values are clues, not current check output; confirm current code-line counts and CSSConstitutionCheck findings before choosing the next file.
- The latest observed commit 6214949 contains a change intended to let the read-only pre-repair proof tolerate other sessions committing. This is not proof that a bounded /fix trial has completed or that repair quality is good.

## P0 — prove the current RAILS state and preserve trial integrity

- [ ] Identify whether a bounded /fix trial is still running, and record its pinned starting SHA, target tree, toolchain identity, Law digest, baseline output, repair output, and terminal state. Do not use a moving branch name as the only trial identity.
- [ ] Run MASTER/bin/operator check --scan-only --tree=RAILS on the actual checkout. Preserve the exact output for schema_migration, release, css_constitution, and rendered/visual status. Do not infer a green result from this handoff.
- [ ] Run the RAILS source checks and check suite on the same tree. If schema_migration is green, keep the schema untouched. If CSS is red, repair the reported files one at a time, re-measure, and compare the full check output before/after.
- [ ] Treat missing browser, closed app ports, missing baseline, and provider-unavailable results as INCONCLUSIVE or SKIPPED according to the existing result contract, never as a source failure and never as green proof.
- [ ] Read the actual rejection and ratchet records from the trial, if they exist: .master/rejections.jsonl, the run ledger, retained run logs, and the named proof envelope. Do not claim a file exists merely because an earlier handoff proposed it.

Rationale: C1 is the reported problem that main starts red, C2 is the reported long proof cycle, and C3 is the reported repair-quality risk. These claims came from a prior handoff and were not re-measured in this source-only review. The bounded trial and its evidence answer those questions; a narrative does not.

## P1 — prove write-path admission and transaction safety

- [ ] Trace every write, stage, and commit path from the actual call sites before writing tests: World Effect execution, Constitution#admit, Master::Io::Base, DiffStager, Committer, Fix::Transaction, rollback/recovery, direct File.write/IO.write and FileUtils mutation paths.
- [ ] Define the property before building the write-path audit. Core::Fold-proposed Effects must pass Master::Core::Constitution#admit before Master::Core::World performs them. Master::Io::Base, DiffStager, Fix::Transaction, Committer, and other /fix mutation sites are distinct write planes with their own guards and transaction responsibilities; they must not be assumed to be literal Core Effects.
- [ ] Instrument representative flows in each write plane and correlate every agent-originated write with the applicable admission/guard decision, normalized path, transactional owner, and outcome evidence. If a write bypasses its intended protection, fix that exact path. Only unify all planes behind Constitution#admit if source tracing proves that is the intended invariant and the shared API can preserve the distinct transaction and staging contracts.
- [ ] Add transaction end-to-end tests after inspecting the existing Transaction API. Cover atomic snapshot ownership, crash recovery, concurrent run serialization, rollback evidence/orphans, attempts to roll back after commit, and rollback on verification failure. Any assumed class or method signature in old notes is unverified until fetched from main.
- [ ] Prove semantic scan coverage: every applicable detector evaluates every target file in scope, and a Law change invalidates cached findings. Verify that FindingCache keys include all inputs a detector reads, including the Law/catalogue digest where needed.
- [ ] Implement or locate a trial-hygiene command that proves baseline and repair share the same source SHA or pinned worktree, laws digest, and toolchain identity. If an earlier artifact exists, inspect and repair it rather than creating a second command.
- [ ] Measure transaction snapshot bytes, elapsed time, and file count with a reproducible baseline. Do not add hand-entered cost estimates to checks.yml; use the existing ledger and measurements.
- [ ] Audit swallowed exceptions, including rescue nil, in load-bearing paths. Separate intentional nil-return contracts from true failure swallowing and make unhandled failure evidence visible.
- [ ] Prove a fresh clone can run the documented setup and canonical Minitest suite. Record actual wall time; the five-minute setup target is a measurement, not an assertion to fake.

Rationale: The central architectural property is one admission decision per Core Effect, not a simplistic replacement of all existing protection layers. Transaction, immutable-path, staging, I/O-tool and commit checks may have different jobs and operate on different APIs. The evidence must prove that each relevant write plane is governed and that the protections compose; it must not manufacture an architectural requirement that all internal writes literally call Constitution#admit.

## P1 — keep DesignSweep inside the transaction boundary

- [ ] Keep the standalone design command out of automatic /fix application until its write/apply phase is transaction-aware. The current standalone runner can commit each kept edit locally; a later check failure cannot undo those independent commits.
- [ ] Design a candidate/apply split: evaluate edits in an isolated candidate representation, validate the whole result, then apply through the existing Fix::Transaction and normal Committer only after admission and verification.
- [ ] Add failure tests showing rejected candidate, failed visual evidence, and failed final verification do not leave partial source changes or stray commits.
- [ ] Do not add a branch or worktree as a workaround. The repository contract says changes land on main; use a temporary disposable copy for any destructive experiment.

Rationale: The visual sweep is useful, but its current commit semantics are not an atomic phase of /fix. Keeping it separate is more honest than saying the full lifecycle is transactional when it is not.

## P2 — consolidate the Law catalogue without inventing a second authority

- [ ] Run LawRegistryAudit and save yaml_only, law_only, registry_only, lexical_unwired, structural_unwired, semantic_only and dep_graph_gaps. Resolve each drift with an explanation backed by source and tests.
- [ ] Audit each check/check for whether it is a policy assertion, a factual measurement, an environment precondition, or a composite. Link policy assertions to real existing Law IDs when the mapping is accurate; record unmapped normative checks as coverage gaps instead of fabricating IDs.
- [ ] Define an enforced registry schema only after the audit shows which fields are necessary. Do not add parallel rule registries, a rules: subtree, or undocumented severity/tier values.
- [ ] Keep LawDSL positive and negative fixtures for every new detector. Run the fixture test, registry audit, law inventory, and autofix reach report whenever scanner registration changes.
- [ ] Inspect the real Law Definition contract before adding metadata. Proposed fields such as provenance, counter_law, rationale and last_reviewed are not proven requirements of the current schema; adding them must include migrations/schema validation, consumers, fixtures, and stale-data policy.
- [ ] If law review age matters, implement a report (for example, older than 90 days) only after there is a trusted, machine-readable review timestamp and a deterministic lint result.

Rationale: A detector ID, a constitutional Law ID, a check ID, and a test name can all be different identifiers because they answer different questions. The goal is traceable one-source policy, not false one-to-one identity or a global class/file rename.

## P2 — RAILS/CSS follow-through

- [ ] Confirm the component partial order and output with the existing CSS bundle and visual/source tests. The _components.scss wrapper currently includes base, forms, overlays, feedback, fields, progress_and_uploads, and content_controls in order.
- [ ] Use the real CSS check and current source line counts to select the next oversize candidate. Do not split _surface_chrome_endgame.scss or _minimal.scss from stale historical numbers alone.
- [ ] After each CSS split, compare all check output, keep cascade order, then lower/remove the exact ratchet entry. No line-count ceiling should be raised just to get green.
- [ ] Run the complete release composite after source blockers are resolved. Diagnose browser evidence separately from schema/CSS source defects.
- [ ] Centralize RailsApp detection only if a source trace confirms meaningful duplication among rails_app.rb, visual_pass, RailsProof and the RAILS/<app>/fix.yml profiles. Add tests before delegating callers.

## P2 — glossary, help, and contributor polish

- [x] Add a glossary-only vocabulary file outside sacred data/, clarify Law/check/proof/result-state terms, and state that the execution registry has no policy authority.
- [x] Make bin/operator check the one user-facing command for the ladder.
- [x] Keep shell completion and its Minitest drift check in sync with both spellings.
- [x] Add a Minitest contract that keeps checks.yml limited to execution metadata, preventing policy IDs/severity/tiers from silently growing into a parallel Law catalogue.
- [ ] Run rake docs:agent_contracts and rake lint:agent_contracts on a real checkout after synchronizing the generated agent files.
- [ ] Consider man pages for vocabulary and the write path only if they become the single source for command/help generation; avoid a second prose source.
- [ ] Derive CLI help from canonical command/docs once the existing registry supports it and test for drift rather than hand-maintaining another help list.
- [ ] Measure cold-start time before setting a 200 ms version-command ratchet. A target without a baseline is aspirational, not evidence.
- [ ] Keep commit subjects aligned with MASTER/data/commit_format.yml.

## P3 — test whether self-regeneration pays for itself

- [ ] Choose the smallest grain with a stable API and clear behavior (the prior proposal names ProseMetrics, which must be verified to exist and be suitable).
- [ ] Write a behavioral specification and independent oracle before deleting implementation. Run the deletion experiment only in a disposable copy outside the shared working tree.
- [ ] Measure regeneration tokens, wall time, human correction, and behavioral-evaluation pass rate. Compare regeneration cost to careful maintenance.
- [ ] Only generalize to neighboring grains if the smallest experiment succeeds or shows a measured positive return. A governed, non-regenerative MASTER remains a valid result if that is what the evidence supports.
- [ ] Treat whole-harness self-regeneration as long-range research, not a completion criterion for the current /fix repair.

## Verification commands to run on the real checkout

1. From the repository root: MASTER/bin/operator check --scan-only --tree=RAILS
2. From MASTER: rake lint:agent_contracts; rake test; the law fixture and registry audit tasks found in the current Rakefile.
3. From RAILS: run the focused file-length ratchet and CSS source-check tests using the app's documented bundle.
4. Run the bounded /fix trial with its SHA, Law digest, and toolchain identity recorded; capture its terminal report and rejection outcomes.
5. Re-run the checks after fixes, and report PASS, FAIL, INCONCLUSIVE, or SKIPPED with command output. Do not claim unexecuted validation.

## Guardrails

- Read soul.yml, then laws.yml, then executable laws and scanner laws before future MASTER policy changes.
- data/ and MASTER/lib/review/scan/ are sacred under soul.yml; do not modify these paths absent an approved constitutional override.
- Keep one Law authority, one registry of check execution, and one runner. No second rules registry.
- No mass Check-to-Check class/file rename in this pass.
- No runtime vocabulary loader, no fake Law IDs, no unvalidated hard/soft/ops tiers.
- Do not use Vercel or GitHub Actions as a substitute for local verification.
- Do not call the repair finished until the real tests, check outputs, and bounded trial provide evidence.
