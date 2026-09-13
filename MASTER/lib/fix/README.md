# Fix

**A scanner that only reports is half a system; fix is the other half.** It scans,
repairs, verifies, and commits, and every mutation it makes is reversible before
it makes it.

`fix_loop.rb` and `fix_loop/` run the iterative pass. `fix_attempt.rb`,
`violation.rb`, `severity.rb` and `constants.rb` are the value objects and the
shared thresholds that pass carries. `rule_loop.rb` converges one rule at a time,
scoring candidates and checking for regressions. `watch_loop.rb` and `watcher.rb`
scan on file change; `heartbeat.rb` scans on a schedule.

Four things loop, and a process runs at most one of the three that write. The
fix loop starts only when `MASTER_AUTOFIX` is 1, and it sleeps its startup delay
before touching lib/. The watch loop starts only when `MASTER_WATCH` is 1. The
load watcher starts unless `MASTER_WATCHER` is 0, which the process defaults
set, so it too is off until asked for. `MASTER_LOOP=fix`, `watch` or `watcher`
picks one and zeroes the others, and `Ops::LoopSlot` refuses to boot with two.
The heartbeat sits outside that slot and runs only when `MASTER_HEARTBEAT` is 1.
The rule loop is never started on its own: the fix loop and the watch loop each
build one per rule inside their own pass. The web daemon on vm23 runs none of
them unless `/etc/master.env` sets a flag, and `limits.yml`'s `process:` block
holds the run and sleep budgets for each.

Three files hold the pressure back. `homeostat.rb` reads runtime pressure and
adapts. `governor.rb` limits rate and throughput across runs. `self_check.rb`
stands in front of the one dangerous case, a loop about to mutate its own source.

The reversible path is `checkpoint.rb`, `diff_stager.rb`, `patch_applier.rb` and
`rollback.rb`. `checkpoint.rb` copies the files a pass is about to touch into
`.master/checkpoints` and copies them back on request, refusing any path that
escapes the root either way.
`conflict_resolver.rb` settles two fixes that want the same lines, and
`propose_tree.rb` is where a proposal evolves before either of them sees it.

`content_dedup_scan.rb` reads the other direction: it flags lines that repeat
across the constitution files, and reports rather than repairs, because which
copy is right when two differ slightly is not safe to guess. `rake lint:dedup`
is its reader.

The filenames are canonical. Any numbered architecture label you find in a
comment names nothing that exists.
