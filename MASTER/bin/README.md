# MASTER/bin

**Two commands open this whole system, and everything else here is a stage one
of them runs.** `operator` is the operator surface and `master` is the
instruction surface. Run both from `MASTER/` unless a script says otherwise.
`MASTER/data/spine.yml` records how many executables this directory may hold, so
the next one argues for itself instead of arriving unnoticed.

`bin/operator gate` is the chain. It runs the scanner over all four trees with
autofix on, then every RAILS gate, then every suite, then the ratchets, the
sprawl census, and last the council. It names the files each stage changed and
refuses to report a clean pass over a tier it never reached. `bin/operator gate
--explain` prints the ladder without running it, and `--scan-only` measures
without writing. The operator surface also carries status, test, measure, lint,
land, worktree, rule, readers, hooks, snapshot and vps, and `completions/`
completes every one of them in zsh. `bin/master "<instruction>"` boots the
runtime around a single instruction; bare `bin/master` opens a session, and
`cli` is the interactive runtime it boots, so the two share one completion file.

Three scripts are stages of the gate rather than things to run alone. `gate`
scans, fixes, scans again, then critiques and reviews across the four trees;
run it by hand only to debug the scanner, because `bin/operator gate` is the
chain and `gate` is one rung of it. `check` runs the profiled suites —
operator, contributor, agent, web, ci and full. `ci` is the name GitHub Actions
and vm23 call, and it resolves to `check --profile=ci`.

Three things judge code by the law, and they differ in what they may do.
`bin/operator lint` scans files with every deterministic rule and no model, and
writes nothing, so it is the one to run on a diff before a commit; `--staged
--changed-lines` is the pre-commit shape. `/fix --dry-run` inside a session
is the same scan with the council behind it, and it writes fixes only when
given `--apply`. `rake constitution` counts MASTER's own findings against a
budget and is a ratchet, not a linter. To ask who reaches a file, use
`bin/operator readers`; the censuses in `tools/` answer narrower questions for
the ratchets and are not verbs to learn.

The rest diagnose. `probe` runs the readiness probes, and its audit probe is
`bin/operator lint` over the staged lines. `doctor` reports on the environment
and the wiring, which is also what to run before a deploy. `dogfood` boots the
CLI and talks to it. `smoke` checks boot and wiring and calls `tts-e2e` against
a running face, and `smoke-web` checks the face over HTTP; both need a live
server, which is why neither is a unit test. `nsaudit` audits namespace
references and `onboard` writes a new contributor's `.master/config.yml`.

A few serve a session or the runtime around it. `master-core` runs the fold with
a scripted model and passes only when the constitution refuses a `done` that
carries no real evidence; with `--real` it drives a live model instead.
`playbook` prints the operator playbook, `handoff` prints the state an incoming
agent needs, `cleanup` writes inventory reports on a clean tree and removes stray
root images only when told to apply, and `reset-costs` zeroes the local cost
counters. `test/test_bin_lifecycle.rb` runs each of these as a process.

Four drive speech. `tts-bootstrap` starts the worker stack, `tts-worker` is the
worker itself, `tts-speak` says one line, and `tts-e2e` polls the path end to
end.

Three settle the environment. `ruby` resolves the Ruby this repo prefers and
execs the rest of the command line under it, `sync-env` copies API keys from
shell profiles into a private `~/.config/master/env`, and `provider-catalog`
refreshes the provider model catalog.
