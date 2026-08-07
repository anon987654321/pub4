# Decisions

Deploy and VPS policy. Agent/runtime policy lives in `MASTER/DECISIONS.md`.

## No Fourth Public App Until brgen Boundaries Hold (2026-07)

**Status:** accepted  
**Context:** brgen already hosts many verticals (social, marketplace, dating, playlist, takeaway, TV, maps, live, messenger) in one deployable Rails app. Historical restarts (aight → ai3 → pub2 → pub3 → pub4) repeatedly expanded surface before isolation and shared contracts were boring.

**Decision:** Do not add a **fourth public Rails app** (beyond brgen, amber, bsdports) until:

1. High-churn brgen verticals (marketplace, dating, takeaway at minimum) are **namespaced engines** with their own migrations and test boundaries (still one `rc.d` service is fine).
2. Cross-cutting money (**øre/cents**) and **trust/identity** primitives live in `RAILS/shared` with unit tests consumed by more than one app.
3. CI runs **layout_suite** (design craft) plus **/up smoke** for all three inventory apps on every relevant change.

**Consequences:** New product energy goes into Bergen density (seed, guest demo path Live → listing → message) and engine extraction, not `hjerterom`/`blognet`-class launches. Horizon ideas stay in `RAILS/apps.horizon.yml` with `agent: ignore` until the three gates above are green.

## Repo Layout (2026-07)

- `RAILS/` — Rails apps + shared engine (was `DEPLOY/rails`)
- `OPENBSD/` — VPS config backup (`etc/`, `usr/`, `var/`) plus deploy tooling (`bin/`, `lib/`, `sh/`, gates)
- The `DEPLOY → OPERATOR → OPENBSD` renames completed 2026-07-14; legacy path strings still resolve via `MASTER/lib/pub4/paths.rb`

## OpenBSD First

OPENBSD targets vm23. macOS local checks are useful, but OpenBSD behavior wins for package names, service management, relayd, pf, NSD, and Ruby command names.

## The Nameserver Owns The Zones, Not The Repo (2026-08-02)

We run our own authoritative nsd with a lot of domains — 61 zones in
`/var/nsd/zones/master`, none of them in git, and that is deliberate. The
signed artifacts (`*.zone.signed`, `K*.key`, `K*.ds`) are regenerated on every
re-sign, so mirroring zone data would put a churning copy of the DNS into every
diff while the nameserver stays the real source of truth.

`OPENBSD/sync.rb` used to glob all four zone patterns. It had never actually
been run, which is the only reason the repo is clean of them; the globs are now
removed so the first person to run it does not import 61 zones by accident.
`nsd.conf` is still mirrored — that is server configuration, not zone data.

An audit that reports "61 zone files missing from the repo" is describing this
decision, not a gap. Do not close it.

## relayd Owns TLS

TLS terminates at relayd. Rails apps must use `config.assume_ssl = true` and must not force SSL themselves.

## Loopback App Ports

App ports are internal implementation details. Public ingress is 22, 25, 80, and 443; app ports stay behind relayd.

## `rails/apps.yml` Is Canonical

App status, domains, ports, and deploy scripts live in `RAILS/apps.yml`. `OPENBSD/deploy_inventory.json`, relayd, acme, NSD, and docs should agree with it.

## Copy-Tree Deploy

Rails app trees are copied to `/home/<app>/app`; shared code is copied to `/home/<app>/shared`. Do not assume symlinked repo layout on the VPS.

## MASTER Web Assets Must Be Explicit

Falcon does not hot-reload production assets. MASTER web changes require `rails assets:precompile` and `doas rcctl restart master`.

## Falcon Only (No Puma)

Production app servers on vm23 are Falcon (`falcon serve` in `/etc/rc.d/*`). Do not add Puma or run `bin/rails server` with Puma in production.

Solid Queue inline mode uses the env var `SOLID_QUEUE_IN_PUMA=true` — that name comes from Solid Queue/Rails 8 defaults and means "run the supervisor inside the web server process," not "use Puma." Falcon honors it the same way.

## Deploy Script Names

- `OPENBSD/OPERATOR.sh` — full vm23 OpenBSD installer (etc/usr/var, relayd, services)
- `RAILS/deploy.sh` — Rails app copy-tree deploy only (brgen, amber, bsdports)

## Release history (from RELEASE.md, merged 2026-07-10)

- **Gate chain restored** — repointed `require_relative "utf8"` refs after the `tools/` reorg; every gate had been crashing with `LoadError`.
- **CLI + probe bugs** — `Master::CommandRegistry.tree_lines` → `Master::Now::CommandRegistry.dispatch_tree`; nsaudit eager-loads + skips the kernel spine; smoke-web no longer crashes on a refused connection and skips cleanly off-VPS; asset drift regenerated.
- **baibl + blognet removed** — apps, relayd, acme, nsd (zones + DNSSEC keys), litestream, rc.d, inventories (`deploy_inventory.json`, `apps.yml`), gates, tests, and their vanity/megablog domains.
- **Web "tap to start" hardening** — platform-level guard in `chat/index.html.erb` blocks WebGL until primer tap.

## Open decisions (2026-07-10)

- **No staging environment.** vm23 is the only environment; a full staging copy would worsen 1-vCPU/1GB pressure (see `OPENBSD/resource_guard.sh`).
- **Auto-commit atomicity.** Unrelated automated commits to `main` sometimes bundle unrelated changes; scope commits to one concern each.
