# MASTER

**MASTER is an artificial intelligence written in pure Ruby that governs itself
by law instead of by hope, grown in Norway and meant to run its own mind on
clean power drawn from inside a fjord mountain.** Most systems let a model act
first and inspect the wreckage afterward. MASTER inverts the order. The model
only proposes, and nothing touches a file until a written constitution admits
it.

See the [full tooling comparison and architecture proposal](TOOLING_COMPARISON_PROPOSAL_2026-10-26.md) for the latest source-grounded review of external agent tools, the gaps in MASTER, and a phased implementation plan.

### Cognitive judgment

MASTER's reasoning habits are executable, not a second constitution. `Master::Cognition::Intelligence`
keeps observation, hypothesis, falsifier, measurement, causal trace, uncertainty, leverage,
conceptual equivalence, scale and creative-preservation vocabulary in one place. `/fix`
persists its bounded decision frames through the existing `.master/memory.yml` store, and
the model receives a compact recent reasoning history on the next turn. This is deliberately
small: better judgment should reduce machinery, not create another orchestration layer.

## The idea

Most AI is written in Python, chosen for its libraries more than its clarity.
MASTER is written in Ruby, and that is the point. A law governs a system only
when a human can read both the Law and the code that enforces it, and Ruby reads
like intention. The constitution therefore stays legible. `data/soul.yml` holds
the constitutional absolutes; `data/laws.yml` is the canonical declared Law
catalogue and execution policy. Executable definitions and detector-adapter
sources share one physical home under `law/`; detector adapters live in
`law/detectors/`. `lib/review/scan/` holds scanner machinery, registration,
auditing, and orchestration—not a second Law source tree. These are enforcement
mechanisms, not alternate sources of normative authority. `LawRegistryAudit`
checks Law identity and source integrity and reports declared coverage debt
separately. Reconciliation does not prove that every Law has a deterministic
detector or that every runtime surface has actually been assessed; MASTER must
not claim complete enforcement from a file count or registry count.
A break gets a refusal with a reason, never a quiet patch.

The `MASTER/bin/operator laws <ID>` view uses
`Operator::LawInventory.catalogue_declaration` through `Master.load_laws` to
search every catalogue section. `Master.law_entries` is intentionally narrower:
it provides priority-ranked entries, not every declaration.

The kernel also forbids simulation. MASTER may not claim it read a file without
showing the content and its hash, claim a change without the diff, or claim
completion without the command output. A model, a network or a speech worker
that is unavailable makes the run degraded or failed. It never counts as a
success.

The law is not the only thing written down. Every measure that matters carries a
number recorded in the tree: files per tree, lines the runtime may use,
findings its own rules produce against its own source. A number may fall and
never rise. An improvement locks the moment someone makes it, and a regression
fails the build. Run `bin/operator measure` and every measure prints beside the
ceiling it must respect.

MASTER can run offline when a local model is available. It deploys to OpenBSD
and judges a codebase without a cloud control plane.

## Skills and execution contracts

Skills may declare an `execution_contract` with a semantic version, risk, required
capabilities, Law IDs, fixture references and provenance. The declaration is
content-addressed along with the skill; changing its body, triggers, metadata or
bundled files changes the revision. A declaration does not grant its listed
capabilities, and a declared skill is not injected just because its own metadata
labels it approved.

A declared skill requires a matching revision-bound entry in the operator-owned
`~/.master/skill_approvals.yml`. Use `/skill list` to review declared skill
revisions, `/skill inspect NAME` to inspect their metadata, and
`/skill approve NAME FULL_SHA256 --confirm` or
`/skill revoke NAME FULL_SHA256 --confirm` to approve/revoke one exact revision.
The command is local-operator-only; malformed manifests are not overwritten,
and a change to skill content requires a new approval. Candidate fixture references
are not proof that the tests passed. Legacy skills remain compatible while
migration proceeds. See [Execution contracts](docs/execution-contracts.md) for
the contract and its remaining limits. Regression tests have been added, but
runtime validation remains INCONCLUSIVE until they run on the pinned Ruby toolchain.

## Visual identity

The current direction is **signal and stillness**: neutral, flat surfaces; decisive
typography; deliberate negative space; and one original mineral-lime signal for
meaningful states. The visual contract lives in `MASTER/data/laws.yml`; values
live in `MASTER/data/tokens.yml`. The browser and terminal face are presentation
adapters, not separate visual authorities. The signal must never obscure a truthful
runtime state, reduce accessibility, or force another product's palette.

## The loop

The whole control flow is a fold that fits on one screen. The model proposes an
effect. The constitution judges it and returns one of four verdicts. Allow lets
the effect through. Revise rewrites it for the rules that come after, and never
leaves the constitution. Block refuses it with a reason, which the model sees
and can answer by choosing another route. Request stops to ask a person, and no
answer counts as no. An admitted effect that can change the tree runs against a
checkpoint, and an error undoes it. To add an ability, add an effect handler. To
add a constraint, add a rule. The spine does not grow.

## Fixing

`/fix [path]` is the single write-enabled convergence operation. `/review` and
`/critique` are read-only. The pre-repair baseline is deliberately read-only,
but it is a preflight stage, not a silent downgrade to dry-run. Explicit
`--dry-run` plans and measures without writing.

