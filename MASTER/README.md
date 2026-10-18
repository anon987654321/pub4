# MASTER

**MASTER is an artificial intelligence written in pure Ruby that governs itself
by law instead of by hope, grown in Norway and meant to run its own mind on
clean power drawn from inside a fjord mountain.** Most systems let a model act
first and inspect the wreckage afterward. MASTER inverts the order. The model
only proposes, and nothing touches a file until a written constitution admits
it.

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
when a human can read both the law and the code it judges, and Ruby reads like
intention. The constitution therefore stays legible. One kernel, `data/soul.yml`,
holds the unbreakable rule: preserve, then improve, and never break. Under it,
`data/laws.yml` declares the working laws. Under that, the files in `law/` carry
each law as executable code, with one example it must flag and one it must
spare. A break gets a refusal with a reason, never a quiet patch.

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

A requested repair starts by inventorying its eligible corpus, refreshing the
static reference graph and refusing to proceed if an eligible source could not
be read or indexed. Before a proposed edit, the repair receives the complete
target file and complete sources for the direct graph-linked dependencies and
callers that the graph can resolve, with SHA-256 identifiers. These are treated
as untrusted source data, never as instructions. A missing linked file or a
context that exceeds `MASTER_FIX_CONTEXT_MAX_BYTES` stops that repair rather
than clipping the input and guessing. The current graph is static: dynamic
dispatch, reflection and arbitrary runtime loading still require explicit
reference investigation and runtime evidence; the graph is not proof that every
possible call edge has been resolved.

The unbounded worklist is scanned before repair starts, then prioritized by the
highest finding severity, weighted finding impact and a stable path tie-break.
An explicit `--max-files` is a bounded lane; `MASTER_FIX_RANK=1` asks for a
full scan before choosing the highest-impact files within that cap. Formatting
frequency and alphabetical order are not importance measures.

Each owned repair checkpoint must pass its applicable syntax, intent and delivery
guards before it is committed and pushed. This is the default; set
`MASTER_FIX_PUSH=end` to defer pushes until final verification, or
`MASTER_FIX_NO_PUBLISH=1` to leave commits local deliberately. Another operator's
pre-existing dirty work is never part of the batch. An unsuccessful or
unconfirmed push is a delivery failure, not a completed repair.

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

For the web, source-clean is not enough. When the target is under `RAILS/`, a
pass renders the pages in a real browser, measures their geometry, and hands the
screenshot and the measurements to a council. The council's chosen repairs
become ordinary findings, and the next pass renders again. If the browser or the
council cannot run, the pass says it is inconclusive and does not claim
success.


## Debugging Ruby behavior

Start with a reproducible failing test, then use the pinned Ruby debugger for
live state and call-stack inspection:

