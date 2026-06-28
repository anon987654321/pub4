---
name: MASTER 7-module refactor (approved 2026-05-08)
description: User approved collapse of lib/master/ into 7 time-oriented modules — now/loop/judge/voice/ground/reach/trace. Multi-commit, pass-by-pass; ship on VPS dev@brgen.no.
type: project
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---
Approved 2026-05-08 after scan+sweep+council on lib/ and DEPLOY.

**Target `lib/master/`:** now/ (cli, repl, pipeline); loop/ (autoloop, sweep, heartbeat, convergence); judge/ (scan/rules, council, swarm, security — unified Verdict); voice/ (personality, soul, renderer, speech); ground/ (config, axioms, data/*.yml — Constitution aggregator); reach/ (tools/base + 24 tools); trace/ (session, telemetry, bus, undo).

Subsumes: Constitution aggregator, Tools::Base, deliberation unification, refactor cycle, Security::Policy, Voice namespace.

**Passes** (one commit each, tests green, Zeitwerk ok): skeleton → voice → trace → ground → reach → judge → loop → now (stages/ → pipeline-as-data in now/pipeline.rb).

Work on VPS dev@brgen.no. Branch `refactor/seven-modules`. Time-orientation (now vs loop vs trace) over file-type splits; judge/ unifies four "is this OK?" trees.