The architectural boundary matters: `Core::Fold` governs the general model-effect
loop, while `/fix` owns repository repair and convergence. They share constitutional
principles but are not the same workflow. Production boot creates one
`Fix::Kernel` and enters through `Kernel#build_fix_loop`. The canonical
convergence class is `Kernel::ConvergenceAdapter`, exposed to existing callers as
`FixLoop`; the canonical per-Law repair class is `Kernel::RepairAdapter`, exposed
as `RepairLoop`; the canonical durable run journal is `Kernel::LifecycleJournal`,
exposed as `RunJournal`. The compatibility constants and on-disk journal schema
remain while call sites are migrated and recovery parity is proved.
The current `RunJournal` serializes access through `.master/fix_runs.lock` and
refuses symlinked state/lock paths, group/world-writable state directories,
non-regular or non-private lock files, and lock-path/inode replacement around
`flock`.

Kernel now owns the outer execution lock, hash-chained coordinator start/terminal
receipts, a shared journal accessor, a repair factory and bounded repair-outcome
receipts. The durable journal's separate lock rejects symlinked state and lock paths,
insecure state-directory permissions and non-private lock files. A process restart reconciles an orphaned coordinator receipt to
`unknown_outcome` only after a same-host process identity proves the writer is
gone. Kernel does not apply source edits: the existing FixLoop/repair policy and
disk-backed `Transaction` remain the mutation, rollback and Git-delivery path.
`Mission` remains the durable cross-run objective and lease owner.

The convergence implementation retains its existing responsibility modules:
`FixLoop::Lifecycle` owns journal resume, incremental-scope proof and checkpoint
restoration; `FixLoop::PassExecution` owns bounded passes and structural
follow-ups; `FixLoop::Completion` owns gap-aware terminalization and Mission
updates. `Fix::OutcomePolicy` remains the common source for terminal states and
result-category mapping. Regression tests now cover Kernel receipts and a
process-boundary crash/restart with an open transaction, journal resume, Mission
checkpoint survival and orphan-receipt reconciliation. They are **authored, not
executed** on the pinned Ruby 4.0.5 runtime, so Mission/journal-loss reconstruction,
budget/collapse behavior, adapter receipt parity and a real repository-wide
`/fix` trial remain open proof gates in `docs/fix_coordinator_map.md`.

CoreBridge attaches a lifecycle observer to the Fold even when the host does not
supply a bus; that case uses the event log at the task runtime root, or MASTER's
canonical runtime root when working in pub4 itself. The standalone `bin/master core`
subcommand uses the same shared Trace::EffectObserver adapter, so it does not bypass
the lifecycle contract. `core:effect:before` is durably published before each World effect and
`core:effect:after` records the observed outcome and elapsed time. Rollback is a
separate audited operation linked to the failed effect and its checkpoint. If the
required after-event cannot be persisted, the mission fails terminally instead of
being automatically resumed against an ambiguous side effect. Event payloads carry a typed
effect ID, turn, verb, capability, run ID, attempt ID and mission ID; source scope is
represented by a SHA-256 digest, not a raw path, URL or command argument. Failure to persist the before-event
prevents the effect from running; failure to persist the after-event returns `trace_failed`
rather than claiming the task completed. This path uses `EventBus#publish_required` and the
event log's strict append method, while ordinary best-effort telemetry retains its existing
failure-swallowing behavior. The legacy `core:turn` stream is also privacy-safe now: action
subjects are categorical, the detail is reduced to completed/failed, and read/exec output is
represented by byte and line counts. Full observations remain only in the local operator
transcript. This is the first slice of the external-action event contract, not yet a shared
event adapter for every tool and /fix path.

Interactive turns carry a cooperative cancellation token through the session and TurnRouter.
The general Core Fold checks it at safe proposal/admission/effect boundaries. The canonical
`/fix` command carries the same token through PipelineContext and FixLoop, which stops
between preflight phases and repair passes. If cancellation arrives during a pass, that
bounded pass is allowed to finish and record its receipt before any later repair or structural
pass is started; persisted active-transaction recovery runs before a resumed repair is stopped.
Cancelled, unknown-outcome and recovery-failed repair missions are terminal and cannot be
automatically resumed, and cancellation never claims delivery. A model request, check or
external operation already in progress is not forcibly killed; non-interactive background runs
and other commands retain their existing lifecycle.

The normalized contract adapter and its migration boundary are documented in
[Execution contracts](docs/execution-contracts.md). Its existence does not mean the
Fix transaction, all tools, background jobs or deployment paths have already migrated.
The new regression tests are source changes only until executed on the pinned Ruby runtime;
validation remains INCONCLUSIVE in this checkout.

A requested repair starts by inventorying its eligible corpus, refreshing the
static reference graph and refusing to proceed if an eligible source could not
be read or indexed. Before a proposed edit, the repair receives the complete
target file and complete sources for the direct graph-linked dependencies and
callers that the graph can resolve, with SHA-256 identifiers. These are treated
as untrusted source data, never as instructions. A missing linked file or a
context that exceeds `MASTER_FIX_CONTEXT_MAX_BYTES` stops that repair rather
than clipping the input and guessing. The graph now uses Prism to identify Ruby class, module, constant and
method definitions, plus statically identifiable method calls, inheritance,
mixins and constant references, alongside import edges. It reports unresolved
references and dynamic sites; repairs defer when unresolved relationships could
affect the target or its directly linked files. Dynamic receiver types,
reflection, metaprogramming, plugin discovery, runtime loading and non-Ruby
import/call graphs remain incomplete, so this is not proof that every possible
caller has been discovered.