```zsh
RBENV_VERSION=4.0.7 rbenv exec ruby -rdebug -Itest test/test_execution_trace.rb
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

## Model pool

The router discovers reachable models from the configured tiers, local Ollama installations, hosted OpenAI-compatible endpoints and provider catalogs. All requests still pass through MASTER's existing fallback, budget and provider-health policies; adding a gateway does not bypass those controls.

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
- **Network and security:** ExternalAudit performs passive HTTP(S), redirect, TLS and response-header observations plus basic HTML semantics. VulCheck reports local posture observations and can run already-installed scanners only with a second dangerous-tier permit; it never installs or updates packages. Nmap is an active, bounded scan of one explicitly authorised host. Its basic, services and safe profiles avoid full-port sweeps and exploit scripts. A missing header or unavailable check is not a confirmed vulnerability or a pass.
- **Evidence contract:** separate confirmed defects, hypotheses, missing evidence and out-of-scope checks. Findings should name the URL or file/line, observed evidence, confidence, impact, remediation and how the repair can be verified. This is not a penetration-test certification.

**Code-level review requires separately authorised source access.** The `ExternalAudit` URL lane does not inspect unseen source and does not claim that it did; use the existing repository/source review workflow against an owner-authorised copy. Until that end-to-end source lane is proven with a fixture, report code-side conclusions as INCONCLUSIVE rather than inferring them from page output.

### Competitive landscape

The space is competitive and split across specialties; the cross-discipline gap is a hypothesis, not a proven absence of competitors.

| Segment | Benchmarks | Established strength |
| --- | --- | --- |
| Source and dependency security | [GitHub Code Security](https://github.com/features), [Snyk](https://snyk.io/product/), [Aikido](https://www.aikido.dev/) | Source analysis, dependency findings and developer workflow integration |
| Dynamic application security | [OWASP ZAP](https://www.zaproxy.org/), [StackHawk](https://www.stackhawk.com/) | Purpose-built DAST/API testing and repeatable security scans |
| Network discovery | [Nmap](https://nmap.org/book/), [NSE script categories](https://nmap.org/nsedoc/categories/) | Mature host, port and service discovery |
| Accessibility and visual quality | [Deque axe DevTools](https://www.deque.com/axe/devtools/), [Lighthouse](https://developer.chrome.com/docs/lighthouse/overview), [BrowserStack Percy](https://www.browserstack.com/percy) | Automated accessibility checks, page-quality metrics and visual regression |

MASTER should integrate mature specialists rather than re-create their scanners. The candidate distinction is one evidence trail that connects rendered user experience, source evidence, network observations and verified remediation.

### Business hypothesis and strategy

**Initial offer:** a bounded evidence-backed review of a public website or an owner-authorised app, ending in a concise severity-ranked report and repair plan. Repository access adds code-level evidence; implementation of fixes is a separately authorised service. Do not sell it as a certified pentest or as a replacement for specialist auditors.

**Initial buyers to test:** independent web agencies, small SaaS firms and Norwegian/European SMEs preparing for launch, redesign or customer security review. Offer a fixed-scope diagnostic first, optional remediation next, then test recurring release reviews. Agency and hosting-provider referrals are plausible channels, not validated channels.

**Validation before scale:** interview ten target buyers and run three paid pilots with written scope. Measure confirmed-finding rate, false positives, time to first useful finding, time to verified remediation, delivery cost, willingness to pay and repeat purchase. Keep the dashboard and multi-tenant service small until buyers repeatedly pay for the report and the follow-through. The possible moat is evidence and verification, not a new scanner. Risks include false positives, out-of-scope testing, liability and a scope too broad to deliver well.

## Runtime

MASTER pins Ruby 4.0.7. Isolated execution through `Ruby::Box` is available only
when the process was started with `RUBY_BOX=1`, and the adapter in
`Master::Runtime::Box` does not pretend otherwise. Startup prefers YJIT, and
`MASTER_JIT=zjit` selects ZJIT as an experiment. The parallel compute path uses
`Ractor::Port`.

Speech is data. `data/voice.yml` names the voices, the processing chain applied
after synthesis, and the bed under the speech, and the web face reads the same
file so that it sounds like the server. The design tokens live in
`data/tokens.yml`, read through `Master.tokens`.

## Entering

`bin/master "<instruction>"` runs one instruction across the repository, and
bare `bin/master` opens a session. `bin/cli` is the same runtime without the
repository-wide setup. `bin/operator` is the operator's surface: it runs the
gate ladder, reports status, lints files by the laws with no model, runs the
tests that prove a change, manages worktrees and the production box, boots the
Rails apps with `triangle`, and writes snapshots. `bin/operator snapshot` writes
one snapshot per tree for another model to read, and `--mirror` writes the
byte-exact pack. `bin/check` runs the checks for a profile, among operator,
contributor, agent, web, ci and full.

The `gates` directory holds the Rails and web gates, and `tools` holds the
scanners, audits and censuses behind the operator. Plugins in `plugins` extend
MASTER without joining its core: a Wi-Fi and Bluetooth observer, and two
governed browsers for social accounts and travel bookings. Each plugin runs
under a policy declared in `data/laws.yml`.

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
repository's single backlog in [backlog](../TODO.md). Licensed MIT.

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
