# Review
 
**Nothing MASTER writes reaches disk without passing through here.** Review is the epistemic gate of the system. It is where the laws are applied and the "Truth" is determined.
 
### The Review Hierarchy
 
1. **The Scanner**: Deterministic rules that flag violations.
2. **The Council**: Multi-agent deliberation that critiques the scanner's findings.
3. **The Swarm**: Parallelized execution of review tasks across specialized roles.
4. **The Crews**: Domain-specific agents (e.g., Security, Performance, Style) that provide deep-dive analysis.
 
### Role-Based Validation
 
Review leverages the **Architect $\rightarrow$ Implementer $\rightarrow$ Validator** split. The Validator role is specifically tuned to be adversarial, attempting to find holes in the Implementer's logic before the `CompletionContract` is satisfied.
 
Enter through `MASTER/bin/operator lint`, `MASTER/bin/gate`, or `rake selftest`.
