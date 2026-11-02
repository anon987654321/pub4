# pub4

**One checkout, four trees, and a written source hierarchy that outranks every
agent working in any of them.** pub4 is a self-governing repository: the model
only proposes; Soul defines global identity, preservation, source order and
protected paths, while the Law catalogue defines the requirements each change
must satisfy.

## The four trees

- `MASTER/` — the constitution, the runtime and the instruments: the Law
  catalogue, the scanner, `/fix`, `/review`, `/critique`, and the operator and
  agent entrypoints. Start at `MASTER/README.md`; the workflow contract is
  `MASTER/AGENTS.md`.
- `RAILS/` — the applications and their shared engine, with the deploy
  tooling that carries them. Start at `RAILS/README.md`.
- `OPENBSD/` — the vm23 deployment tree: VPS configuration under `etc/`,
  `usr/` and `var/`, DNS, relayd, and the operator scripts. Live work starts
  at `OPENBSD/RUNBOOK.md`.
- `STUDIO/` — the media tools: Dilla, photograph and the Replicate client.
  `STUDIO/Rakefile` is the tree's check surface.

## How to enter

`AGENTS.md` is the canonical agent entrypoint and carries the shared workflow
contract generated from `MASTER/AGENTS.md`. Gemini, GLM, Cursor and Copilot
entry files are short pointers to it; `CLAUDE.md` is the bootstrap pointer.
`TREE_CONTRACTS.md` is the one per-tree contract file. `TODO.md` is the one
cross-tree backlog; an item closes by being deleted in the commit that carries
its evidence.

## Source authority and Laws

`MASTER/data/soul.yml` owns global identity, preservation principles,
source precedence and `absolute.sacred_paths`. Its source hierarchy is:

`soul.yml > laws.yml > executable laws and gates > tree contracts > Git history`.

`MASTER/data/laws.yml` is the one catalogue of individual Law identities,
statements, parentage and the nine invariant nodes' internal order. It does not
restate the source hierarchy or protected-path list. `law_runtime.yml` remains
live transitional execution metadata; it is not a second normative Law
catalogue. A missing or unrun measurement is INCONCLUSIVE, never PASS.

## Repository facts

`VERSION` records the release line. The FULL.yml rule corpus was retired on
2026-11-02: it declared itself `not_a_live_config` and every one of its rows
in `MASTER/data/law_runtime.yml` is marked covered — the constitution lives
in `MASTER/law/` and `MASTER/data/laws.yml`. `FETAT.md` (working master of
the FETAT proposal, a document, not policy) lives at
`STUDIO/docs/fetat/proposal.md`. `redeploy` is the workstation deploy
entrypoint.
