# pub4 architecture

pub4 remains one repository with four roots. Their jobs are distinct.

```
MASTER   = brain / constitution / observation / repair
RAILS    = product / people / data / presentation
OPENBSD  = machine / network / security / deployment
STUDIO   = sound / image / media / export
```

The repository is not rebuilt by copying old structure into a new name. The existing rules, law, tests, gates, contracts, runbooks, provenance and working media tools are retained while implementation is moved behind smaller boundaries.

The same invariant is enforced at each tree's real boundary, not by copying MASTER's constitution four times. MASTER admits effects before execution and records outcomes; RAILS binds requests to known hosts and data identity, and constrains browser-based imports to public targets; OPENBSD validates deploy targets before path construction and serializes machine-changing work under locks and health checks; STUDIO treats generated media as valuable artifacts, publishes WAV/MIDI atomically, and requires explicit consent to replace an existing take. Each tree owns its mechanisms, tests and failure vocabulary. One philosophy; no duplicate registry.

## MASTER

The small control kernel is a boundary rule, not a command to delete working subsystems or force every responsibility into one file. The live execution fold has four separate roles:

```
Model proposes Effect
        |
Constitution admits, revises, requests approval, or blocks
        |
World performs only an admitted Effect
        |
Memory records the observation; Proof tracks whether completion is earned
        |
Fold decides whether to continue or stop
```

`Master::Core::Fold` owns this turn-by-turn sequence. `Constitution` owns policy decisions, `World` owns external effects, `Memory` records the conversation and outcomes, and `Proof` tracks evidence. These responsibilities may be refactored internally, but their authority boundaries must remain executable.

The repository repair loop, `Master::Fix::FixLoop`, is a different loop. It coordinates repository inventory, scanning, repair, verification, convergence and delivery. Do not collapse it into the core effect fold: its terminal states and delivery semantics are part of the safety contract.

A four-method sketch such as `observe`, `apply`, `verify`, `fix` is a useful vocabulary for describing work, not a mandate to replace the current implementation with those exact method names. Keep orchestration small by keeping decisions, effects, proof and repair policy behind explicit boundaries.

Every Effect copies and freezes its JSON-shaped argument payload at construction, so a
later rule or caller cannot mutate what was admitted or approved. It also derives a typed
reversibility contract from its verb and arguments; the model cannot grant itself a label. Failed writes use the existing path-scoped
checkpoint restore. An exec may declare a concrete compensation as argv plus a human-readable
reason, but that compensation is re-admitted by the Constitution and requires operator
approval after the original command fails. A successful compensation does not rewrite the
original failure into success. Git stage and commit require explicit approval because the
shared index and durable history have no automatic inverse. Approval is a deferred request,
not a bypass: every applicable law must run first, any later block wins, and multiple checks
are presented together. Unknown effects are blocked; policy-gated means only that the existing
command or network policy decides, not that an effect is safe or reversible.

The command boundary resolves path arguments and Git working-directory targets through real
filesystem paths, not just strings. A workspace symlink cannot widen the admitted path into
another directory; if the path boundary cannot be established, execution is refused. This is
an argv/workspace guard, not a substitute for operating-system process confinement.

Canonical layers:

```
core
observe
fix
io
model
runtime
```

Dependency direction:

```
data / law
    |
  core
    |
  +-------+-------+------+
  |       |       |      |
observe  fix      io    model
  |       |       |      |
  +-------+-------+------+
             |
          runtime
```

Core does not depend upward. Observation never mutates. Planning never mutates. Repair mutates. Verification does not mutate.

`soul.yml` is the source for identity, sacred paths and absolute protection. `laws.yml` is the rule catalogue. Executable law remains under `law/`. The catalogue must never grow a second sacred-path authority.

## RAILS

`brgen` and `amber` remain real Rails applications. `shared/` contains only genuinely shared product primitives.

Domain ownership stays with the application that owns the noun. Shared messaging is a domain subsystem:

```
conversation
participant
message
attachment
event
delivery
```

Cross-tree access goes through explicit contracts. No RAILS code imports MASTER internals, OPENBSD internals or STUDIO internals.

The visual system has one shared interaction grammar. Dialects may change surface treatment, not the underlying interaction contract.

## OPENBSD

OPENBSD owns machine truth:

