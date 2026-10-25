# Runbook: rendered layout and accessibility

Source-level CSS checks and browser-rendered evidence answer different
questions. Run the existing browser diagnostics from the repository root
against live app ports; the diagnostic runner reports unavailable apps or
browsers as SKIPPED/INCONCLUSIVE instead of silently green.

    ruby OPENBSD/bin/evidence browser-diagnostics -- env CHECK_BROWSER_DIAGNOSTICS_OUTPUT=evidence/browser-diagnostics ruby MASTER/checks/runner.rb browser_diagnostics

Review the emitted route/viewport manifest and every screenshot. The runner
uses the canonical MASTER/checks/data/geometry_surfaces.yml inventory; do not
change it merely to make a run smaller. Capture the additional acceptance
widths 320, 360, 375, 390, 430, 480, 640, 768, 1024 and 1280 CSS pixels for
relevant MASTER/RAILS surfaces, with the geometry measurements retained in the
run manifest beside the screenshots. Record viewport, app/host, browser/runtime,
commit and timestamp.

At each required width, inspect:

- keyboard-only traversal, visible focus, logical order, Escape behavior and
  absence of focus traps;
- 200% zoom, reflow, horizontal overflow, keyboard-open layouts and safe-area
  insets;
- forced-colors and prefers-reduced-motion: reduce;
- preferred 44px touch targets on mobile, dashboard density and prompt/face
  coexistence;
- console errors, failed resources, route status and failed asset recovery.

Do not treat a single desktop screenshot as evidence for mobile geometry.
Attach reviewed screenshots and geometry files to a later evidence capture:

    ruby OPENBSD/bin/evidence --attach evidence/browser-diagnostics/<run-id>/screenshots/<surface>.png --attach evidence/browser-diagnostics/<run-id>/manifest.json --note 'I reviewed the named screenshot and manifest; record the exact result and any findings' visual-review -- env CHECK_BROWSER_DIAGNOSTICS_OUTPUT=evidence/browser-diagnostics/review-run ruby MASTER/checks/runner.rb browser_diagnostics

The command runs a real fresh browser-diagnostics pass and records the prior
reviewed PNG/manifest hashes and the reviewer’s note. Replace illustrative
paths with real files, inspect the fresh manifest too, and do not use a no-op
command as a surrogate for a browser check.

## Fresh asset budgets

Measure generated CSS, JavaScript and PWA payload budgets in a fresh
source-to-build pass. Preserve existing ratchets and CSS cascade order.
A ceiling is not raised to make a regression pass. When a build or browser is
unavailable, record that limitation instead of recording a green result.
