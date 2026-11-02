# pub4

**One checkout, four trees, and a written constitution that outranks every
agent working in any of them.** pub4 is a self-governing repository: the model
only proposes, and nothing touches a file until `MASTER/data/laws.yml` admits
it. Nothing here acts first and inspects the wreckage afterward.

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

`AGENTS.md` is the canonical agent entrypoint: it routes every harness door
(`CLAUDE.md`, `GEMINI.md`, `GLM.md`, `.cursorlaws` and
`.github/copilot-instructions.md`) to MASTER and holds no policy of its own.
`TREE_CONTRACTS.md` is the one per-tree contract file. `TODO.md` is the one
cross-tree backlog; an item closes by being deleted in the commit that carries
its evidence.

## The constitution

`MASTER/data/laws.yml` is the sole normative document; `MASTER/data/soul.yml`
is subordinate identity and delivery configuration. Authority runs laws.yml >
soul.yml > Ruby implementations and executable Law adapters > checks and tree
contracts > agent-harness prose. A missing or unrun measurement is
INCONCLUSIVE, never PASS.

## Repository facts

`VERSION` records the release line. `FULL.yml` is the generated self-contained
rule corpus. `FETAT.md` is the working master of the FETAT proposal — a
document, not policy. `redeploy` is the workstation deploy entrypoint, and
`replicate/`, `output_paths.rb` and `subprocess.rb` are root-level shims over
STUDIO's canonical implementations.
