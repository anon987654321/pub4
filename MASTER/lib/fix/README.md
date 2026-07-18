# Loop architecture map

The loop subsystem implements the runtime feedback architectures described in the project docs.

- `fix_loop.rb` and `fix_loop/`: iterative scan, repair, verification, and commit passes.
- `fix_attempt.rb`, `violation.rb`, `severity.rb`, `constants.rb`: fix-loop value objects and shared thresholds.
- `rule_loop.rb`: one-rule convergence with candidate scoring and regression checks.
- `watch_loop.rb` and `watcher.rb`: file-change-driven scans.
- `heartbeat.rb`: scheduled health and self-application checks.
- `homeostat.rb`: runtime pressure and adaptive behavior.
- `governor.rb`: rate/throughput limiting across loop runs.
- `self_check.rb`: self-application safety checks before a loop mutates its own source.
- `diff_stager.rb`, `patch_applier.rb`, and `rollback.rb`: reversible mutation path.
- `conflict_resolver.rb`: competing-fix resolution.
- `propose_tree.rb`: proposal evolution path.

The numbered architecture labels in older comments are historical navigation aids; these filenames are canonical.
