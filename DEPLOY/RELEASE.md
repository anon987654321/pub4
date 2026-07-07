# Release readiness

Status: **ready** — MASTER and DEPLOY gates green on the release branch. Four Rails apps
(brgen, amber, hjerterom, bsdports) + MASTER. `baibl` and `blognet` were removed from the stack.

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
| amber | https://amber.brgen.no | yes |
| hjerterom | https://hjerterom.brgen.no | yes |
| bsdports | https://bsdports.org | yes |

The brgen verticals are one Rails app under subdomains; relayd routes them all
(`openbsd/etc/relayd.conf`). Everything above is wired and passes the gates.

## Verified green

```
cd MASTER && bin/ci                 # unit + kernel tests
cd MASTER && bin/probe all          # smoke, nsaudit, kernel, dogfood, preflight, rails, phantom_fk
cd MASTER && bin/probe deploy       # rails, phantom_fk, crawl, integrity, smoke-web, playbook
ruby DEPLOY/integrity_gate.rb       # deploy_identity, production, phantom_fk, frontend, relayd, domain_align, crawl
```

macOS-only skips (expected): `crawl`/`smoke-web` with no local server, `crawl-browser`/`health`/`vps_health` off-VPS.

## Changes in this release

- **DEPLOY gate chain restored** — repointed 10 `require_relative "utf8"` refs to `tools/utf8`
  after the `tools/` reorg; every gate had been crashing with `LoadError`.
- **CLI + probe bugs** — `Master::CommandRegistry.tree_lines` → `Master::Now::CommandRegistry
  .dispatch_tree`; nsaudit eager-loads + skips the kernel spine; smoke-web no longer crashes on a
  refused connection and skips cleanly off-VPS; asset drift regenerated.
- **baibl + blognet removed** — apps, relayd, acme, nsd (zones + DNSSEC keys), litestream,
  rc.d, inventories (`master.json`, `apps.yml`), gates, tests, and their vanity/megablog domains
  (`baibl.no`, `blognet.no`, `foodielicio.us`, `anti{casino,gambling,betting}blog.com`).
- **Web "tap to start" hardening** — added a platform-level guard in `chat/index.html.erb` that
  blocks WebGL context creation until the primer tap, enforcing the deferred-boot contract so a
  stale/eager asset can't wedge the main thread (the recurring dead-tap bug). Redeploy note below.

## Deploy checklist

1. `cd /home/dev/pub4 && git pull --ff-only`
2. Full stack: `cd DEPLOY/openbsd && tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"`
3. **MASTER web must precompile + restart** (Falcon has no hot-reload; skipping this is the usual
   cause of stale-UI / dead-tap reports): `cd MASTER/web && RAILS_ENV=production rails assets:precompile`
   then `doas rcctl restart master`. The full `openbsd.sh` run already does this.
4. Verify: `ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps` and open `https://ai.brgen.no`,
   tap to start, confirm the particle face renders.

Remaining feature work: `BACKLOG.yml` (open) and `DEPLOY/rails/apps.horizon.yml` (planned, agent: ignore).
