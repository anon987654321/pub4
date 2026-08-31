# MASTER/bin

**Two commands open this whole system, and everything else here is a stage one
of them runs.** `pub4` is the operator surface and `master` is the instruction
surface. Run both from `MASTER/` unless a script says otherwise.
`MASTER/data/spine.yml` records how many executables this directory may hold, so
the next one argues for itself instead of arriving unnoticed.

`bin/pub4 gate` is the chain. It runs the scanner over all four trees with
autofix on, then every RAILS gate, then every suite, then the ratchets, the
sprawl census, and last the council. It names the files each stage changed and
refuses to report a clean pass over a tier it never reached. `bin/pub4 gate
--explain` prints the ladder without running it, and `--scan-only` measures
without writing. The operator surface also carries status, test, measure, lint,
land, worktree and vps. `bin/master "<instruction>"` boots the runtime around a
single instruction; bare `bin/master` opens a session, and `cli` is the
interactive runtime it boots.

Three scripts are stages of the gate rather than things to run alone. `gate`
scans, fixes, scans again, then critiques and reviews across the four trees.
`check` runs the profiled suites — operator, contributor, agent, web, ci and
full. `ci` is the name GitHub Actions and vm23 call, and it resolves to `check
--profile=ci`.

The rest diagnose. `probe` runs the readiness probes, `audit` scans staged files
against the constitution before a commit, and `doctor` reports on the
environment and the wiring. `dogfood` boots the CLI and talks to it. `smoke`
checks boot and wiring, `smoke-web` checks the face over HTTP, and `preflight`
checks an OpenBSD box before a deploy. `nsaudit` audits namespace references and
`onboard` checks a new contributor's machine.

A few serve a session or the runtime around it. `master-core` exposes the core
spine, `playbook` runs a playbook, `handoff` writes an agent handoff bundle,
`cleanup` clears sessions and artifacts, and `reset-costs` zeroes the local cost
counters.

Four drive speech. `tts-bootstrap` starts the worker stack, `tts-worker` is the
worker itself, `tts-speak` says one line, and `tts-e2e` polls the path end to
end.

Three settle the environment. `ruby` resolves the Ruby this repo prefers and
execs the rest of the command line under it, `sync-env` refreshes env files from
their templates, and `provider-catalog` refreshes the provider model catalog.
