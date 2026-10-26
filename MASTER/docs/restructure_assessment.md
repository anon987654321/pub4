# Restructure and rename assessment

The question this file answers: can the trees be restructured or files renamed
for greater clarity and brevity? It was written from static reading only — the
analysis environment had no Ruby runtime and no browser — so every proposal is
gated, and a gate that cannot run is a stop, not a formality. Nothing here
renames anything by itself; the phases say what must be proven first.

Precedent that frames every rename below: the rename of `playlist.<apex>` to
`radio.<apex>` once "walked straight past" the header's must-match-DomainRegistry
sentence because a sweep over literal hostnames cannot see an interpolated host
(MASTER/checks/support/brgen_vertical_surfaces.rb). Names here are load-bearing
in ways that are invisible to text search, which is why the gates are runtime
proofs rather than grep runs.

## Findings

**F1 — `lib/fix` is the mass.** 125 top-level `.rb` files, 29,926 lines, three
coordinator generations (`Kernel` 686, `FixLoop` 976 + 13 sub-files,
`RepairLoop` 569 + 6 sub-files, plus `Mission`, `RunJournal`, `RunLedger`,
`Transaction`). RAILS — three shipping apps and five engine verticals — is
1,749 Ruby files total. The repair machinery approaches the size of the thing
it repairs. Resolution is not a rename: it is the merge this repo already
mandated, now mapped in `docs/fix_coordinator_map.md`. Until that map's
Phase 2 recovery tests exist, **no file in `lib/fix` moves or goes**.

