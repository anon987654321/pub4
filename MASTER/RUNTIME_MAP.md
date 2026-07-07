# Runtime Map

This is the short map for people and agents trying to find the right edge of MASTER.

```text
bin/cli
  -> Master.bootstrap_container
  -> lib/now pipeline and command registry
  -> lib/judge scanners, output checks, council, routing
  -> lib/loop fix/watch/self-check loops
  -> lib/reach tools and external actions
  -> lib/trace evidence, session, event, and telemetry records
  -> web/ Rails face for chat/runtime visibility
```

## Major Areas

- `bin/`: executable entry points and checks.
- `lib/master*.rb`: boot, data loading, runtime bootstrap.
- `lib/now/`: CLI, commands, pipeline stages, web server adapters.
- `lib/judge/`: scanning, verdicts, routing, output contracts, review logic.
- `lib/loop/`: rule loop, fix loop, watcher, rollback, self-check pressure.
- `lib/reach/`: tool implementations, external calls, file/search/shell actions.
- `lib/ground/`: constitution, config, memory, policy, schema, immutable basics.
- `lib/trace/`: append-only evidence, events, telemetry, replay, snapshots.
- `lib/voice/`: personality, rendering, TTS, speech, visual state.
- `kernel/`: isolated constitutional Effect -> Constitution -> World fold.
- `data/`: operator-facing registries and constitutional configuration.
- `web/`: Rails face and static JS runtime.

## High-Risk Boundaries

- Law: `data/soul.yml`, `data/rules.yml`, `data/rules/*.yml`.
- Boot: `lib/master.rb`, `lib/master_boot.rb`, `lib/builder*.rb`.
- Web tap path: `web/app/views/chat/index.html.erb`, `web/public/face*`, `web/public/three*`.
- External actions: `lib/reach/`, `lib/ground/tool_*`, `lib/ground/sandbox_policy.rb`.
- Persistent memory/evidence: `lib/trace/`, `lib/ground/memory*`, `.master/`.

## Check Selection

- Ordinary code: `bin/check`.
- Constitutional/agent behavior: `bin/check-agent`.
- Web face: `bin/check-web`.
- Release/operator pass: `bin/check-full`.
