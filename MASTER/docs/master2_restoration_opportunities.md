# MASTER2 Restoration Opportunities (Reanalysis)

Date: 2026-04-30
Scope analyzed: `pub4/MASTER` against legacy source tree under `pub4/__predecessors/MASTER2`.

## What was reanalyzed

- Current `MASTER` tree structure and runtime library surface.
- Legacy `MASTER2` modules related to old Codex tasking and code-review subsystems.
- Existing in-repo restoration tracker document (this file), which had been overwritten by transient text (`circuit open: retry in 20s`).

## Findings

### 1) Corrupted restoration tracker (high priority)

The prior tracker file content was not actionable and appeared to be accidental transport error text.

**Restoration action autoimplemented:**
- Rebuilt this document with a fresh, explicit reanalysis snapshot.

### 2) Legacy review/task engines exist only in predecessor snapshot

The predecessor tree contains substantial legacy capability not currently mirrored 1:1 in `MASTER`, including:

- `__predecessors/MASTER2/lib/code_review/*`
- `__predecessors/MASTER2/lib/review/*`
- additional focused tests under `__predecessors/MASTER2/test/test_*review*` and related files.

These appear to be architectural ancestors rather than drop-in files for the current `MASTER` layout.

**Restoration decision:**
- No blind file-copy performed because interfaces and current architecture diverge, and unscoped bulk restoration would be unsafe.

### 3) Directly restorable opportunity implemented now

The only unambiguous, low-risk restoration opportunity in current scope was the damaged tracker itself.

**Autoimplemented:**
- Replaced corrupted placeholder with this complete reanalysis and restoration status document.

## Reassessment of old Codex tasks & code-review artifacts

- Old task/code-review artifacts were reassessed via predecessor inventory and current-tree capability mapping.
- Result: legacy modules are available for targeted future porting, but require staged integration plans (API compatibility, tests, and command wiring).

## Recommended next restoration batches (safe sequencing)

1. **Review engine portability slice**
   - Port one self-contained analyzer from `__predecessors/MASTER2/lib/code_review/` into `MASTER/lib/master/` with adapter tests.
2. **CLI/task wiring slice**
   - Reintroduce one legacy task command path with modern command registry conventions.
3. **Regression harness slice**
   - Add compatibility tests derived from predecessor review tests.

## Status

- Reanalysis: complete.
- Reassessment: complete.
- Autoimplementation: complete for all immediately safe restoration opportunities discovered in current scope.
