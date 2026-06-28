# Loop architecture map

The loop subsystem implements the runtime feedback architectures described in the project docs.

- `fix_loop.rb` and `fix_loop/`: iterative scan, repair, verification, and commit passes.
- `rule_loop.rb`: one-rule convergence with candidate scoring and regression checks.
- `watch_loop.rb` and `watcher.rb`: file-change-driven scans.
- `heartbeat.rb`: scheduled health and self-application checks.
- `homeostat.rb` and `system_pressure.rb`: runtime pressure and adaptive behavior.
- `diff_stager.rb`, `patch_applier.rb`, and `rollback.rb`: reversible mutation path.
- `conflict_resolver.rb`: competing-fix resolution.
- `crdt_loop.rb`: convergent multi-writer coordination.
- `propose_tree.rb` and `soul_proposals.rb`: proposal and constitutional evolution paths.

The numbered architecture labels in older comments are historical navigation aids; these filenames are canonical.
