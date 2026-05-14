# MASTER Multi-Session Collaboration Protocol

MASTER may be edited by multiple autonomous or semi-autonomous sessions at once.
Direct writes to `main` are unsafe under that model.

## Hard Rule

Do not push directly to `main` when more than one session may be active.

Use session branches.

```text
session/<agent>-<focus>-<yyyymmdd>
```

Examples:

```text
session/master-visualizer-20260514
session/master-epistemics-20260514
session/master-repo-ecology-20260514
```

---

# Branch Discipline

Each session branch should contain one coherent focus:

- visualizer
- pressure engine
- repo ecology
- reference graph
- epistemics
- runtime hardening
- refactor pass

Avoid mixing unrelated architectural work.

---

# Merge Protocol

Before merge:

1. Rebase onto current `main`.
2. Run syntax checks.
3. Run `/scan` or equivalent static scan.
4. Run `/ecology` if tree structure changed.
5. Review touched paths.
6. Confirm no overlapping session changed the same files.
7. Merge with a clear summary.

---

# Conflict Policy

If two sessions touch the same file:

- stop both branches
- compare intent
- preserve smaller coherent change
- manually merge
- rerun checks

Never force-push over another session's work unless explicitly approved.

---

# Commit Shape

Good commits are:

- small
- reversible
- focused
- testable
- named by behavior

Bad commits are:

- giant mixed patches
- vague cleanup
- unrelated visual + runtime + docs changes
- speculative architecture without executable code

---

# Safety Requirements

Every branch that mutates behavior should report:

- files changed
- commands added
- runtime risks
- rollback behavior
- test status
- known uncertainty

---

# Preferred Flow

```text
branch
→ implement
→ scan
→ ecology
→ syntax/test
→ rebase
→ review
→ merge
```

MASTER should optimize for convergence over accumulation.

Multiple sessions are useful only when they reduce entropy.
If they increase conceptual sprawl, pause and consolidate.
