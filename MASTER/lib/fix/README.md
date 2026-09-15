# Fix
 
**A scanner that only reports is half a system; fix is the other half.** The Fix subsystem is the mutation engine of MASTER. It transforms the laws of the constitution into actual code changes through a deterministic loop.
 
### The Fix Pipeline
 
`fix_loop.rb` orchestrates the iterative pass: **Scan $\rightarrow$ Repair $\rightarrow$ Verify $\rightarrow$ Commit**.
- **Sensing**: `watch_loop.rb` and `heartbeat.rb` trigger scans based on file changes or schedules.
- **Control**: `governor.rb` limits throughput, while `homeostat.rb` adapts to runtime pressure.
- **Safety**: `self_check.rb` prevents the loop from mutating its own core logic without explicit authorization.
- **Reversibility**: Every change is backed by `checkpoint.rb` and `rollback.rb`, ensuring any mutation can be undone the moment it fails a verification gate.
 
### Deterministic Convergence
 
Fix does not "hope" a change works. It uses the `CompletionContract` to ensure that a fix is only committed when it is proven clean and correct. If a repair fails, the `AdversarialRegressionCorpus` records the failure signature to ensure the same mistake is never made twice.
