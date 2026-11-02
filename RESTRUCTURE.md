# RESTRUCTURE.md — pub4 consolidation, cleanup and restructuring proposal

**Status:** Executed 2026-11-02 (operator-approved): Phase 0 tag `consolidation-20261102`;
root shims retired (8171130cb); FULL.yml + the recovery assessment retired (92bf64485);
FETAT.md relocated (7357a5f7d); mrdamascy promoted (c5a176b4c); contracts and ownership
extended (e7ddfeb01, dde802564). NOT executed, deliberately: the TODO.md session-log split
(operator asked for direct work instead of new TODO surfaces), and Phase 4's git-LFS
conversion (it rewrites history; the fetch-at-deploy variant is the acceptable path).
**Prepared:** 2026-11-02, from a full-repo audit at `main` = `9424bcac5`.
**Verification basis:** every claim below was checked against the live tree and git
metadata on 2026-11-02; commands are given so each claim can be re-verified.

---

## 1. Executive summary

pub4 is five trees (MASTER, RAILS, OPENBSD, STUDIO, replicate) plus a root governance
layer, governed by `MASTER/AGENTS.md` → `TREE_CONTRACTS.md` → `PATH_OWNERSHIP.yml`,
with `cd MASTER && bundle exec ruby bin/check` as the enforcement spine. That spine is
good. The problems are around it:

