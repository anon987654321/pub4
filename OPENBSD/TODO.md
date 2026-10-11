# OPENBSD TODO

Updated: 2026-10-11. Production truth is observed vm23 state; repository inventories and runbooks are not proof that external DNS, certificates or backups are healthy. Cross-tree work is indexed in the repository-root `TODO.md`.

## P0 — production safety

- [ ] Verify registrar and authoritative DNS status for `svalbrd.no`: `RAILS/apps.yml` records an expiry of 2026-09-06, which is in the past, while the committed `OPENBSD/data/domain_inventory.yml` snapshot omits this owned domain. The test no longer pins that historical expiry date, but the actual registrar state remains unverified. The expiry gate now asserts that every renewable owned domain has a registered snapshot row with an expiry; until the stale snapshot is refreshed, this gate is expected to fail closed. Refresh from registrar evidence and reconcile the other owned domains absent from the snapshot. Check nameserver, DNSSEC and certificate state independently.
- [ ] Run the deploy-lock regression on OpenBSD and a developer host, then rehearse stale-lock recovery. The source now refuses to reap a live same-host owner solely because its timestamp exceeds the TTL; production safety remains unproven until the updated test passes.
- [ ] Perform a watched vm23 deploy for each supported target and the full fleet. Record the commit, deploy log, pre/post service state, relayd checks, public health and ports 61352/47312; verify amber and bsdports are restored after the serial deployment.
- [ ] Test deploy failure at each stage (pull, CI, sync, precompile, restart and post-deploy health). Locks and deploy flags must be released or deliberately retained with a clear recovery instruction; dependent services must not remain silently shed; the log must preserve the actual terminal result after SSH disconnect.
- [ ] Execute a restore drill from `OPENBSD/bin/dr-pull` into an isolated scratch location. Verify checksums and application-level readability, record recovery time, prove backup copies exist off-host, and document which secrets must be restored separately from `/etc/*.env`. A successful backup command alone is not a restore test.
- [ ] Verify domain/TLS state from the live box: NS delegation, A/AAAA resolution, DNSSEC, certificate dates/SANs, relayd configuration syntax, and real HTTPS health for every intended public host. Do not activate a relayd keypair before its certificate exists; distinguish intended-but-unpublished cities from broken live sites.
- [ ] Run `OPENBSD/bin/check --profile=full` and the watched post-deploy checks on current `main`. Fix failures and record explicit PASS/FAIL/INCONCLUSIVE results instead of treating unavailable vm23, DNS or backup storage as success.

## P1 — operations that fail clearly

- [ ] Add bounded monitoring for repeated relayd/watchdog restarts, failed app health, low disk/RAM and stale backups. A watchdog that heals a symptom must also leave an actionable durable alert when the symptom recurs.
- [ ] Prove deploy idempotence with two consecutive deploys of each target and the full fleet. The second run must not leave stale files, wrong sibling path gems, stale service flags or a different runtime than the declared inventory.
- [ ] Reconcile `OPENBSD/deploy_inventory.json`, `RAILS/apps.yml`, DNS templates and relayd routes through the canonical generator/gates; never hand-maintain a second app/domain inventory.
- [ ] Review OpenBSD package and base-system security updates against the deployed Ruby, database, TLS and media stack. Stage and record upgrades before applying them to the live host; preserve a tested rollback/recovery route.
- [ ] Rehearse low-disk, failed-precompile and failed-health scenarios without touching production data. Make failure output identify the failed stage, the services left running and the safe next command.

## P2 — KISS and maintainability

- [ ] Keep `OPENBSD/bin/vps-deploy` as the canonical serial deploy entrypoint and the operator recipes in their declared source. Remove redundant wrappers only after searching callers, installed paths and runbook references.


## Proof surfaces

`OPENBSD/bin/rehearse`, `OPENBSD/bin/check`, `OPENBSD/bin/check-vps`, `OPENBSD/test/run_all.rb`, `OPENBSD/bin/vps-deploy`, and watched vm23/registrar/DNS/backup evidence. Never run a destructive rehearsal against production.
