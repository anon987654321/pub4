# Start Here

MASTER is a constitutional AI runtime in Ruby. Models propose actions; the runtime validates them against `data/soul.yml`, `data/rules.yml`, and scanner rules before durable writes. The Rails web face in `web/` mirrors runtime state.

## Fast Orientation

Read these first:

1. `README.md` for the short project identity.
2. `AGENT_CONTRACT.md` for safe collaboration rules.
3. `RUNTIME_MAP.md` for the major runtime paths.
4. `PATH_OWNERSHIP.yml` for path purpose and risk.
5. `EXAMPLES.md` for good/bad patch and triage shapes.
6. `web/BOOT_CONTRACT.md` before touching the chat face boot path.

## Safe First Commands

- `bin/check` runs the normal contributor gate.
- `bin/check-agent` runs the self-test law gate and may fail on known debt.
- `bin/check-web` runs static web UI checks; set `MASTER_WEB_LIVE=1` for live web checks.
- `bin/check-full` runs the full CI/probe/audit path and may fail until known debt is triaged.

## Source And Local State

- Source: `lib/`, `kernel/`, `data/`, `bin/`, `test/`, `spec/`, `web/app/`, `web/public/`.
- Local/generated: `.master/`, `knowledge/`, `output/`, `web/public/assets/`, `web/storage/`, `web/log/`.
- High-risk web boot files: `web/app/views/chat/index.html.erb`, `web/public/face*.js`, `web/public/face.part*.txt`, `web/public/three.face.module.js`.

## Law Ladder

Treat guidance by force:

1. Fatal invariant: preserve working behavior, user intent, and secrets.
2. CI gate: tests, syntax, YAML shape, self-test when intentionally running agent/full gates.
3. Scanner finding: triage as true violation, false positive, or rule retune.
4. Design preference: follow when local code supports it.
5. Philosophy/research: use as context, not as permission to rewrite unrelated code.

## Before Editing

- Read the target file and its nearby tests.
- Check `PATH_OWNERSHIP.yml` for risk.
- Prefer small patches and local patterns.
- Update `TODO.md`, `DECISIONS.md`, or `DEBT.md` when the change settles a known ambiguity.
- Run the smallest check that proves the work.
