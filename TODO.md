
## /fix constitutional hardening and UX backlog — opened 2026-10-05

This is the operating plan to tighten `/fix`, make it smoother for both agents and humans, and keep it aligned with the repo's constitution. It is a backlog item, not a claim of completed implementation.

### P0 — stop false convergence and noisy rule churn

- **Fix stream refresh before stagnation**: the pass stream must refresh touched findings before stagnation/oscillation logic runs. This is the first fix in the loop, because a successful repair that is then judged against stale findings produces false plateau/oscillation states.
- **Demote high-noise rules to measurement mode**: rules with a documented false-positive rate above the measured threshold (notably CQS, some magic-color and legacy detector families) should become non-blocking measurement rows unless they meet the rule's calibration gate. The registry can still report them without counting as a repair candidate.
- **Add calibration metadata to rules**: each detector should record its `known_false_positives`, `exclude_paths`, and `measurement_mode` contract in the rule entry or the registry so `/fix` can explain why it skipped or downgraded a rule.

### P1 — make the structure phase real, not aspirational

- **Implement the STRUCTURE preflight**: before scan and repair, run a bounded structural pass over a tree target (flatten, merge, decouple, relocate, rename) and emit a small set of recommended transformations with their proof boundary. This is the missing bridge between inventory and repair.
- **Require structural proof before multi-file restructures**: a structural change must produce before/after proof, a diff review, and a roll-back path. No rewrite should be treated as finished without the same proof discipline as a mechanical fix.
- **Keep rule ordering constitutional**: the ordering pass should read the same law-dependency graph (`data/laws.yml` + executable law) and not rely on ad hoc priorities.

### P1 — improve LLM operating context and resilience

- **Add a detector matrix to `/fix` context**: each rule entry should say whether it is scannable, semantic, practice-only, or conduct-only; and which tree scope it applies to. This is necessary for external agents and for consistent task planning.
- **Expose design and rule exemptions explicitly**: every path or rule exemption must be named, reasoned, and audited. `MASTER/data/laws.yml` is the authority; the runtime should surface which findings are exempt and why.
- **Add a rule health line to the `--full` context**: report detector kind, known false positives, and the current enforcement mode. This removes the second-source problem where the law says one thing and the agent memory says another.

### P1 — smooth the human experience and keep the command honest

- **Unify the operational surface**: `/fix`, `/review`, `/why`, and the dry-run path should share one inspection model, one output shape, and one proof contract. A human should not have to remember seven different entrypoints for the same underlying operation.
- **Stream measured progress**: the command should show counts, percentage completion, ETA, and the current rule or file being processed. Stale progress messages are worse than no progress.
- **Mark operator-owned decisions**: rendered values, aesthetic changes, and any content that changes style or production appearance should require an explicit operator decision gate before the write is accepted.
- **Produce one cross-tree report**: when a target spans MASTER + RAILS + OPENBSD + STUDIO, the result should still be one report with a unified verdict, not four independent shells of logic.

### P2 — constitution enforcement hardening

- **Enforce anti-simulation in output**: commands that describe future work or hypothetical changes must not claim certainty or present a plan as though it were already completed. Use the same grammar as the repo's anti-simulation policy and reject speculative wording in repair output.
- **Require evidence for all mutation claims**: a mutation report should include the changed file(s), the diff or direct proof, and the command output that verified the result. No silent “fixed” claims.
- **Keep rendered values below the operator layer**: the repair loop must refuse to modify a surface style without a human decision when the subject is operator-owned rendered output, including colors, spacing, font choices, sound parameters and layout values.

### P2 — scheduler and enforcement details

- **Add dry-run order to `/fix`**: `--dry` must follow the same inventory/repair planning loop but write nothing and report candidates, blocked items, and proof requirements.
- **Add explicit blocked states**: a fix may end as `DONE`, `PLATEAU`, `BLOCKED`, `VALIDATION_FAILED`, `HUMAN_DECISION`, or `DELIVERY_FAILED`; the output should say which stage produced the block and what proof remains missing.
- **Separate “measured” from “theoretical”**: a result counts as green only when the run measured the relevant evidence. “It should work” remains an unmeasured state and must not be reported as a pass.

### Acceptance criteria

- A restart or re-entrant pass no longer oscillates on stale findings.
- No high-noise rule is treated as a hard repair gate without a calibration proof.
- `/fix` reports one coherent run, not a sequence of contradictory mini-decisions.
- A rendered-value or design change is blocked until the operator has accepted the decision or the rule is explicitly exempted.
- The agent context includes a rule detector matrix and the rule's enforcement mode before the repair begins.

This work should be implemented in slices, with test coverage for the failing loop, noisy detector demotion, operator-owned value gates, and tree-level structure preflight before the broader UX simplifications are claimed complete.
