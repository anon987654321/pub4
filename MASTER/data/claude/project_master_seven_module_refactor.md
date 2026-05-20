---
name: MASTER 7-module refactor (approved 2026-05-08)
description: User approved collapse of lib/master/ into 7 time-oriented modules — now/loop/judge/voice/ground/reach/trace. Multi-commit, pass-by-pass; ship on VPS dev@brgen.no.
type: project
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
User approved the radical 7-directory tree on 2026-05-08 ("i approve of all your suggestions") after scan + sweep + council runs on lib/ and DEPLOY surfaced the duplication patterns.

Target tree (lib/master/):
- now/      cli, repl, pipeline executor — synchronous user turn
- loop/     autoloop, sweep, heartbeat, convergence — async background
- judge/    scan/rules, council, swarm, security — verdict passes (unified Verdict shape)
- voice/    personality, soul, renderer, speech — output identity
- ground/   config, axioms, data/*.yml loaders — read-only constitution (Constitution aggregator)
- reach/    tools/base + 24 tools — actions on world (Tools::Base DRYs boilerplate)
- trace/    session, telemetry, bus, undo — write-only history

This subsumes the older 6 dedup proposals (Constitution aggregator, Tools::Base, deliberation unification, refactor cycle, Security::Policy, Voice namespace).

Pass sequence (one commit per pass, must keep tests green and Zeitwerk loading):
1. Skeleton — create empty dirs + README pointers
2. voice/ — move personality, soul, speech, renderer; update inflector + requires
3. trace/ — move session, telemetry, bus, undo
4. ground/ — move config, axioms, YAML loaders; introduce Constitution aggregator
5. reach/ — move tools, introduce Tools::Base, collapse 24 tool boilerplates
6. judge/ — move scan, council, swarm, security; introduce shared Verdict shape
7. loop/ — move sweep, autoloop, heartbeat, convergence
8. now/ — move cli + collapse stages/ into pipeline-as-data executor

Why: 100+ files split by file-type/domain are slicing the codebase against its own grain. Time-orientation (now vs loop vs trace) makes pledges/unveil and concurrency reasoning structural. judge/ unifies four trees that all answer "is this OK?" but reinvent the verdict shape.

How to apply: Work on VPS dev@brgen.no (memory: no heavy work on device). Create branch `refactor/seven-modules` off main. Each pass is one commit; if a pass breaks Zeitwerk or specs, fix in the same pass before moving on. Tradeoff accepted: stages/ disappears as directory — pipeline becomes a ~150-line lambda table inside now/pipeline.rb, losing per-stage class affordance for tests but collapsing 12 files.
