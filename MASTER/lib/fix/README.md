# Fix

**A scanner that only reports is half a system; fix is the other half.** It scans,
repairs, verifies, and commits, and every mutation it makes is reversible before
it makes it.

`fix_loop.rb` and `fix_loop/` run the iterative pass. `fix_attempt.rb`,
`violation.rb`, `severity.rb` and `constants.rb` are the value objects and the
shared thresholds that pass carries. `rule_loop.rb` converges one rule at a time,
scoring candidates and checking for regressions. `watch_loop.rb` and `watcher.rb`
scan on file change; `heartbeat.rb` scans on a schedule.

Three files hold the pressure back. `homeostat.rb` reads runtime pressure and
adapts. `governor.rb` limits rate and throughput across runs. `self_check.rb`
stands in front of the one dangerous case, a loop about to mutate its own source.

The reversible path is `checkpoint.rb`, `diff_stager.rb`, `patch_applier.rb` and
`rollback.rb`. `checkpoint.rb` copies the files a pass is about to touch into
`.master/checkpoints` and copies them back on request, refusing any path that
escapes the root either way. `conflict_resolver.rb` settles two fixes that want
the same lines, and `propose_tree.rb` is where a proposal evolves before either
of them sees it.

Verification closes the loop. `patch_verifier.rb` asks whether a change landed —
the file is there, the symbol is somewhere under `lib/`, the caller names it — and `done_checker.rb` puts that question to a whole plan and answers
done or not done. `unfinished_ledger.rb` keeps what was left open, so a pass that
stopped short says so instead of reading as finished.

The filenames are canonical. Any numbered architecture label you find in a
comment names nothing that exists.
