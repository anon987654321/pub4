# MASTER/bin
 
**Two commands open this whole system: `operator` and `master`.**
 
## The Operator Surface (`bin/operator`)
The operator surface is for management, measurement, and auditing.
- `gate`: The primary convergence chain. Scans, fixes, and verifies across the whole repository.
- `lint`: A deterministic, non-mutating scan of the codebase.
- `measure`: Prints every ratchet (metric) against its ceiling.
- `readers`: A census of which components reach which files.
- `doctor`: Environment and wiring diagnostics.
 
## The Instruction Surface (`bin/master`)
The instruction surface is the gateway to the agentic runtime.
- `bin/master "<instruction>"`: Boots the runtime around a single goal.
- `bin/cli`: Opens an interactive session with the MASTER agent.
 
## The Convergence Loop
The runtime implements a deterministic state machine:
**Discover $\rightarrow$ Analyze $\rightarrow$ Plan $\rightarrow$ Implement $\rightarrow$ Validate $\rightarrow$ Converge $\rightarrow$ Deliver**.
 
Every turn is recorded in the `Episode Ledger` and linked via the `Structural Trace` to provide a complete, auditable proof of work.