The unbounded worklist is scanned before repair starts, then prioritized by the
highest finding severity, weighted finding impact and a stable path tie-break.
An explicit `--max-files` is a bounded lane; `MASTER_FIX_RANK=1` asks for a
full scan before choosing the highest-impact files within that cap. Formatting
frequency and alphabetical order are not importance measures.

On a target inside one RAILS app, `/fix` follows the verified fix with the layout loop of
`bin/operator design`, with no flag to add. That loop keeps a stylesheet edit only when the surface's measured layout score
rises and nothing else gets worse, commits each kept edit locally for review, and never pushes; a target
that names no single app skips the loop.

Each owned repair checkpoint must pass its applicable syntax, intent and delivery
guards before it is committed and pushed. This is the default; set
`MASTER_FIX_PUSH=end` to defer pushes until final verification, or
`MASTER_FIX_NO_PUBLISH=1` to leave commits local deliberately. Another operator's
pre-existing dirty work is never part of the batch. An unsuccessful or
unconfirmed push is a delivery failure, not a completed repair.

Every repair is proved against what was already red. Before its first edit,
`/fix` measures the target read-only; a commit another session lands meanwhile
leaves that measurement valid, while a file edited under it does not. A
whole-MASTER repair is then proved by the tests that name the files it changed,
judged against the known-red record the last whole suite left, so a failing test
that record does not name refuses the repair. The record names failing tests,
lapses after a day or a change of Ruby or lockfile, and a record naming only
failed steps sends the proof back to the whole suite. A target is Rails when its
files say so, an application or an engine above it, and a Rails target is proved
by the check runner over the apps `RAILS/apps.yml` registers. A run whose budget
ran out while no process held it is closed, and the next `/fix` starts afresh.
Every commit the runtime makes refuses the sacred paths `data/soul.yml`
declares, whichever writer left them changed.

For model-assisted findings, each /fix repair route proposes several materially
different candidates (three by default), then selects one using the target Law and
focused-test evidence. The candidate prompt draws action/fault oracles from
RAILS/test/interaction_campaign_400.json for the relevant surface. Existing focused
tests run against the baseline and each candidate in test mode; candidates that
introduce failures are rejected and the exact original source is restored after
each run. /fix records the command paths and distinguishes PASS, improved,
no-regression, blocked and unavailable outcomes. The 400 natural-language
campaign cases guide candidates but are not themselves 400 executable browser
tests; a case stays NOT_RUN until that interaction is run and evidenced.

Code that changes behavior, interfaces, commands, configuration or operations
must carry matching changes to the relevant README or contract. Generated
documentation is regenerated from its canonical source, never hand-edited, and
unrelated documents are left alone.

A fix run attempts every actionable finding in scope and repeats measurement and
repair. It cannot promise to repair literally everything: unsupported surfaces,
unresolved findings, timeouts, quota exhaustion and human decisions must remain
visible. Only `DONE` with full applicable coverage and the required consecutive
clean readings proves completion; every other terminal state remains open work.

The run is journaled before its first repair pass, so a crashed attempt is resumed
rather than mistaken for success. An unfinished goal is a durable mission in
`.master/mission.json`; its supervisor renews its lease and retries with bounded
backoff. Observe, plan, repair and deploy modes choose a starting set of
capabilities but never outrank the law.

For the web, source-clean is not enough. When the target is under `RAILS/`, the
visual pass captures browser renders and geometry when the browser and app are
available; missing live evidence remains inconclusive, never a pass. The repair
loop uses its ordinary finding and candidate-selection path to propose layout
changes, then measures the resulting render again. The multi-model critique
council is opt-in inside `/fix`: set `MASTER_FIX_COUNCIL=1` or request
`--critique`; otherwise the report offers `/critique` on the result instead
of making every repair wait on the council. A successful source scan alone does
not prove visual completion.

## Debugging Ruby behavior

Start with a reproducible failing test, then use the pinned Ruby debugger for
live state and call-stack inspection:

```zsh
RBENV_VERSION=4.0.5 rbenv exec ruby -rdebug -Itest test/test_execution_trace.rb
```

Place `binding.break` at the narrowest useful line. Use `caller_locations(1, 8)`
to inspect the caller chain, and `method(:call).source_location` /
`method(:call).super_method&.source_location` to locate the active implementation
and its next `super` implementation. Remove temporary breakpoints before
committing; do not introduce a permanent Pry/byebug dependency just for debugging.

For object collaboration problems, use the bounded
`Master::Trace::ObjectProbe` with explicit receiver objects and a method filter.
It captures call/return order, dispatch owner, source location and exception
class, but deliberately omits arguments and return values. Its event limit is
explicit, and `method_chain` reports prepended modules and superclass
implementations. For mutation/lifetime bugs, compare
`ObjectProbe.state_snapshot(object)` before and after a call, then inspect
`ObjectProbe.state_diff(before, after)`; snapshots report object identities and
container shapes, never stored values. Keep the scope narrow: TracePoint can add
substantial overhead when enabled on busy objects.

For a quick, temporary inspection, use `pp object` or `p object.instance_variables`
at the narrowest point. A breakpoint can inspect locals without changing the
return value:

