# MASTER and Modern Agent Tooling — Comparative Architecture Proposal

**Reviewed:** 2026-10-26  
**Repository baseline reviewed:** main at 62cfd1e069f89d838d4400132537369994846a92 (including merged PR #773).  
**Intent:** improve MASTER by borrowing specific, evidenced techniques from other tools—not replace MASTER with another agent framework.

## Executive recommendation

Keep MASTER as the constitutional Ruby spine for CLI, web, voice, code repair and future adapters. Its differentiator is not that it can call a model; it is that a model action passes through law/policy checks, a bounded effect executor, trace/evidence infrastructure, and a repair/delivery path that can report failure honestly.

The best next step is to close a short list of seams already visible in the source:

1. **One measured proof ledger.** Main now correctly refuses DONE while its Law × stream × surface assessment matrix is not_measured. Implement the measurement and evidence records; do not weaken the gate.
2. **One lifecycle contract.** Required before/after events, bounded metadata, idempotent operation IDs, and fail-closed recovery should apply to effect execution, Fix transactions, RunJournal writes, and Git mutations. The current patch is the first implementation slice; validate it before broadening.
3. **One ownership model for /fix.** Keep FixLoop, RepairLoop, Kernel, Mission, RunJournal, and Transaction as focused components, but define who owns run state, recovery, effects, budgets, and terminal status. Do not collapse them into a god object.
4. **An OS-enforced tool boundary.** Prompts and Ruby capability checks are necessary but are not sufficient against a compromised or misbehaving child process. Add optional platform-specific sandbox adapters behind the existing execution gateway; do not make Docker or a new runtime mandatory.
5. **Proof before claims.** Every terminal report should reference measured checks, test runs and delivery evidence. Unavailable, inconclusive, blocked, timeout and delivery failure stay distinct from success.

Do **not** replace MASTER wholesale with LangGraph, OpenHands, OpenClaw, Paperclip, NanoClaw, Ruflo or a multi-agent swarm. Those projects solve overlapping but different problems. Borrow the useful pattern at a time, behind MASTER's own laws and interfaces.

## What the current tree already has

The baseline includes constitutional authority in data/soul.yml and data/laws.yml, executable laws and scanner adapters, a capability-oriented Core Fold/World path, paired Core effect observation, strict EventBus persistence, redacted event projections, and separate FixLoop/RepairLoop/Kernel/Mission/RunJournal/Transaction/Delivery responsibilities. The code-reference graph, inter-model contract, grounding and repair gates, known-good promotion, approval/governor checks, resource budgets, and model-lane routing are established pieces—not blank spaces that a framework should recreate.

Recent main changes also matter: model registry/context windows are refreshed and used for routing, tests isolate provider/lane state, /fix preflight resists unexpectedly falling to a free/local model while a better lane is available, and the terminal completion gate refuses DONE when the proof matrix has not been measured. A current routing load failure was also fixed. These are incremental advances; the remaining concern is end-to-end proof, consistency and runtime enforcement.

The reconciled integration adds a required mutation observer for Fix transaction state changes and RunJournal persistence. `Master::Io::GitOperations` already uses required `ToolObserver` receipts for mutating `git!` calls in the current baseline, so those receipts remain the canonical Git mutation audit rather than adding a second recorder. Missing transaction/journal after-events leave durable markers that block automatic recovery. The regression tests are written but have **not** been executed in this environment; validation remains **INCONCLUSIVE**, not PASS.

## Comparative review

| Project / pattern | What is worth borrowing | Where MASTER already overlaps | Recommendation |
|---|---|---|---|
| [LangGraph](https://github.com/langchain-ai/langgraph) | Persistent checkpoints, resumable state transitions, human approval interrupts and explicit resume semantics | RunJournal, Transaction and FixLoop already implement recovery and terminal states | **Borrow the checkpoint/state-transition discipline, not a second workflow engine.** Require explicit state version, checkpoint identity and approval resume data. |
| [OpenHands](https://github.com/OpenHands/OpenHands) | Clear split between UI, agent server, workspace/runtime services and sandbox; explicit action stream | MASTER already separates CLI/web/voice surfaces from Core/World and Trace | **Borrow the boundary and workspace lifecycle.** Keep the Ruby core and law enforcement in charge; no agent runtime replacement. |
| [NanoClaw](https://github.com/nanocoai/nanoclaw) | Per-agent workspace/mount policy, session isolation and host-mediated actions | MASTER has tree roots, sessions, budgets and capability gates, but isolation is not uniformly OS-enforced | **Borrow per-run isolation and explicit mounts.** Do not copy its Docker dependency, given MASTER's portability constraints. |
| [Superpowers](https://github.com/obra/superpowers) | Repeatable TDD, systematic debugging, verification-before-completion, review and branch-finish checklists | MASTER has laws, gates and tests, but verification can vary by command and stage | **Adopt a small set of internal, versioned procedures** for diagnose → reproduce → patch → verify → report. Procedures help quality but are not a security boundary. |
| [Graphify](https://github.com/Graphify-Labs/graphify) | Deterministic AST graph, explicit extracted-vs-inferred edge provenance, queryable paths and stale graph detection | MASTER has a Ruby-aware reference/call graph and static scanner contracts | **Strengthen the existing graph, do not add another graph.** Tag edges as extracted/inferred/unresolved, store source locations and freshness, and test dynamic dispatch gaps. |
| [Hermes Agent](https://github.com/NousResearch/hermes-agent) | Curated persistent memory, skill loading, checkpoint-aware context reduction and explicit memory boundaries | MASTER has project context/laws and run journals; memory ownership and freshness need a clear contract | **Borrow bounded, provenance-bearing memory.** Separate constitutional truth, user preferences, project facts and per-run scratch. Never let a model silently rewrite laws or high-authority memory. |
| [Anthropic Agent Skills](https://github.com/anthropics/skills) | Small task-specific procedure bundles with a stable skill entry point | MASTER uses central laws and a single prompt/shell experience | **Use skills as internal procedure modules**, loaded by task and policy—not as a second user-facing prompt system. Every skill needs version, declared capabilities, acceptance checks and provenance. |
| [Anthropic sandbox-runtime](https://github.com/anthropics/sandbox-runtime) | OS-level filesystem and network isolation, allow-only write paths and explicit network destinations | MASTER has application-level capability checks and process wrappers, but not every child process is boxed by the OS | **High-priority reference for an optional SandboxAdapter.** Define platform backends (macOS, OpenBSD, Linux, Termux where available) and an honest unsandboxed/unsupported state. Do not claim isolation when only a prompt or Ruby check ran. |
| [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) | Policy-governed execution sandbox, verification of policy changes and boundary between model and enforcement | MASTER's laws are stronger in project-specific constitutional authority; OS enforcement is the gap | **Borrow the threat model and policy verification**, not an enterprise control plane as a mandatory dependency. Policy denial must come from the trusted host layer. |
| [OpenClaw](https://github.com/openclaw/openclaw) | A gateway as the authoritative owner of sessions, routes and channel state | MASTER aims for one Ruby spine across CLI, web and mic, with EventBus/session stamping | **Keep one source of truth for session and routing state.** Do not make EventBus, CoreBridge or a new gateway a god object. |
| [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) | Typed provider aliases, ordered fallback, per-provider retry behavior and visible model substitution | MASTER now refreshes model metadata, considers context windows and has lane preflight | **Improve failure taxonomy and route visibility**: provider unavailable, auth, rate limit, context overflow, timeout and policy refusal should be different typed outcomes. Show requested and served model, retry count and reason without leaking credentials. |
| [Paperclip](https://github.com/paperclipai/paperclip) | Run ownership, budgets, approvals, audit attribution and watchdog/recovery controls | MASTER has resource budgets, Governor, approvals and run journals | **Borrow the control-plane invariants.** A run has one owner, one budget ledger, explicit approval gates, and a provable terminal state. Do not build a separate company/agent-management app into MASTER. |
| [HKUDS/nanobot](https://github.com/HKUDS/nanobot) | Small gateway that owns execution, sessions, tools, memory and channel adapters | MASTER's single-spine goal and CoreBridge already fit this shape | **Use it as a simplicity benchmark.** Every new service must justify why it cannot be a small Ruby adapter behind an existing boundary. |
| [Goose](https://github.com/block/goose) | Extension/MCP adapters, recipes, tool-specific permissions and selectable autonomy levels | MASTER has tool wrappers and policy gates; adapters can still vary in authority and reporting | **Standardize a capability manifest** for each adapter: read/write scope, network destinations, secrets, approval class, timeout, retry safety and evidence output. No implicit shell authority. |
| [Open Interpreter](https://github.com/OpenInterpreter/open-interpreter) | Concrete computer/browser/file/terminal action adapters and clear exposure of action provenance | MASTER's multi-surface ambition will require more than text-only tool outputs | **Borrow adapters only behind World/capability policy** with action previews, scoped data and explicit confirmation for irreversible external actions. Do not grant general computer control by default. |
| [Ruflo](https://github.com/ruvnet/ruflo) | Delegation and multi-agent workflow patterns | MASTER already has a council/model pool and repair stages | **Defer swarm expansion.** First make one run's actions, budgets, checkpoints and evidence unambiguous; then test whether parallel agents add measurable quality. |
| [CoPaw](https://github.com/agentscope-ai/CoPaw) | Personal-agent memory and channel/workload organization | MASTER already owns user interaction across surfaces | **Use selectively for memory/user-work separation**, not as a new multi-channel control plane. |
| [PicoClaw](https://github.com/sipeed/picoclaw) | Small-footprint deployment patterns for constrained devices | MASTER has a Ruby spine and Termux-related portability goals | **Treat as a later footprint benchmark** for mobile/edge operation; do not fork the core into a second implementation. |
| [IronClaw](https://github.com/nearai/ironclaw) | Security-first tool/runtime boundary ideas | MASTER's policy authority is project-specific; isolation, secrets and process constraints remain important | **Compare threat models and tests**, not its runtime architecture wholesale. |

The table deliberately distinguishes **pattern borrowing** from dependency adoption. A clever feature is not a reason to duplicate a subsystem already in MASTER.

## Architecture proposal

### 1. One effect protocol, one run identity

Preserve the current constitutional order. Introduce a stable, versioned lifecycle record with:

- run_id, effect_id, optional parent_effect_id, and checkpoint_id;
- operation/capability labels, start/end timestamps, result status, elapsed time and bounded counts;
- explicit states: planned, before_persisted, running, succeeded, failed, blocked, ambiguous, recovery_required;
- a versioned schema and a redaction/projection step before durable persistence.

The existing Core EffectObserver and the new MutationObserver should eventually share the low-level recorder/record schema, while keeping separate domain adapters for world effects, transactions, Git and journal writes. Do not have each component invent its own event IDs, status vocabulary or persistence semantics.

**Invariant:** no side effect starts until its required before-record is durable. If the side effect may have happened but its after-record cannot be written, mark the outcome ambiguous, leave a durable recovery marker, and refuse automatic retry/resume. Reconcile from ground truth; never infer success from an exception, an event, or a planned action alone.

### 2. One owner per responsibility in /fix

Do not merge classes just to reduce the file count. Define ownership explicitly:

- **FixLoop:** top-level orchestration, budget, stop policy and terminal outcome.
- **RepairLoop/pass runner:** executes bounded repair passes and reports structured stage results.
- **Kernel/World:** trusted capability enforcement and actual mutations.
- **Mission:** task intent, acceptance conditions and approvals—not a second run journal.
- **RunJournal:** durable run/phase/checkpoint metadata and restart decisions.
- **Transaction/Delivery:** snapshot, conflict, rollback floor and local/remote delivery identity.
- **Trace:** required lifecycle ledger and separate best-effort diagnostics.

Give each run one ID across those components. Keep local state machines where they protect real invariants, but remove duplicate terminal decisions, duplicate retry ownership and duplicate completed semantics. Do this only after call-site and recovery tests demonstrate the handoff.

### 3. Actually measure the Law × stream × surface matrix

The latest main gate is right to report not_measured. The next architecture task is a real ledger, not a looser status flag.

For each executable law and each relevant surface/stream:
1. identify the expected enforcement point and evidence source;
2. instrument a positive case, a negative/denial case and a failure-to-measure case;
3. capture event/effect IDs, source revision, toolchain, timestamps and outcome;
4. mark coverage as measured-pass, measured-fail, unmeasured, unavailable or inconclusive;
5. require complete, current evidence before DONE.

Do not mark every law × surface pair as applicable blindly. Store applicability and rationale so not applicable is distinct from not measured. Add a regression that intentionally deletes or disables a measurement and proves /fix cannot claim DONE.

### 4. Enforce tools outside model text

Route shell/process, file writes, Git mutation, browser/network and deployment operations through a small set of capability adapters. Each adapter declares path scope, network allowlist, credentials, timeout, retryability and whether the effect is reversible.

The host enforces those constraints. If the current platform cannot supply an OS-level sandbox, report sandbox_unavailable/degraded and use only explicitly allowed lower-risk operations; do not claim equivalent isolation. Start with command execution and provider-controlled helper processes, then cover browser/MCP and background jobs. Respect MASTER's portability goals and avoid a mandatory Docker/Kamal/Vercel layer.

### 5. Standardize findings and terminal results

Create a stable contract rather than spreading new wrapper types through every layer:

- **Finding:** law ID, severity, path/range if appropriate, evidence reference, confidence, source (extracted/inferred/semantic), freshness, and repairability;
- **StageResult:** stage, status, evidence refs, counts, elapsed time, retryability and bounded error code;
- **RunOutcome:** terminal status plus proof requirements satisfied/missing.

Keep raw source snippets, prompts, file contents, command output, secrets and paths out of shared durable telemetry by default. They may remain in explicitly protected local artifacts when a repair genuinely needs them; any such artifact gets a stricter access/retention contract. The durable event stream should contain references and bounded metadata, not duplicate the artifact.

### 6. Make routing observable rather than clever

Preserve the current model registry, lane preflight, context-window measurement and provider pool. Add:

- typed provider failure categories and a bounded retry budget;
- per-provider/model cooldown or circuit-breaker state with TTL and last-good fallback;
- a single visible route record: requested model, served model, reason for fallback, attempts, context budget and latency;
- fixtures for keyless, rate-limited, timed-out, context-overflow, refusing and unavailable providers;
- deterministic policy preventing an accidental free/local lane when an approved paid/subscription lane is available, except with explicit override.

Never persist credentials or expose raw authorization material. A fallback is not success on the requested model; report the actually served provider truthfully.

### 7. Versioned procedures and bounded memory

Keep the user interface as MASTER's single prompt. Inside the runtime, use versioned skill/procedure objects for recurring tasks such as /fix, incident diagnosis, security review, audio production and delivery. A procedure can declare required evidence and allowed tools; it cannot grant itself capabilities.

Keep memory separated into (a) constitutional sources, (b) project facts with file/revision provenance, (c) user preferences, and (d) expiring run scratch. Record when a fact was observed, which source supports it and what source changes invalidate it. Use bounded summaries and explicit ownership; do not let model-generated memory overwrite higher-authority sources.

## Sequenced implementation plan

| Priority | Slice | Deliverables | Acceptance gate |
|---|---|---|---|
| **P0 — current branch** | Close the lifecycle/privacy seam | Redacted durable event projection; shared mutation observer; required before/after around transaction, journal and Git state mutations; recovery markers; focused regressions | On the pinned Ruby/toolchain, new tests plus affected Core/trace/Fix/transaction/Git tests pass. Fault injection proves a failed before-record blocks mutation; a failed after-record prevents silent retry. |
| **P1 — proof first** | Real assessment matrix | Versioned law × stream × surface ledger, applicability evidence, measured states, proof references in terminal result | A deliberately missing matrix record keeps /fix BLOCKED; complete measured matrix allows DONE only with all other gates satisfied. |
| **P1 — lifecycle convergence** | Common recorder and clear /fix ownership | Shared event schema, migration map of all mutation sites, one run ID and owner, typed stage and run outcomes | No duplicate terminal status; each external mutation has one authoritative before/after pair and recovery owner. |
| **P2 — fault-injection harness** | Repeatable simulation matrix | 200–400 deterministic CLI/repair/event/routing scenarios: ENOSPC, permission denied, process death between records, concurrent edits, lock contention, remote rejection, provider failure, partial output and replay | Reproducible seeds, no unhandled false-DONE, no privacy leakage in durable logs, stable exit/status contract. These are local simulations, not claimed live external delivery. |
| **P2 — tool boundary** | Sandboxed execution adapters | OS-specific sandbox capability checks, per-command file/network policy, explicit degraded state, secret masking/withholding | Prove both enforcement and negative cases on each supported platform; unsupported platform is reported honestly. |
| **P3 — graph and findings** | Evidence-provenance upgrade | Extracted/inferred/unresolved graph edges, source freshness, shared Finding schema | Graph claims always link to source; dynamic/unresolved references remain explicit instead of being invented. |
| **P3 — routing, skills, memory** | Reliable model and procedure policy | Typed routing telemetry, bounded retries/cooldowns, internal versioned skills, scoped memory updates | Route/fallback is observable; task procedures do not bypass law checks; memory cannot silently override higher-authority files. |
| **P4 — optional adapters** | Browser, MCP, mobile and deployment capabilities | Adapter manifests, risk tiers, approval and evidence contracts | New adapter passes shared capability/lifecycle suite before inclusion. No new parallel agent control plane. |

## Required non-goals

- No replacement of MASTER's constitutional authority with a third-party framework.
- No prompt-only sandboxing and no fabricated sandboxed result when an OS boundary was not applied.
- No second workflow/state database unless a measured requirement cannot be met with the current RunJournal and transaction ledger.
- No swarm/multi-agent layer before deterministic single-run recovery, budgets and terminal evidence work.
- No success claim from a model response, an exit code alone, or an event that failed durable persistence.
- No changes to sacred constitutional files as part of the lifecycle refactor.

## Source references checked

The comparison is grounded in the projects' official repositories/docs as checked on 2026-10-26:

- LangGraph checkpoint/HITL model: https://github.com/langchain-ai/langgraph
- OpenHands runtime boundaries: https://github.com/OpenHands/OpenHands
- NanoClaw isolation model: https://github.com/nanocoai/nanoclaw
- Superpowers procedures: https://github.com/obra/superpowers
- Graphify provenance graph: https://github.com/Graphify-Labs/graphify
- Hermes memory/skills: https://github.com/NousResearch/hermes-agent
- Anthropic Skills: https://github.com/anthropics/skills
- Anthropic sandbox-runtime: https://github.com/anthropics/sandbox-runtime
- NVIDIA OpenShell: https://github.com/NVIDIA/OpenShell
- OpenClaw gateway: https://github.com/openclaw/openclaw
- ZeroClaw routing/fallback: https://github.com/zeroclaw-labs/zeroclaw
- Paperclip budgeting/approvals: https://github.com/paperclipai/paperclip
- nanobot gateway: https://github.com/HKUDS/nanobot
- Goose extensions/permissions: https://github.com/block/goose
- Open Interpreter: https://github.com/OpenInterpreter/open-interpreter
- Ruflo: https://github.com/ruvnet/ruflo
- CoPaw: https://github.com/agentscope-ai/CoPaw
- PicoClaw: https://github.com/sipeed/picoclaw
- IronClaw: https://github.com/nearai/ironclaw
