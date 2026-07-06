# Release readiness

Status: **ready** — all MASTER and DEPLOY gates green on the release branch. One operator
step remains for amber's public domain (see below).

## Release surface

| Service | URL | Wired |
|---------|-----|-------|
| MASTER (constitutional AI face) | https://ai.brgen.no | yes |
| brgen | https://brgen.no | yes |
| brgen · marketplace | https://markedsplass.brgen.no | yes |
| brgen · dating | https://dating.brgen.no | yes |
| brgen · playlist | https://playlist.brgen.no | yes |
| brgen · takeaway | https://takeaway.brgen.no | yes |
| brgen · tv | https://tv.brgen.no | yes |
| brgen · messenger | https://messenger.brgen.no | yes |
| amber | https://amberapp.com | **operator step** — served today at `amber.brgen.no` |
| bsdports | https://bsdports.org | yes |

The brgen verticals are one Rails app under subdomains; relayd already routes all of them
(`DEPLOY/openbsd/etc/relayd.conf`). Nine of the ten launch URLs are wired and pass the gates
unchanged.

## Verified green

Run from repo root / `MASTER/`:

```
cd MASTER && bin/ci                 # unit + kernel tests → clean
cd MASTER && bin/probe all          # smoke, nsaudit, kernel, dogfood, preflight, rails, phantom_fk → clean
cd MASTER && bin/probe deploy       # rails, phantom_fk, crawl, integrity, smoke-web, playbook → clean
ruby DEPLOY/integrity_gate.rb       # deploy_identity, production, phantom_fk, frontend, relayd, domain_align, crawl → clean
```

macOS-only skips (expected, not failures): `crawl`/`smoke-web` skip with no local server up,
`crawl-browser`/`health`/`vps_health` skip off the VPS.

## Fixes applied this release

- **DEPLOY gate chain restored.** The `tools/` reorg (`59824d74e`) moved `utf8.rb` into
  `DEPLOY/tools/` but left 10 `require_relative "utf8"` / `"../utf8"` references pointing at the
  old path — every gate that required it crashed with `LoadError`. Repointed all 10 to
  `tools/utf8`.
- **CLI repo-tree bug.** `command_handlers#print_repo_tree` called the non-existent
  `Master::CommandRegistry.tree_lines`; it silently swallowed the `NoMethodError` and never
  rendered. Fixed to `Master::Now::CommandRegistry.dispatch_tree(...).split("\n")`.
- **Web asset drift.** `visual_bridge.js` changed in `f9b6aa57e` without regenerating the
  Propshaft digest; ran `assets:precompile`. Updated the stale boot-manifest test to match the
  DRY `javascript_include_tag(*%w[...])` form.
- **nsaudit robustness.** Now eager-loads before checking (so Zeitwerk-ignored rule fragments
  resolve) and skips `bin/master-kernel` (kernel spine has its own `Master::` namespace). Removed
  the phantom `Master::BedrockStub` and a stale `Master::RepoMap` doc reference it flagged.
- **smoke-web robustness.** A check that raised (e.g. connection refused) crashed the whole run
  with a backtrace; now it reports a clean `fail`, and off-VPS with no server up the smoke skips
  cleanly instead of red-failing the deploy gate.

## Remaining operator step — amber → amberapp.com

The committed stack serves amber at `amber.brgen.no`. To publish it at `amberapp.com`, in one
change (mirrors how `bsdports.org` is wired):

1. **DNS**: delegate `amberapp.com` to the VPS nsd (NS + A → `46.23.89.226`), as `bsdports.org` does.
2. `DEPLOY/openbsd/openbsd.sh`: map `amber:amber.brgen.no` → `amber:amberapp.com`, add
   `amberapp.com` to `ALL_DOMAINS`.
3. `DEPLOY/openbsd/etc/acme-client.conf`: add an `amberapp.com` cert block.
4. `DEPLOY/openbsd/etc/relayd.conf`: add TLS keypair + `Host "amberapp.com"` → `<amber>`.
5. `DEPLOY/master.json` and `DEPLOY/rails/apps.yml`: set amber `domain: amberapp.com`.
6. amber Rails production allowed-hosts config.
7. Redeploy: `openbsd.sh` (stage-1 acme + nsd zone sign) then `doas rcctl restart relayd`.

Keep `amber.brgen.no` as an alias if a clean cutover isn't wanted. This step is gated on the
external DNS delegation, which is why it's left to the operator rather than pre-committed.
