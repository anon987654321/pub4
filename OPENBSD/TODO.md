# OPENBSD TODO

Updated: 2026-10-11. Production truth is observed vm23 state; repository inventories and runbooks are not proof that external DNS, certificates or backups are healthy. Cross-tree work is indexed in the repository-root `TODO.md`.

## P0 — production safety

- [ ] **svalbrd.no renewal (Johann, Domeneshop login).** Observed 2026-10-12: Norid lists it registered (created 2020-09-06, DNSSEC signed, NS `ns1-3.hyp.net`, A `185.134.245.113`, nothing on 443), but Norid publishes no expiry and `RAILS/apps.yml` records 2026-09-06, 36 days past; every sibling .no domain already reads 2027-08. It is probably renewed with the fact stale, but only the registrar can say. Read the renewal date there, set `owned_domain_facts.svalbrd.no.expires` in `RAILS/apps.yml`, run `ruby OPENBSD/bin/domain_watch.rb --update`; `ruby OPENBSD/test/test_domain_expiry.rb` going green proves it. It is the only red in that file; `domain_watch.rb` now fills .no expiries from the recorded facts so the other .no names are watched.
- [ ] **Lapsed city domains (Johann, money).** `brmingham.uk`, `glasgw.uk`, `lverpool.uk`, `mnchester.uk` and `dnver.us` are unregistered at their registries (whois 2026-10-12). Re-register at Domeneshop, or delete each zone and `acme-client.conf` block and record the decision in `data/domain_released.yml`. `ruby OPENBSD/bin/domain_watch.rb` lists them under "not registered" until one of those happens.
- [ ] **Watched deploys on vm23 (operator, not this session).** Per target and `all`: record commit, `~/vps-deploy.log`, `OPENBSD/bin/vps-state`, relayd and ports 61352/47312, and that amber and bsdports are back. Observed 2026-10-12 03:15 CEST: someone else was mid-`master` deploy (log at assets precompile); stamps were brgen ok `0a3181adb` (2026-10-10T05:09Z), amber failed `c4f56d285` (10-10 09:29Z), bsdports failed (10-10 09:44Z), master failed `a43c922d3` (10-10 20:01Z). Passes when `zsh OPENBSD/bin/vps-deploy all` ends `all ok` and `ruby OPENBSD/bin/vps-state` shows four stamps `ok`.
- [ ] **Observe the failure trap once on vm23.** `bin/vps-deploy` now stamps failed, names the stage, says whether the app is left stopped, lists shed amber/bsdports, releases lock and flag and appends `finished ... exit=N stage=...` to the log directly (unit-tested in `test/test_vps_deploy_contract.rb`, 19 runs). Still unobserved on the box: induce one failure at the next deploy window (for example a deliberate CI failure on a throwaway branch) and read `tail ~/vps-deploy.log` and `/var/db/pub4/last_deploy_<app>.json`. A stale zero-byte `/home/dev/pub4/.deploying-vps-deploy-brgen` from 2026-10-10 05:16 is on the box, so an earlier run ended without the old trap; the guard ignores flags over 30 minutes, so it is harmless, and `rm` it from the checkout after the next deploy.
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