```ruby
require "pp"
pp service.instance_variables.to_h { |name| [name, service.instance_variable_get(name).class] }
binding.break
```

Use `Master::Trace::ObjectProbe.state_snapshot(object)` before and after an
operation to compare instance-variable identities, frozen state and basic
container shapes without emitting the values. `state_diff(before, after)` names
the shape changes. This is intentionally shallow: equal-length edits inside a
container are not claimed as detected. For a likely allocation leak, enable
`ObjectSpace.trace_object_allocations_start` before creating the suspect
objects, then inspect allocation source locations; allocation tracing changes
runtime memory and should be stopped after a narrow reproduction.

Use `/diag`, the existing dmesg trace level and the per-turn trace when the
failure depends on normal runtime behavior. For unhandled collaborations, inject
a timeout, failed write, malformed reply, duplicate event or stale record through
the existing dependency seam and verify the expected failure result. Compare old
and new implementations against the same fixtures during refactors; add
property-based tests for invariants across generated inputs and mutation testing
when the repository's pinned toolchain supports it. Promote every confirmed
defect to a minimal regression test. Never patch `NilClass` globally or install
a permanent method wrapper just to inspect a call path, and never treat an
unexecuted test, a surviving mutation, or an unavailable instrument as proof.

## Research and training

MASTER can look things up. It retrieves from local knowledge, searches the web,
and fetches public pages through guarded adapters, including GitHub, arXiv by
way of ar5iv, and CodePen. `web_browse` reads rendered pages and writes
nothing. Whatever it brings back is untrusted until checked. Setting
`MASTER_LLM_RECORD=1` records verified model and tool trajectories in a form
independent of any model vendor, so the same record can score or filter any
small model. Training happens outside MASTER, and only verified behavior comes
back.

Conversational support follows the rubric in `data/dialogue_rubric.yml` and is
added to the dynamic prompt only when the current turn calls for it. It covers
practical coping skills, CBT/DBT/ACT-informed approaches, depression, anxiety,
ADHD, OCD, trauma, bipolar disorder, psychosis, eating and alcohol concerns,
relationship conflict, coercive-control awareness, manipulation resistance,
medication boundaries, martial-arts philosophy and research habits. Sensitive
mental-health, relationship and abuse details are not persisted to shared memory
or profiles without explicit opt-in and permission from the active privacy policy.
When recognized personal stories trigger research, the agent and guarded
`WebSearch` adapter reduce the query to generic evidence topics before external
search and its permission telemetry. This is lexical minimization, not a complete
data-loss-prevention guarantee; verify its coverage in `test_evidence_router.rb`,
`test_agent.rb` and `test_io_tools.rb`.
English, Bokmål and Nynorsk routing examples—including factual family mentions, explicit self-harm denials, mixed-risk statements, indirect crisis language, violence-related wording, unlabeled emotional-abuse patterns and philosophical martial-arts questions—are covered by `test/test_dialogue_rubric.rb`.
Research URLs are starting points: the runtime must actually consult a source
before claiming it performed research. Topic routing is lexical assistance, not
a clinical classifier or suicide-risk assessment. MASTER must not diagnose a
person from chat, direct medication changes, treat a prompt cue as proof of
abuse, or describe itself as a therapist. When imminent danger may be present,
ordinary coaching yields to immediate, locale-appropriate human support;
relationship violence may make joint sessions unsafe, so safety and confidential
individual support take priority.

The synthetic response-quality screen is exposed as
`Master::Voice::DialogueRubric.run_support_benchmark` and through
`/support benchmark --confirm [response-model] [judge-model]` in the CLI and
web command palette. Confirmation is required before the bounded run because
it can make up to sixteen model calls. A run is capped at eight
named scenarios; it records each candidate answer, grades practicality,
empathy and agency, calibration, safety, research quality and fit, treats
malformed judge output as inconclusive, and lets critical safety findings
override aggregate scores. Every grade requires human review. Different model
identifiers do not prove that two judgments are independent, and a benchmark
pass is not evidence of clinical safety or treatment efficacy. The focused
regression suite is `ruby -Itest test/test_dialogue_rubric.rb`, run from this
directory with MASTER's pinned Ruby and dependencies. The suite has not yet
been executed in the pinned runtime for this change.

## Model pool

The router discovers reachable models from configured tiers, local Ollama installations, hosted OpenAI-compatible endpoints and provider catalogs. `ModelRouter` delegates candidate selection to `model_router/selection.rb`; deterministic `RoutePolicy` decides from a supplied snapshot of reachable, parked, usable, recently failed and operation-floor candidates without performing I/O. Provider availability, health, quota, compute ranking and existing lane ordering remain explicit collaborators, so one failed or parked lane cannot silently become the whole policy. The focused policy fixtures live in `test/test_route_policy.rb`; runtime routing still needs verification against the configured providers and MASTER's pinned Ruby. All requests retain the existing budget, provider-health and fallback controls.

An OpenAI-compatible gateway such as a local freellmpool instance is opt-in:

```zsh
export MASTER_LLM_GATEWAY_URL=http://127.0.0.1:PORT/v1
# Only when the gateway requires authentication:
export MASTER_LLM_GATEWAY_KEY=...
bin/master
```

