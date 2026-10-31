# The `.pub4` permission matrix — harness-only, not enforcement

## The decision

`MASTER/.pub4` is **harness-only**. Nothing in this repository reads it. The deep
analysis of MASTER (October 2026) found no reader for it anywhere under `lib/`,
`tools/`, `bin/`, `checks/` or `contracts/` — the only `.pub4`-shaped strings in the
tree are unrelated paths (`~/.pub4/ssh-connections.log`, the `Pub4MobileApp.swift`
URL notification name). The file describes a permission matrix that the external
harness may consult; the runtime itself neither loads it nor enforces it, and this
commit makes that explicit instead of leaving it as an unenforced permission matrix
that invites false confidence.

## What the file contains

```yaml
schema: 1
tree: master
allows:
  master: read_write   # MASTER may read and write the MASTER tree
  rails: read          # MASTER may read the RAILS tree
  openbsd: none        # MASTER may not touch OPENBSD
  studio: none         # MASTER may not touch STUDIO
adapters: []
```

`allows` is a tree-to-tree permission matrix across the four pub4 trees, and
`adapters` is the (empty) list of cross-tree adapter registrations.

## What this means in practice

- **Do not trust it as a boundary.** The boundaries that actually hold are the ones
  with readers and tests: `Ground::Policy::Sandbox` (path scope, deny patterns),
  PathGuard/WriteGuard (realpath-based scope, sacred paths), and the Governor's tier
  approval with the @auto allowlist and per-run budget. A cross-tree write that
  `.pub4` forbids is forbidden only if one of those mechanisms forbids it too.
- **Do not widen it to grant yourself permission.** Editing `.pub4` grants nothing,
  because nothing reads it.
- **If a reader is ever wanted**, it arrives together with its tests and a law
  fixture under `law/` — same rule as any other config key in this tree: no reader,
  no key. Until then this document is the only interpretation of record, and the
  harness contract lives outside the repo.

## Why document rather than implement

An in-repo reader with tests would put the runtime's own cross-tree policy under the
runtime's control, which is exactly the confidence the matrix cannot deliver while
the enforcement points (Sandbox, PathGuard, WriteGuard, Governor) take their scope
from config and law, not from `.pub4`. Documenting the file as harness-only keeps
the matrix honest: it constrains the harness operator, not the agent.
