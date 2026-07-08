# Agent Contract

This contract is for AI agents and humans who want predictable collaboration with MASTER.

## Operating Modes

- Contributor mode: make narrow changes, run `bin/check`, and avoid broad constitutional cleanup.
- Operator mode: run full gates, triage debt, and change policy or runtime contracts deliberately.
- Agent mode: obey this file, surface uncertainty, and run `bin/check --profile=agent` when changing law or agent behavior.

## Work Rules

- Preserve behavior first; improve second.
- Read before writing.
- Do not collapse files that only look similar until their live consumers are known.
- Keep generated and local-only artifacts out of source changes.
- Report blocked checks exactly, including the command and the first useful failure class.
- Update documentation when you rely on an intentional exception.

## Tool Rules

- Use `rg` for search.
- Use `bin/check` for ordinary local validation.
- Use `rake lint:data_singularity` after YAML registry edits.
- Use `bin/check --profile=web` after web face or asset changes.
- Use `bin/check --profile=agent` after changes to `data/soul.yml`, `data/rules.yml`, scanners, loop repair, or agent routing.

## Reporting Rules

Good closeout:

- changed files and purpose
- checks run
- known failures with current counts
- remaining operator decisions

Bad closeout:

- vague "should work"
- hidden skipped checks
- TODO checkboxes changed without evidence
- unrelated cleanup mixed into feature work

## Do Not Optimize Away

- The `lib/` and `kernel/` spines both define `Master::` intentionally.
- `data/rules/` shards are split by scanner scope intentionally.
- `knowledge/` is local-only but still powers `SearchKnowledge`.
- WebGL face boot is deferred until the primer tap.
- Some self-test findings are known debt; do not chase them during unrelated work.