```
host
network
services
deploy
security
observability
verify
```

Deployment is one explicit lifecycle:

```
build -> stage -> verify -> install -> restart -> probe -> confirm
```

PF, relayd, NSD, rcctl, pledge, unveil, filesystem permissions and service ownership stay authoritative here. MASTER may inspect them, but does not silently redefine them.

## STUDIO

STUDIO owns media implementation.

```
dilla
visual
media
postpro
export
```

Dilla owns musical generation and measurement. Postpro owns image processing. LoRA/Replicate workflows belong here. MASTER dispatches and governs; it does not contain the media engines.

## Migration rule

Preserve first, then improve. Move physical boundaries before deleting behavior. Keep regression tests with the behavior they protect. A compatibility shim is acceptable only when it is explicit and temporary.

Generated output, vendored code, snapshots and machine state are not authored architecture.

## Filesystem hierarchy

Use OpenBSD's `hier(7)` as a guide to purpose and lifecycle, not as a literal directory template. A path should tell a reader whether a file is a public command, reusable implementation, canonical policy, verifier, test, generated artifact, or mutable runtime state.

- `bin/` contains stable operator-facing entrypoints; implementation belongs in `lib/` or a purpose-named tool family.
- `law/` contains executable Laws. `data/` holds versioned registries and policy, not logs, caches, or temporary results.
- `gates/` owns verification declarations, gate code, fixtures, and measurement support. It remains the single gate registry and runner.
- `tools/<family>/` holds canonical developer instruments by responsibility. A root-level legacy path may remain only as a thin, tested compatibility entrypoint; it must not become a second implementation.
- `test/` may be grouped by subsystem only while recursive discovery remains proven for both supported test naming forms, fixture exclusion remains explicit, and the runner's selected-file census does not shrink.
- Mutable state and generated results stay in their existing runtime/output locations. Do not move approved media, baselines, recovery payloads, or deployed OpenBSD targets as cosmetic cleanup.

Structural changes preserve callers first, then move one family at a time, update ownership and reachability contracts, and retain a reversible path until the consumer census and relevant tests prove the new layout.

## Evidence, memory and constitutional change

MASTER deliberately has several records with different jobs; they are not interchangeable copies of one log.

- `Master::Core::Proof` tracks whether current-generation evidence is sufficient to justify completion. A write invalidates proof earned against an earlier generation.
- `Master::Fix::RunJournal` records repair-run lifecycle metadata so interrupted runs can be identified and resumed. It is not a file-content backup.
- Git history, transaction checkpoints and the write/undo journal preserve source changes and recovery state.
- The event bus and dmesg surface report live progress. A console line alone is not durable proof that a command, deployment or repair succeeded.

Do not replace these with a single hash-chained JSONL file until its canonical encoding, key handling, serialization lock, corruption detection, recovery procedure, retention/privacy policy and independent verifier have been specified and tested. A hash chain detects some changes; by itself, a writer who can rewrite the entire file can recompute the chain. Stronger tamper evidence needs an independent trust anchor appropriate to the threat model.

Every proof report names the commit and the checks actually run. Distinguish passing, failing, inconclusive, blocked, skipped and delivery-failed outcomes. Missing tooling or a timed-out check is not a pass. Metrics such as verified convergence, regression recurrence, rollback frequency, false-clean outcomes, cost and escalation reasons are reported separately and by risk class. Escalating an unsafe action is successful governance, not an autonomy failure.

Ordinary repair does not amend the constitution. Changes to absolute law use a separate, human-authorized amendment path, with the exact diff, previous and proposed content digests, reviewers, verification evidence and rollback path recorded. A remembered successful repair is a candidate, not an exemption: replay must check the current source revision, law, scope, environment and verification contract before applying it.

Cross-host federation is a later capability, not a property obtained by sharing a log format. Before kernels witness each other, define authenticated identities, independent failure domains, signed observations, replay protection, quorum rules, privacy limits and recovery from divergent histories.

## Proof

The clean architecture is not complete until:

- the four roots have single responsibilities;
- no sibling imports another tree's internals;
- sacred-path ownership has one source;
- MASTER core has no higher-layer dependency;
- observation/repair mutation boundaries are executable;
- RAILS shared code is actually shared;
- OPENBSD has one authoritative deployment path;
- STUDIO owns media implementations;
- migrated behavior retains regression coverage;
- semantic coverage is reported honestly;
- runtime and rendered gates are watched, not inferred.

