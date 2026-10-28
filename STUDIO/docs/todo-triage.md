# TODO triage: code first vs evidence first

TODO.md is the single backlog for MASTER, RAILS, OPENBSD and STUDIO. This
file is an index and a closure protocol, not a second backlog: do not copy
TODO checkboxes here, and do not close an item here.

A source edit is not proof that the behavior works. A fixture, mock, static
contract, missing CI result or successful process launch is not a live pass.
Close an item in TODO.md only after its owning command or interaction ran
against the intended commit, the artifact was reviewed and committed, and the
closing commit cites the artifact and verdict.

## Evidence-first work

These items cannot be closed by a diff alone. A code fix may be required too,
but the live outcome remains a separate acceptance requirement.

| Backlog area | Evidence procedure |
|---|---|
| Bounded four-tree release and repository checks | runbooks/release-pass.md |
| The existing 400-case interaction campaign | runbooks/release-pass.md |
| Real-browser geometry, accessibility and layout screenshots | runbooks/rendered-layout.md |
| Installed PWA, offline/update recovery and host-aware manifest | runbooks/pwa.md |
| Real voice, interruption and latency on the target device | runbooks/voice-path.md |
| Deploy, canary, service health, backup and restore on OpenBSD | runbooks/openbsd-deploy-restore.md |
| Live calendar/email or messaging provider, human-reviewed advice, revenue path | runbooks/provider-integration.md |
| CLI/web state, cancellation, reload/draft retention and idempotent sending | runbooks/cli-web-ux.md |
| Dilla audio render, postpro/live output and measured audio quality | runbooks/studio-render.md |

## Code-first work

Patch the relevant owning source and regression tests first; then capture
evidence that the repaired behavior actually works.

| Area | Acceptance boundary |
|---|---|
| MASTER time-to-first-token and input acknowledgement | TODO.md, MASTER CLI/web/voice section |
| Search approval and intent routing | TODO.md, MASTER personal-assistance section |
| Reminder delivery and honest acceptance-time messaging | TODO.md, MASTER personal-assistance section |
| Ghostty-inspired console, prompt/face coexistence and state restoration | TODO.md, MASTER CLI/web/voice section |
| Brgen/Amber guest conversion and guest-transfer retries | TODO.md, RAILS section |
| bsdports HTTP, signature, DNS/HTTPS, disk and rollback hardening | TODO.md, RAILS and OPENBSD sections |
| Law catalogue, /fix ownership, transaction safety and scanner coverage | TODO.md, /fix transaction safety and Law coverage section |
| DRY/KISS, CSS/JS/PWA budgets and cross-tree performance | TODO.md, cross-tree section |

The runbook does not change the code backlog’s status. A code item stays open
until its own regression and required live evidence are both recorded.

## Evidence capture

Use ruby OPENBSD/bin/evidence LABEL -- COMMAND [ARG...] from inside the checkout.
The helper writes JSON and captured command output to evidence/, recording
the Git commit, branch, before/after dirty state, duration, exit status,
timeout, host/runtime and optional attachment SHA-256 values.

Exit sentinels are 0 PASS, 77 BLOCKED, 78 INCONCLUSIVE and 124 TIMEOUT. Any
other non-zero command result is FAIL unless an operator explicitly
reclassifies it with a non-empty --note. A non-zero command can never be
labelled PASS. An override never changes the command's exit status.

Inspect the log before committing it. Command output can still contain secrets
or personal data even though obvious credential-shaped command arguments are
redacted. Attach screenshot, video, device-log or geometry files with repeated
--attach PATH flags; the helper records a SHA-256 digest, not the media itself.

No runbook uses an empty command or a no-op to manufacture a pass. No file in
evidence/ is automatically trustworthy merely because the helper created it.