**F2 — the `visual_*` family wants a directory.** Twenty-plus flat
`lib/fix/visual_*.rb` files (ghost pages, ghost stack, cross-page drift,
cross-page overlay, cross-page pages, drift budget, surface budget, focus
order, custody, i18n, stress, usability…). They are one instrument with modes
wearing twenty filenames. Proposal: `lib/fix/visual/` with one file per mode
and a thin facade keeping the old constant names alive during the move. Gate:
the FixLoop require graph (F1's Phase 3) plus one full visual suite run before
the facade is deleted.

**F3 — `lib/fix/wishlist.rb` is a wish, not a runtime component.** 564 lines
of proposals living beside coordinators that execute. Proposal: move to
`docs/wishlist.md` (or split into convergence.yml workstreams, which is where
`convergence.yml` already says this content belongs — it calls itself
"non-authoritative implementation map for the assistant wishlist"). Gate:
none beyond a full-tree search for requires of it (FixLoop requires it — that
require line moves in the same batch, so this is F1-adjacent, done at
Phase 3).

**F4 — the tools shims have paid for themselves — phase 1 done.** 87 root-level
`.rb` files in `tools/`, of which fourteen are compatibility entrypoints (each a
short forwarder into `repo/`, `voice/`, `audit/`, `research/`). The 2026-10-26
batch re-pointed every live in-tree reference at the canonical paths — twenty
call sites across sixteen files, found by census rather than memory:
`lib/fix/fix_loop/council_round.rb` and `lib/operator/ratchets.rb` (the runtime
requires), `bin/cleanup`, the `Rakefile` naming rows and comment, five test
files' `require_relative` lines, `test_phoenix.rb`'s boundary probe,
`convergence.yml`'s proof path, and the prose in `AGENTS.md`, `tools/README.md`
and a comment in `RAILS/test/run_all.rb`. What remains is the gated half:
the shims themselves stay until one full check-ladder run on a Ruby host
proves the re-point, because the same census cannot see host-side harnesses —
operator zshrc, crontabs, STUDIO configs outside these trees — that may still
name the old paths. Then delete all fourteen in one batch. Gate: a Ruby host
and the ladder.

**F5 — law-about-law bridges should end in one registry view.**
`law/detectors/law_bridge_law.rb`, `yaml_bridge_laws.rb`,
`meta_laws.rb` plus `LawRegistryAudit` and `constitutional_triage` are
governance of governance. AGENTS.md says the mapping "is still being
reconciled"; the end state is these collapsing into the registry audit's view,
not persisting as a shadow catalogue. Gate: `LawRegistryAudit` gap
populations must be empty-or-explained first, on a Ruby host.

**F6 — the radio naming triangle.** `RAILS/brgen_radio/` is not an engine; it
is a container holding two engines (`playlist/`, `tv/`), while the `radio`
*subdomain* serves `Playlist::Engine` (`mount Playlist::Engine, at: "/",
as: "playlist", constraints: { subdomain: RADIO_SUBDOMAINS }` — brgen/config/routes.rb:221).
Three overlapping names, one of them attached to a public hostname that
already burned once. Proposal, worst-to-best of the options considered:
  - Rename the container to `brgen_radio_verticals/` — churn without clarity
    gain; the engines inside are still playlist and tv. Rejected.
  - Rename engines to radio/* — touches hostname coupling; the burned
    precedent says no without an operator decision. Rejected for now.
  - Document the triangle where the confusion will happen (this file, the
    routes comment, and brgen_vertical_surfaces already each carry a piece).
    **Chosen for now**: zero runtime risk, and the pieces already exist — this
    assessment is the third piece. A real rename is an operator decision with
    hostname migration, not an agent tidy-up.

**F7 — messenger's module prefix is the odd one out.** Sibling engines use
bare module paths (`lib/dating/`, `lib/maps/`, `lib/marketplace/`,
`lib/playlist/`, `lib/tv/`); messenger alone is `lib/brgen_messenger/`
(`BrgenMessenger::Engine` vs `Dating::Engine`). Proposal: rename
`brgen_messenger/lib/brgen_messenger/` to `lib/messenger/` with module
`Messenger`, gemspec name unchanged in the same batch. Gates, all required:
`tools/constant_collisions.rb` clean before and after; engine param-key,
route-helper and migration-convention tests (`test/engine_*`) green; the host
mount line updated in the same batch. Risk is moderate and real — this is the
one genuine rename candidate, and it waits for a Ruby host.

**F8 — messenger has no `config/locales/`.** dating, maps and marketplace
carry `en.yml` + `nb.yml`; messenger carries none. This may be correct (if it
renders no user-visible strings of its own) or a gap the nb/en parity contract
cannot see because it walks directories that exist. It is a question for the
operator, recorded here rather than "fixed" — inventing a locale file for an
engine whose strings were never inventoried would be worse than the empty
directory. If the answer is "no strings", record that sentence in
`brgen_messenger/README.md`; if "strings exist", they need keys before they
need a directory.

**F9 — the four generated agent surfaces.** AGENTS.md, GEMINI.md,
`.cursorlaws` and `.github/copilot-instructions.md` are generated from one
marked block, with drift linted — the right mechanism. The next step is not a
rename but pointer-ization: three of the four becoming one-line pointers to
AGENTS.md, so even generated drift becomes impossible. Gate: the harnesses
that read each file must be confirmed to follow a pointer (each vendor's
resolver behaves differently); until confirmed per harness, the generated
copies stay.

**F10 — prose drift is real and argues for generated brevity.**
`tools/agent_context.rb`'s header says `data/laws.yml` is 4,609 lines; it is
2,170. Nobody lied — the file was slimmed and the prose kept the old number.
The fix is in this patch's spirit rather than its letter: figures that can
drift belong in generated output (`--json` fields), not hand-written headers.
The one stale figure in this file's header is corrected in the same batch.

**F11 — brevity for laws.yml.** 2,170 lines is the canonical catalogue and is
read linearly every session. A generated digest (tier → id → one-line
requirement → pointer), produced the way the agent contracts are — `rake`
task, drift lint, never hand-edited — would cut the largest recurring token
cost without touching authority. Proposal only; the rake task wants a Ruby
host to write and lint it honestly.

**F12 — `__shared` keeps its name.** Renaming it to `pub4_shared/` (matching
the gem) would touch the gemspec, deploy scripts, `_core.sh`-family paths,
completions and every require that says `__shared`. Clarity gain near zero —
the double underscore already says "not an app". Keep.

## Phase gates

- **P0 — runtime prerequisite.** Ruby 4.0.5 host, check ladder green, RAILS
  contract suite green. Everything below halts without it.
- **P1 — zero-risk moves, no rename semantics:** F3 (wishlist to docs) and
  F10-style stale-figure corrections, each with its require/reference sweep in
  the same batch.
- **P2 — shim deletion** (F4) after harness re-pointing, one ladder run as
  the gate.
- **P3 — `lib/fix` consolidation** per `docs/fix_coordinator_map.md`, which
  carries F1 and F2 entirely.
- **P4 — the one rename:** F7 messenger module, with its full gate list.
- **P5 — generated brevity:** F9 pointer-ization per harness as each is
  confirmed; F11 laws digest behind its rake task.

## What this assessment does not claim

No dynamic-dispatch caller census (`send`, `const_get`, string requires are
invisible to it); no claim that any rename here is safe without its gate; no
opinion on hostnames — the radio triangle is documented, not resolved, because
resolving it belongs to the operator who owns the domain facts in
`RAILS/apps.yml`.
