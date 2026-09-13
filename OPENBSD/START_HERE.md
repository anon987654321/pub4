# Start Here

OPENBSD is the production surface for pub4: vm23 config backup, relayd,
NSD/acme, Rails 8 apps, MASTER web, and operator recovery tools.

Three doors: agents read `CLAUDE.md`, operators read `RUNBOOK.md`, and everyone
starts at `README.md`.

## Read First

1. `README.md` for the short layout.
2. `RUNBOOK.md` for everything else: deployment map, agent contract,
   live-operation safety (read before any SSH, `doas`, rc.d, pf, relayd, or
   full-stack deploy), deploy commands, gates.
3. `MASTER/START_HERE.md` for MASTER agent rules and the **data file budget**
   (why ~80 YAML files exist and what merges next).
4. `RUNBOOK.md` repair playbooks and patch examples when a gate fails.

## Golden Commands

`MASTER/bin/operator status` gives you the one-screen posture and the next
command. Every other command lives in `OPENBSD/data/operator.yml`, which is the
command list — `MASTER/lib/operator/operator_docs.rb` reads it and `/orient
deploy` prints it.

The gates under `OPENBSD/gates/` are registered in `RAILS/gates/gates.yml` and
run through `RAILS/gates/runner.rb`, because that runner is the one gate
registry; `OPENBSD/bin/check-openbsd` is what invokes them for this tree.

After `git pull` on vm23, never `git stash` to get a pull through. A stashed
`Gemfile.lock` has already taken master down once; resolve the conflict, then
run `OPENBSD/bin/post-pull-checklist`.

## Source Of Truth

`OPENBSD/data/operator.yml`'s `single_source_of_truth:` block, which names
features, horizon, debt and deploy identity. The OpenBSD configs themselves are
`OPENBSD/etc/`, and the procedure is `RUNBOOK.md`.

## Safety Defaults

- Do not run parallel SSH or parallel app CI on vm23.
- Do not expose app ports publicly; relayd terminates TLS and forwards to
  loopback.
- Do not commit `/etc/*.env`, Rails master keys, generated assets, or local VPS
  state.
- After `MASTER/web/` changes, precompile assets and restart Falcon; no hot
  reload exists in production.
- Prefer local static gates before touching the VPS.