FREELLMPOOL_PROXY_KEY is also accepted. The URL must be absolute HTTP(S), contain no embedded credentials, query or fragment, and use HTTPS unless its host is loopback. The gateway's /v1/models response becomes the discovered pool, and chat calls use /v1/chat/completions. MASTER does not install or launch the gateway, treat free-tier capacity as guaranteed, or claim offline operation when only a remote route is available. Provider environment values belong in the operator's protected environment file, not in source control or command history.

## External assessment and business direction

MASTER can assess a public website from observable evidence, review source when the owner grants repository access, and use its existing governed tools to create one prioritised remediation plan. These capabilities have different boundaries and should not be presented as interchangeable scanners.

- **Design and UX:** use the existing Browser to inspect rendered pages at desktop and mobile sizes, capture screenshots, and route them through an available vision lane. Review hierarchy, typography, contrast, responsive states, navigation, keyboard access and accessibility. HTML-only evidence cannot establish visual quality.
- **Code and architecture:** when source is available and authorised, inventory the repository, read entrypoints and dependencies, inspect callers and tests, run MASTER's existing laws, then verify proposed repairs. A black-box web page cannot prove the internals of its code.
- **Network and security:** ExternalAudit performs passive HTTP(S), redirect, TLS and response-header observations plus basic HTML semantics. VulCheck reports local posture observations and can run already-installed scanners only with a second dangerous-tier permit; it never installs or updates packages. Nmap is an active, bounded scan of one explicitly authorised host. Its basic, services and safe profiles avoid full-port sweeps and exploit scripts, but `safe` is an NSE script category, not a zero-impact guarantee. A missing header or unavailable check is not a confirmed vulnerability or a pass.
- **Evidence contract:** separate confirmed defects, hypotheses, missing evidence and out-of-scope checks. Findings should name the URL or file/line, observed evidence, confidence, impact, remediation and how the repair can be verified. This is not a penetration-test certification.

**Code-level review requires separately authorised source access.** The `ExternalAudit` URL lane does not inspect unseen source and does not claim that it did; use the existing repository/source review workflow against an owner-authorised copy. Until that end-to-end source lane is proven with a fixture, report code-side conclusions as INCONCLUSIVE rather than inferring them from page output.

### Competitive landscape

