# Runbook: OpenBSD deploy, rollback and restore

Read OPENBSD/RUNBOOK.md before any live operation. Deployment and recovery
are privileged operator actions; do not execute them against vm23 or production
merely to generate an artifact. Establish the target, maintenance window,
rollback authority and expected deployed SHA first.

## Deployment/canary/recovery

Use the documented OPENBSD/bin/vps-deploy, canary and recovery entrypoints
for the target. Do not substitute a guessed command or manually run root shell
commands. For each approved stage, capture:

- intended source SHA and actual deployed SHA;
- canary output, service readiness and public/loopback health;
- git -C <production-worktree> rev-parse HEAD and status before/after;
- service restart outcome, bounded logs and relay/TLS route health;
- rollback reason, exact rollback target, restored health and final worktree state.

A local script fixture is not proof that the remote host is healthy. Confirm
the installed privileged broker and follow the canonical runbook’s brokered
path; do not deploy around a missing broker.

## Backup and restore drill

Run the documented backup check, verify the backup, restore into a scratch
location, and compare the restored data against the source. Record backup
identity/digest, source SHA or database checkpoint, destination, command
status, elapsed time and comparison result. Never overwrite live data during
a verification drill. Confirm scheduled jobs and monitoring actually fire;
attach relevant host/monitor exports without secrets.

## bsdports

Complete both the code review/tests and a real supported-OpenBSD lifecycle:
refresh the package index, inspect signed manifests, verify DNS/public-HTTPS
pinning, bounded response bodies, metadata/dependency and CVE edges,
disk-space fallback, rollback safety and a real package installation. A test
fixture or parser result is not a real index refresh or package install.

Use ruby OPENBSD/bin/evidence from the repository checkout to capture the real
documented command output and attach reviewed host logs/manifests. If no
supported OpenBSD host or permitted target is available, report BLOCKED or
INCONCLUSIVE and leave the TODO item open.