1. **The branch/PR era ended but its debris stayed.** On 2026-11-02 all 15 remote
   branches were folded into `main` and deleted, and all 8 open PRs (#859–#867) were
   resolved (one truly merged, seven closed with provenance comments). This proposal
   covers what that sweep exposed but could not fix.
2. **Root is the messiest tree.** Two root files duplicate STUDIO files *with divergent
   content* (`output_paths.rb`, `subprocess.rb`), two 1–3 MB ungoverned documents sit at
   root (`FULL.yml` 3,000 KB, `FETAT.md`), and `TODO.md` has degenerated into a
   1,120-line session log that no one can act on.
3. **An eighth Rails app is hiding in a junk drawer.** `RAILS/__other/mrdamascy/` is a
   complete app (171 tracked files: models, controllers, migrations, PWA assets) living
   under a name that says "not an app".
4. **Heavy ML binaries are in normal git.** 13.1 MB onnxruntime WASM + 8.5 MB ONNX
   model + 1.9 MB face mask + 2 MB webfonts are commit history weight forever.
5. **Generated artifacts are versioned next to their sources.** `FULL.yml` (generated
   rule corpus) and `MASTER/docs/history/recovery/full_yml_assessment.yml` (395 KB
   assessment copy) are snapshots, not sources.

The plan is four phases, each independently landable as path-scoped commits straight to
`main` per the declared workflow, each with a `bin/check` gate.

## 2. State of the union (verified 2026-11-02)

| Tree | Files | Size | Role |
|---|---|---|---|
| MASTER | 2,238 | 15.4 MB | Constitution-as-code, checks, core runtime gem |
| RAILS | 3,300 | 54.4 MB | 7 named apps + `__shared` gem + `__other` + shared tests |
| OPENBSD | 283 | 1.2 MB | Fleet scripts, runbooks, host checks |
| STUDIO | 18 | 0.2 MB | Dilla, photograph, replicate tooling |
| replicate (root) | 1 | <1 KB | Single `client.rb` |
| root | 16 files | 3.2 MB | Governance doors + 2 large ungoverned docs |

RAILS internals by weight: `brgen` 968 files, `__shared` 585, `amber` 402, `master` 262
(the Rails face of MASTER), `bsdports` 187, `brgen_marketplace` 166, `brgen_radio` 165,
`__other` 171, shared `test/` 206, `brgen_messenger` 63, `brgen_dating` 59,
`brgen_maps` 24.

Git state after the 2026-11-02 sweep: one branch (`main`), zero open PRs, tags
`v0.1`, `v1.0`, `dilla-v0.1`, `dilla-engine-final` preserved as the only archaeology
anchors. `main` history is 19-commit re-cut lineage plus the consolidation commits;
the 26k-commit pre-cut history exists only in the old tags' ancestry, unreachable from
`main`.

## 3. What the 2026-11-02 consolidation did (for the record)

- **Real merges:** `fix/fold-readonly-probes-and-task-routing` (PR #867 → merge commit
  `82993840f`), `retain-original-logo` (→ `1a93b698d`).
- **Cherry-picked onto main:** Dintero key dedupe (#859 → `9d6a7b5f2`), post-card
  unification + cache budgets (#861 → `afc1764f7`), geo coverage tests (#863 →
  `c87a5733f`), affiliate behavioral tests (#865 → `5267f2058`), empty-state String
  actions deprecation + test (#864 → `2bf077209`, `aad3d869a`).
- **Skipped as already contained (verified byte-for-byte or superseded):** bsdports
  Solid Queue/Cache config (#860), marketplace paid-order extraction + test (#862 —
  main's implementation is strictly newer), cache-scope tightening (#864/#865 shared
  commit — already landed inside `afc1764f7`), geo extraction itself (#863 — main has
  the same helpers in `degrees_for_km`/`longitude_degrees_for_km` form), sandbox
  hardening (115/115 touched files identical in main).
- **Skipped as superseded:** `master/face-governor-policy` (#858) — main's
  `visual_governor.js`/`visual_limits.test.mjs` evolved 207/150 diff lines past the
  branch's fork; the branch's rewrite would regress the canonical-policy series.
  `claude/*`, `fix/close-catalogue-*`, `fix/limits-catalogue-*` — zero unique commits
  vs the old-line tip.
- **Deleted:** all 15 remote branches. **Closed:** #859–#865, #867 (GitHub marked #867
  merged; the rest carry provenance comments).

## 4. Findings

### F1 — Root scripts diverge from their STUDIO twins
`output_paths.rb` (root blob `2bbd8676f`) vs `STUDIO/output_paths.rb` (`e31b65888`):
same name, different bytes. Same for `subprocess.rb` (`3c64d79ea` vs `95e5580db`).
Neither TREE_CONTRACTS.md nor MASTER/PATH_OWNERSHIP.yml mentions any of the four
files — nobody owns them, so nothing fails when they drift. Whoever consumes them
(ruby `require` paths, deploy scripts) currently depends on which copy the loader
finds first.

### F2 — Ungoverned multi-megabyte documents at root
`FULL.yml` (3,000 KB, "MASTER_FULL self-contained rule corpus", created 2026-10-30)
and `FETAT.md` (a consolidated government-services proposal, "working master
document") appear in no ownership file and no tree contract. `FULL.yml` additionally
duplicates content that lives as law files under `MASTER/law/`, and has a 395 KB
assessment snapshot inside `MASTER/docs/history/recovery/`. Root markdown census:
8 files of which 5 are agent doors + README + these two.

### F3 — TODO.md is an append-only session log
1,120 lines, 12+ sections keyed by session date ("Open from the 2026-11-02 session",
"Session note 2026-10-28" ×4…), mixing done work, carried-forward requests and stale
items. There is no done/ archive, no owner column, no dedup — the same audit work
appears under multiple dates. Its own top section ("external tree audit") is exactly
what this document performs.

### F4 — `RAILS/__other/mrdamascy` is an app pretending to be scratch space
171 files: 15 migrations, 15 model files, 14 stylesheets, 13 public/PWA assets, 11
config files, plus PWA screenshots landed via the sandbox-hardening re-cuts. It has no
entry in `RAILS/apps.yml` (the canonical deploy matrix), no `_*.sh` deploy script, no
README. Either it is a deployable tenant (it has branding, Vipps ordering, loyalty,
staff board — it behaves like one) or it is archaeology; the current name asserts
neither.

### F5 — ML binaries in plain git
Top tracked binaries: `RAILS/master/public/vendor/onnxruntime/ort-wasm-simd-threaded.wasm`
(13,164 KB), `RAILS/master/public/models/smart-turn-v3.2-cpu.onnx` (8,476 KB),
`RAILS/master/public/face_mask.jpg` (1,891 KB), two JetBrainsMono NerdFont woff2
(1,003 + 1,001 KB), `three.face.module.js` (502 KB). Every clone pays ~28 MB for
vendored vendorables that upstream serves.

### F6 — Deploy logic lives in five overlapping places
`RAILS/_assets.sh`, `_bundle.sh`, `_core.sh`, `_database.sh`, `_deploy.sh`,
`_runtime_check.sh`, `_service.sh`, `deploy.sh`, plus root `redeploy`, plus
`apps.yml` (185 name entries) and `apps.horizon.yml`. TREE_CONTRACTS documents
`apps.yml` as canonical; the shell layer around it is undocumented as a set.

### F7 — Documentation is 87 files across 17 roots
`MASTER/docs` 17 (+3 handoffs), `RAILS/docs` 2 + `docs/archive` 5, per-app READMEs,
3 OPENBSD docs, root doors. No index distinguishes *contract* (must stay), *runbook*
(must stay), *session artifact* (should age out) — so everything accumulates at the
highest-visibility level.

### F8 — Process contract vs actual history
`AGENTS.md`: "commit straight to `main` with path-scoped commits; never force-push."
Reality until today: 300+ PRs, 26k-commit side history, repeated force-push re-cuts of
`main` (the current lineage is a 19-commit re-cut). The declared workflow and the
practiced workflow disagree; the branch debris made every audit slower (this document
is the audit).

## 5. The plan

### Phase 0 — Guardrails (before anything moves)
1. `git tag` audit: keep `v0.1`, `v1.0`, `dilla-v0.1`, `dilla-engine-final`; tag the
   consolidation point: `git tag consolidation-20261102 9424bcac5`.
2. Record `bin/check` baseline: `cd MASTER && bundle exec ruby bin/check` output must
   be green before and after each phase; any phase that turns it red stops.
3. Confirm `OPENBSD/RUNBOOK.md` restore path still works from a fresh clone (the
   26k-commit history is unreachable from `main` now — runbooks referencing old SHAs
   need a sweep).

### Phase 1 — Root hygiene (F1, F2, F3)
1. **De-duplicate the twins.** Diff each root/STUDIO pair; keep the copy the loaders
   actually `require` (trace via `MASTER/bin/check` + RAILS boot), delete the other,
   and add all four paths to `MASTER/PATH_OWNERSHIP.yml` with purpose + check.
2. **Move `FETAT.md` → `STUDIO/docs/fetat/proposal.md`** (it is a writing project, and
   STUDIO is the writing/creative tree) — or, if the operator prefers, into a new
   top-level `DOCS/`; recommendation: STUDIO, it already hosts non-code outputs.
3. **Generated-artifact policy.** `FULL.yml`: regenerate-on-demand
   (`MASTER/rake`-style task), stop tracking it, add to `.gitignore`, keep the latest
   release as a tag annotation instead; delete
   `MASTER/docs/history/recovery/full_yml_assessment.yml` after confirming
   `bin/check` never reads it (grep first — if a check reads it, move it under
   `MASTER/data/` and own it there).
4. **TODO.md triage.** Split into: `TODO.md` (≤150 lines: open items only, one line
   each, owner + origin session), `docs/sessions/2026-*.md` (the historical notes,
   moved verbatim), and a `done` section that gets pruned quarterly. The 12 session
   sections become 12 files; nothing is deleted.

### Phase 2 — RAILS tree (F4, F6)
1. **Promote mrdamascy.** `git mv RAILS/__other/mrdamascy RAILS/mrdamascy`; add it to
   `apps.yml` (status: port — do not claim done until its `_mrdamascy.sh` exists);
   add `RAILS/mrdamascy/README.md` stating what it is (PWA storefront, Vipps-only
   ordering, loyalty, staff board) and that screenshots live under `docs/`.
   Alternative (if the operator says it is not a real tenant): move to
   `RAILS/docs/archive/mrdamascy/` and stop counting it as an app. Decision needed
   from the operator; the tree cannot decide this itself.
2. **Deploy script contract.** One page in TREE_CONTRACTS.md → RAILS section:
   `_*.sh` are library functions sourced by per-app `deploy.sh`; `redeploy` at root
   is the operator entry; `apps.horizon.yml` is the *planned* matrix and must not
   drift from `apps.yml` statuses without a session note. Add a check that every
   `apps.yml` name has a matching deploy path and vice versa.
3. **Docs archive flatten.** `RAILS/docs/archive` (5 files) + `MASTER/docs/handoffs`
   (3) get a two-line README each stating their retention rule ("session artifacts,
   deletable after the next consolidation tag").

### Phase 3 — MASTER / STUDIO / OPENBSD / replicate (F1 fallout, F7)
1. **Absorb root `replicate/` into STUDIO.** `STUDIO/replicate/` already exists;
   root `replicate/client.rb` is the odd one out. Trace its consumers
   (`grep -rn "replicate/client" --exclude-dir=.git`), move it, fix paths, delete the
   root dir. After Phase 1+3 the root holds exactly: doors, README, TREE_CONTRACTS,
   TODO, VERSION, `.git*`, `.github/`.
2. **STUDIO README as the small-tree index** (dilla, photograph, replicate, and now
   the FETAT writing project) — 18 files is small enough that one page is the whole
   contract.
3. **OPENBSD:** no structural change — its layout is clean; only add the Phase 1
   ownership entries for anything that gains a check.

### Phase 4 — Repo mechanics (F5, F8)
1. **Git LFS or release assets for vendorables.** Minimum viable: move
   `ort-wasm-simd-threaded.wasm`, `smart-turn-v3.2-cpu.onnx`, `face_mask.jpg`, the two
   NerdFont woff2 to LFS; better: fetch them at deploy time (checksums in
   `RAILS/master/lib/` boot check) and stop tracking entirely. Clone drops ~28 MB.
2. **History policy, stated once:** `main` is the only branch; path-scoped commits;
   tags mark consolidations; the pre-consolidation archaeology lives behind
   `consolidation-20261102` and the four release tags; force-push remains banned
   (the re-cut era is over — re-cuts now happen as ordinary commits, as this
   consolidation did).
3. **PR/branch guidance:** small or risky changes may still use a short-lived branch,
   but the default is commit-to-main + `bin/check`, matching AGENTS.md. Delete
   branches on merge (GitHub's auto-delete already covers this).

## 6. Execution order and cost

| Phase | Effort | Risk | Gate |
|---|---|---|---|
| 0 guardrails | 30 min | none | `bin/check` green |
| 1 root hygiene | 2–3 h | low (root has no runtime consumers except loaders) | `bin/check` + `rake lint:agent_contracts` |
| 2 RAILS | 3–4 h | medium (mrdamascy promotion touches deploy matrix) | `bin/check --tree=RAILS` + deploy-matrix check |
| 3 tree folds | 1 h | low | `bin/check` + STUDIO rake |
| 4 mechanics | 2 h + one migration PR | medium (LFS history rewrite is the one destructive step) | clone-size check + boot smoke |

Phase 4's LFS conversion is the only step that rewrites history; if that is
unacceptable, the fetch-at-deploy variant achieves the same clone-size win with zero
rewrite.

## 7. What must not change

- The five-door contract (`AGENTS.md` generated from `MASTER/AGENTS.md`; CLAUDE/GEMINI/
  GLM/`.cursorlaws`/copilot as doors) — it is the repo's best property.
- `TREE_CONTRACTS.md` as the single architecture narrative; this proposal's accepted
  items should *extend* it, not fork it.
- `MASTER/law/` constitution-as-code and the `bin/check` spine.
- The apps that boot today: brgen, amber, master, bsdports, brgen_radio,
  brgen_marketplace, brgen_messenger, brgen_dating, brgen_maps and the `__shared` gem
  — no phase may break their boot or their deploy paths.
- Never force-push `main`.

## 8. First five commits to land (if approved)

1. `docs: land the 2026-11-02 consolidation record and restructuring proposal`
   (this file + TODO session-notes split)
2. `refactor(root): de-duplicate output_paths.rb and subprocess.rb against STUDIO`
3. `chore(root): stop tracking FULL.yml; regenerate on demand; relocate FETAT.md`
4. `refactor(rails): promote mrdamascy to a first-class app in the deploy matrix`
5. `chore(master): extend PATH_OWNERSHIP.yml to cover every root and STUDIO script`
