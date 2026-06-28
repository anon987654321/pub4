---
name: MASTER 7-module refactor (approved 2026-05-08)
description: User approved collapse of lib/master/ into 7 time-oriented modules — now/loop/judge/voice/ground/reach/trace. Multi-commit, pass-by-pass; ship on VPS dev@brgen.no.
type: project
originSessionId: 0c593fb2-cd49-4fd7-9e89-d77dd7e909ae
---

Approved 2026-05-08 after scan, sweep, and council on `lib/` and `DEPLOY`.

Target layout under `lib/master/`: `now/` for cli, repl, and pipeline; `loop/` for autoloop, sweep, heartbeat, and convergence; `judge/` for scan/rules, council, swarm, and security with a unified Verdict; `voice/` for personality, soul, renderer, and speech; `ground/` for config, axioms, and `data/*.yml` as the Constitution aggregator; `reach/` for tools/base plus twenty-four tools; `trace/` for session, telemetry, bus, and undo. This subsumes the Constitution aggregator, Tools::Base, deliberation unification, refactor cycle, Security::Policy, and the Voice namespace.

Passes run one commit each with tests green and Zeitwerk ok: skeleton, then voice, trace, ground, reach, judge, loop, and finally now with stages folded into pipeline-as-data in `now/pipeline.rb`. Work happens on VPS dev@brgen.no on branch `refactor/seven-modules`. Time-orientation—now versus loop versus trace—replaces file-type splits; `judge/` unifies four "is this OK?" trees.