The space is already competitive, and product boundaries overlap: GitHub bundles CodeQL/code scanning with dependency and secret-protection capabilities; Snyk markets a platform spanning code, open-source dependencies, secrets, containers, IaC and DAST. Therefore, “one security dashboard” is not a credible differentiation by itself. The narrower hypothesis is a trusted evidence trail that connects rendered UI and accessibility findings to authorised source review, then proves the fix. This remains a hypothesis, not a demonstrated market gap. [GitHub Code Security](https://docs.github.com/en/get-started/learning-about-github/about-github-advanced-security) · [Snyk platform](https://snyk.io/platform/)

| Segment | Benchmarks | Established strength |
| --- | --- | --- |
| Source and dependency security | [GitHub Code Security](https://github.com/features), [Snyk](https://snyk.io/product/), [Aikido](https://www.aikido.dev/) | Source analysis, dependency findings and developer workflow integration |
| Dynamic application security | [OWASP ZAP](https://www.zaproxy.org/), [StackHawk](https://www.stackhawk.com/) | Purpose-built DAST/API testing and repeatable security scans |
| Network discovery | [Nmap](https://nmap.org/book/), [NSE script categories](https://nmap.org/nsedoc/categories/) | Mature host, port and service discovery |
| Accessibility and visual quality | [Deque axe DevTools](https://www.deque.com/axe/devtools/), [Lighthouse](https://developer.chrome.com/docs/lighthouse/overview), [BrowserStack Percy](https://www.browserstack.com/percy) | Automated accessibility checks, page-quality metrics and visual regression |

For EU-facing e-commerce, accessibility may also be a compliance driver: Directive (EU) 2019/882 applies from 28 June 2025 to specified covered products and services, including e-commerce. Confirm the customer's country-specific scope, exemptions and local implementation with qualified counsel before offering a compliance verdict. [Official Directive (EUR-Lex)](https://eur-lex.europa.eu/eli/dir/2019/882/oj)

MASTER should integrate mature specialists rather than re-create their scanners. The candidate distinction is one evidence trail that connects rendered user experience, source evidence, network observations and verified remediation.

**Nmap licensing check:** the official Nmap legal notice states that embedding or redistributing Nmap in commercial software/hardware products requires its special OEM licence. The repo calls an already-installed executable and does not vendor the scanner; before packaging or productising a paid hosted Nmap-backed workflow, resolve the applicable licence with counsel or use a separately licensed alternative. [Nmap legal notice](https://nmap.org/book/man-legal.html).

### Business hypothesis and strategy

**Initial offer:** a bounded evidence-backed review of a public website or an owner-authorised app, ending in a concise severity-ranked report and repair plan. Repository access adds code-level evidence; implementation of fixes is a separately authorised service. Do not sell it as a certified pentest or as a replacement for specialist auditors.

**Initial buyers to test:** independent web agencies, small SaaS firms and Norwegian/European SMEs preparing for launch, redesign or customer security review. Offer a fixed-scope diagnostic first, optional remediation next, then test recurring release reviews. Agency and hosting-provider referrals are plausible channels, not validated channels.

**Validation before scale:** interview ten target buyers and run three paid pilots with written scope. Present the same pilot at three test prices rather than assuming a market price; record actual conversion and buyer-reported alternatives. Measure confirmed-finding rate, false positives, time to first useful finding, time to verified remediation, delivery cost, willingness to pay and repeat purchase. Keep the dashboard and multi-tenant service small until buyers repeatedly pay for the report and the follow-through. The possible moat is evidence and verification, not a new scanner. Risks include false positives, out-of-scope testing, liability and a scope too broad to deliver well.

### Pilot and funding route

The first paid experiment should be a tightly scoped website review with an evidence-backed report and optional, separately authorised remediation. Test this with a few agencies and small SaaS/SME buyers before building a hosted dashboard or assuming recurring demand.

### Ask and evidence

The funding route to investigate includes Innovasjon Norge ([innovasjonnorge.no](https://www.innovasjonnorge.no/)), subject to the current programme criteria, eligibility assessment and an independently checked budget. This document does not claim eligibility or approval. The ask should fund measured pilot delivery, buyer interviews and validation of the evidence-to-verified-fix workflow, not a speculative expansion of scope.

### Horizon

**Next 90 days:** complete buyer interviews, run three fixed-scope pilots, record conversion and false-positive rates, measure delivery cost and time-to-verified-remediation, and decide whether repeat purchase is real. Continue only on evidence from paying customers.

## Runtime

MASTER pins Ruby 4.0.5. Isolated execution through `Ruby::Box` is available only
when the process was started with `RUBY_BOX=1`, and the adapter in
`Master::Runtime::Box` does not pretend otherwise. Startup prefers YJIT, and
`MASTER_JIT=zjit` selects ZJIT as an experiment. The parallel compute path uses
`Ractor::Port`.

Speech is data. `data/voice.yml` names the voices, the processing chain applied
after synthesis, and the bed under the speech, and the web face reads the same
file so that it sounds like the server. The terminal bed uses Dilla minor chords
and Rhodes through the existing dilla_night effects rig at low playback level.
Its ~/.master/bed/dilla-chords cache replaces the former hum and space-tone tracks.
The design tokens live in
`data/tokens.yml`, read through `Master.tokens`.

Local append-only telemetry uses `Master::Trace::Log.append_jsonl` where the
record shape and retention contract permit it. The writer serializes rotation and
append, rejects symlink targets and oversized records, and defaults to the shared
25 MiB log ceiling; sensitive telemetry uses private file and directory modes.
The canonical activity/evidence streams, provider health/quarantine, the incident
notebook, Phoenix provenance, metrics, OpenTelemetry traces and the tool audit use this path. The Swallow error log is
standalone-loadable and maintains its own equivalent locked, capped writer. The
/fix conflict journal keeps its three bounded generations under the same kind of
sidecar lock, and the Reflexion ledger atomically retains its newest 50 rows. A
cap is a retention boundary, not a guarantee that every historic row is kept;
billing ledgers and generated-media manifests need their own explicit retention
decision rather than being silently truncated.

## Entering

MASTER has one interactive input prompt: the Ruby REPL prompt generated by Voice::Renderer and
edited by Reline. The terminal face is an optional full-screen visual over the same session and
prompt, not a second shell prompt. Bare bin/master stays at the REPL; /face opens the visual stage,
and Ctrl-D returns from that stage to the same REPL. Ctrl-C cancels current work or clears a draft.
Repository-wide scanning is opt-in with MASTER_BACKGROUND_SCAN=1; startup scanning does not grant
repair permission, and /fix remains an explicit instruction.

`bin/master "<instruction>"` runs one instruction across the repository, and
bare `bin/master` opens a session. A question goes to the agent, which reads and
searches the checkout before it answers; only an instruction or a slash command
reaches a command. `bin/master core` drives the fold spine alone, and
`bin/master --help` lists every flag. `bin/operator` is the operator's surface: it runs the
check ladder, reports status, lints files by the laws with no model, runs the
tests that prove a change, manages the production box, boots the
Rails apps with `triangle`, and writes snapshots. `bin/operator snapshot` writes
one snapshot per tree for another model to read, and `--mirror` writes the
byte-exact pack. `bin/check` runs the checks for a profile, among operator,
contributor, agent, web, ci and full. Each step writes to `.master/check` as it
runs, and the check names a failing test when it fails, counts the tests run
each minute and calls a step stuck after two silent minutes. `rake test` deals
the suite across three processes, `MASTER_TEST_JOBS` sets how many, and a test
that overruns its limit prints the line it is stuck on.

The `checks` directory holds the Rails and web checks, and `tools` holds the
scanners, audits and censuses behind the operator. Plugins in `plugins` extend
MASTER without joining its core: a Wi-Fi and Bluetooth observer, and two
governed browsers for social accounts and travel bookings. Each plugin runs
under a policy declared in `data/laws.yml`.

Documentation is checked as source: the test suite verifies local Markdown link targets and cited repository paths in maintained entry documents. External link availability is not treated as proven by an offline test. Writing guidance stays with `data/laws.yml`; tree READMEs remain the human entry points, with the OpenBSD runbook and manual pages serving operational work. Use [Google's technical-writing guidance](https://developers.google.com/tech-writing) and [Diátaxis](https://diataxis.fr/) as editorial references; [Awesome Markdown](https://github.com/mundimark/awesome-markdown) is a tool catalogue, not the project's style authority.

On a phone, MASTER detects Android under Termux and exposes only what the
Termux:API app reports, so a missing permission is reported as unavailable and
never simulated. Location, camera and microphone are explicit operations and
never boot probes. `/android` pairs the phone with its owner, and `/ios` starts
the browser lane without claiming native hardware access.

Production is one OpenBSD box. A long-lived MASTER process there owns Git sync
and deployment, and `/fix` takes the same execution slot, so repair cannot
overlap a deploy.

## Why Norway

The world spends heavily on machine intelligence, and nearly all of it burns
electricity in large buildings. The limit has moved from chips to clean power.
Norway's grid is almost entirely hydropower and among the cheapest in Europe,
and cold fjord water cools a hall at no cost. A sovereign AI on that power is a
better product than one on rented heat. MASTER is the first rung of that plan:
the mind, and the clean ground it stands on. The project is also its own
business plan, put to Innovasjon Norge. Its full funding figures sit with the
operator, not in this file.

The design is an embryo. A small core of identity, memory and safety takes on
whatever body a mission needs. Today that body is software. The same core could
one day serve machines that clear debris from the sea, but that is a horizon and
not a claim.

## In code

Every change a model wants runs through the loop below, from `lib/core/fold.rb`.
Read [AGENTS](AGENTS.md) for the contract every agent works under, and the
operator-only work in [operator seams](data/operator_seams.yml). Licensed MIT.

```ruby
def run(goal)
  @memory.note(:goal, goal)

  @max_turns.times do |turn|
    effect = @model.propose(@memory.context, verbs: @world.verbs, scope: @memory.proof.scope)

    case @law.admit(effect, @memory)
    in Verdict::Block(reason:, by:)
      observation = Observation.no("refused by #{by}: #{reason}")
      @memory.record(effect, observation)
      emit(turn, effect, observation)
    in Verdict::Request(effect: asked, prompt:, reason:, by:)
      done = approve(turn, asked, prompt:, reason:, by:)
      return done if done
    in Verdict::Allow(effect: admitted)
      done = apply(turn, admitted)
      return done if done
    end
  end

  Done.new(reason: :max_turns, turns: @max_turns, summary: nil)
end
```

## Local manual pages

The BSD-style reference pages for stable MASTER commands are under
`man/man1/`. From the repository root, look them up with:

```zsh
MANPATH="$PWD/MASTER/man" man master
MANPATH="$PWD/MASTER/man" man operator
MANPATH="$PWD/MASTER/man" man master-fix
```

The manuals describe operator interfaces; the executable command registry,
implementation, Laws and tests remain authoritative.

## Tradedoubler Claims API

MASTER's first TradeDoubler adapter handles the documented token-based Claims API only. Product and voucher imports remain in `RAILS/__shared`; publisher-site/programme management and earnings remain disabled until an OAuth token exchange and one authenticated management GET establish the correct TD Connect routes. The local source registry deliberately contains no guessed site or programme IDs.

Set `TRADEDOUBLER_CLAIMS_TOKEN` in the shell or secret manager used to invoke `bin/operator`. It is a distinct Claims-system token; do not reuse the RAILS Products token unless the publisher account confirms that it is the Claims token, and never commit or paste credentials.

Check configuration without reading credentials or making a request:

```sh
bin/operator affiliate status
```

After confirming the publisher site's IDs in TradeDoubler, populate `MASTER/data/affiliate_sources.yml` for `brgen` and `amber`. Grant access for a short window with an exact confirmation phrase, read claims, then revoke:

```sh
bin/operator affiliate grant claims.read --confirm "GRANT tradedoubler.claims.read"
bin/operator affiliate claims list
bin/operator affiliate claims list --source brgen --since 2026-10-01
bin/operator affiliate revoke claims.read --confirm "REVOKE tradedoubler.claims.read"
```

Claim creation is two-step. Prepare a local JSON file containing `source`, `program_key`, `timeStampEvent`, `eventId`, `orderNumber`, `orderValue`, and `expectedCommission` when `eventId` is 17, plus any allowed optional fields documented in `data/affiliate_sources.yml`. The source and program IDs are injected from the reviewed registry. Preparation writes a private local record and prints its SHA-256 without contacting TradeDoubler. After checking the full summary, submit only with a fresh five-minute grant and a second hash match:

```sh
bin/operator affiliate grant claims.prepare --confirm "GRANT tradedoubler.claims.prepare"
bin/operator affiliate claims prepare ./claim.json
bin/operator affiliate revoke claims.prepare --confirm "REVOKE tradedoubler.claims.prepare"
bin/operator affiliate grant claims.submit --confirm "GRANT tradedoubler.claims.submit"
bin/operator affiliate claims submit <sha256> --confirm-hash <same-sha256>
```

A submit attempt consumes the grant. MASTER never automatically retries a create request: an ambiguous timeout is recorded as uncertain and must be reconciled against the remote claims list before further action. HTTP acceptance means accepted for advertiser review, not approved or earned. Sources, programmes, compensation and earnings reports remain unavailable until the OAuth path is verified.

## Personal preferences

MASTER now has a consent-gated, per-subject preference store at `.master/workspace/<subject>/PREFERENCES.yml`, separate from the profile and episodic memory. It is loaded into the existing prompt builder for the general conversation and the best-matching task scope.

After pairing locally and granting the existing personal-memory scope with `/privacy grant personal_memory`, use `/preferences show` and `/preferences set communication.detail=brief` (or choose another validated key/value from `/help preferences`). Supported scopes are `all`, `coding`, `research`, `support`, `creative` and `planning`; a task-specific value overrides the general value only for that scope. Values are a closed vocabulary, not free-form prompt instructions.

`/preferences learn on` enables a bounded detector for a small set of explicit, low-risk correction phrases. The same signal must recur in two separate user turns before MASTER stages an inactive suggestion. Only the pattern ID, task scope, count and timestamp are stored; raw user messages are not retained as learning evidence. Pending suggestions are surfaced in the prompt and `/preferences show`; only `/preferences accept ID` activates one. `/preferences reject ID`, `/preferences forget KEY`, `/preferences reset --confirm` and `/preferences export` are available. Learning is off by default. Turning it off clears unconfirmed automatic observations and automatically inferred suggestions, while preserving owner-created suggestions and accepted preferences. This is not automatic psychological profiling and does not save sensitive traits. Preference data never grants tool access, changes permissions or overrides Laws, safety, required confirmations or current-turn instructions. The command is local-only and visitor sessions cannot read or write another person's settings.

## Personal privacy and consent

Read `personal_privacy` in `data/laws.yml` before enabling personal-device, companion or financial workflows. `Master::Ground::PersonalPermissions` is a local, default-deny ledger with expiry, immediate revocation and inspectable audit events. Personal-memory grants are bound to one paired subject; `PersonalWorkspace` and `OwnerProfile` refuse reads/writes without the exact `read and write personal profile and memory` purpose grant. Run `/privacy status`, `/privacy grant personal_memory`, or `/privacy revoke personal_memory` in a local, non-visitor paired session. An unpaired `MemoryRecord` user fact is refused rather than written to shared `data/project_context.yml`. Pairing no longer duplicates the owner label into memory before consent. These are source changes, not a claimed test pass: the Ruby suite and Android/Termux acceptance have not been run. Microphone, speech recognition, camera, location, contacts, messages, notifications, financial data/actions, purchases, deployment and destructive operations remain unintegrated and must stay disabled until their adapters enforce this policy and any native OS permission. A paired person is not automatically the operator; public visitors cannot grant. See the single repository backlog for remaining adapter integration and real-device proof.

## /fix architecture tournament and interaction acceptance

A requested /fix targeting the repository root or an exact top-level MASTER, RAILS,
OPENBSD or STUDIO tree now performs a read-only architecture tournament before repair.
It asks for 36 candidates per tree by default (configurable through
MASTER_FIX_ARCHITECTURE_CANDIDATES, clamped to 30–40) in one structured generation per
tree. Candidates must reference existing source evidence and test anchors, state a
verification plan and rollback path, and remain within the target tree. Local scoring
uses source grounding, existing tests, verification specificity, rollback quality, scope
control and Law alignment; model scores are ignored and near-duplicates are rejected.

A winner requires at least 30 distinct, grounded candidates. The tournament itself does
not run tests or edit files, and its report marks runtime tests NOT_RUN. The selected
direction and five-candidate shortlist guide narrow fixes only; they do not authorize
large rewrites or bypass the ordinary Law, transaction and verification requirements.
Generation failures or fewer than 30 valid candidates are reported as INCONCLUSIVE.

The canonical 90-item interaction inventory is MASTER/data/ux_refinements.yml. Every
entry has owner-tree metadata, a test/rendered proof expectation, and an
acceptance_required state. It is included in the /fix protocol fingerprint and adds
target-relevant acceptance contracts to the repair context. The visual Law's required
evidence includes prompt contracts, input recovery, browser reconnection, visible state,
keyboard accessibility and terminal modes. A catalogue row is not proof that the behavior
is implemented or passing; close it only with the declared test or live/rendered evidence.


## Rendered surface and public metadata checks

The existing `surface_schema` check now validates the five declared Brgen surfaces for exactly one non-empty document title, meta description, absolute canonical URL, Open Graph title/description/URL, as well as their existing layout and interaction markers. Positive fixtures exercise complete metadata; `MASTER/test/test_dom_surface_seo_metadata.rb` proves missing descriptions, duplicate canonicals and relative canonical URLs are detected. This is source/fixture coverage, not proof of a full public-host crawl; the broader hostname, redirect, robots, sitemap and JSON-LD audit remains in the root TODO.

The metadata attribute checks respect the active quote delimiter, so valid apostrophes inside titles and descriptions remain accepted; relative canonicals and duplicate/empty metadata remain invalid. A dedicated negative/positive regression covers this distinction.

The OpenBSD tracked PF ruleset guard is registered in the single check runner as `openbsd_pf_policy`. It checks the repository-specific default-deny, explicit interface scope on pass rules, and SSH/bruteforce ordering invariants; the current ICMP type allowlist is a named exception; `pfctl -nf` remains the authority for native PF syntax on OpenBSD.


## Response security header contract

The registered `security_headers_source` check guards the current split: relayd owns HSTS and common edge headers, while Rails owns per-app nonce CSP and the frame-ancestor allowlist used for intentional Brgen/Amber embedding. It rejects a global CSP setter at relayd because that overwrites the Rails nonce policy, and it rejects wildcard or `unsafe-eval` script sources. This is source-policy evidence only. CSP remains report-only until the operator enables and verifies `PUB4_CSP_ENFORCE=1` on vm23; see the `csp_enforced_on_vm23` operator seam for live evidence.