The current migration is deliberately incremental inside pub4. The old pub5 experiment is not an active target.


## Boundary enforcement

Runtime code does not require sibling implementation files. MASTER's observation and gate tooling may read sibling source as evidence, but it does not become a product dependency.

RAILS keeps brgen, amber and bsdports as ordinary Rails applications. Cross-tree product calls use explicit adapters under `MASTER/contracts/`.

MASTER ingress is represented by `MASTER/contracts/master_client.rb`. Studio execution paths are represented by `MASTER/contracts/studio.rb`. These adapters expose the boundary; they do not load sibling internals.


The current boundary is executable: MASTER may invoke STUDIO through the explicit media entrypoints, RAILS crosses to MASTER through the ingress contract and to STUDIO through `MASTER/contracts/studio.rb`, and neither product tree imports sibling implementation files.

STUDIO media ownership includes `dilla/`, `postpro/`, `replicate/`, `lora/`, and `visual/generators/`. `STUDIO/photograph.rb` is the canonical image/short-film entrypoint.


## Cognitive security grammar

MASTER extends the repository's OpenBSD design grammar upward. A model is proposal-only; each Effect carries a verb-derived capability; Constitution admits only capabilities present in the current context; capability sets can only shrink and may be locked.

The operating correspondence is:

```
pledge(2)   -> capability context
unveil(2)   -> Memory::View
sysctl      -> /status security
rcctl       -> /status services
syspatch    -> Fix::Patch over Fix::Transaction
dmesg       -> boot/event evidence
```

The rule is simple: machinery does not grant authority merely because it can perform an operation. Authority is declared, reduced, observed and verified.
## Cognitive judgment kernel

MASTER keeps reasoning machinery in one existing spine, Master::Cognition::Intelligence.
It separates observation from inference, keeps uncertainty explicit, ranks opportunities by
causal leverage, compares concepts by purpose and boundary rather than names, and moves
reasoning across local, subsystem, tree, repository, production and human scales. /fix
records bounded decision frames in the existing Ground::Memory store; the next model turn
can recall those frames without adding a second memory database. Creative work uses the
same frame to preserve identity and invariants while varying one declared axis, and
unfinished work is preserved until consumer/value evidence distinguishes potential from
deadness.

## Decision context

MASTER keeps the runtime identity of a decision small and reproducible. The existing `Ground::BootReceipt` can be asked for a session receipt that joins the current commit, constitutional digest, durable-memory version and answering model; `/why` exposes it only when that runtime context exists, while ordinary doctor output remains unchanged. Cognition also treats attention as a finite budget: leverage ranks the candidates and high-uncertainty work is retained even when it would otherwise fall outside the first slice.


MASTER keeps reasoning machinery in one existing spine, Master::Cognition::Intelligence. It separates observation from inference, keeps uncertainty explicit, ranks opportunities by causal leverage, compares concepts by purpose and boundary rather than names, and moves reasoning across local, subsystem, tree, repository, production and human scales. /fix records bounded decision frames in the existing Ground::Memory store, and council deliberation synthesizes model differences without majority-vote semantics.

Operator feedback is durable taste memory in the existing feedback channel. Creative work preserves identity and invariants while mutating one declared axis. Unfinished work gets a fertility assessment; it is never a deletion authority by itself, and deadness needs stronger evidence than mere inactivity.

## Operator execution modes

Agent work carries one explicit execution mode derived before its first effect:
`observe`, `plan`, `repair`, or `deploy`. The mode is stored inside the existing
durable mission record and emitted on the existing event bus; it is not a second
task ledger or policy source.

`observe` is read-only, `plan` has read/model authority without mutation, `repair`
uses the existing write/execute/network profile, and `deploy` is the critical
profile used only by an explicit deployment path. Constitutional law, sandbox,
evidence, checkpoints and verification remain the final authority and can only
narrow or refuse an effect.

OpenClaw-style Gateway ownership, Hermes-style durable objectives, Pi-style small
agent boundaries, Deep Agents-style explicit modes, and Letta-style durable
trajectories are expressed through MASTER's existing operator, mission, skills
and evidence surfaces rather than parallel frameworks.
