# Decisions

## Repo Layout (2026-07)

- `RAILS/` — Rails apps + shared engine (was `DEPLOY/rails`)
- `OPENBSD/` — exact VPS configuration backup (`etc/`, `usr/`, `var/`)
- `OPERATOR/openbsd/` — OpenBSD deploy, health, safety, and maintenance tooling
- `OPERATOR/` — gates, bin/, data/, operator docs (was `DEPLOY/` minus rails/openbsd)
- The `DEPLOY → OPERATOR` and `OPERATOR/rails → RAILS`
  compatibility symlinks were removed 2026-07-10 once every reference (rc.d
  scripts, cron scripts, `.gitignore`, comments, both locally and on the VPS)
  was confirmed updated to the direct paths. `MASTER/lib/pub4/paths.rb` still
  contains a runtime `DEPLOY/*` → new-path rewrite for any Ruby code that
  still passes an old-style string in; that's deliberate legacy-string
  tolerance, not a sign the symlinks should come back.

## OpenBSD First

OPERATOR targets OpenBSD vm23. macOS local checks are useful, but OpenBSD behavior wins for package names, service management, relayd, pf, NSD, and Ruby command names.

## relayd Owns TLS

TLS terminates at relayd. Rails apps must use `config.assume_ssl = true` and must not force SSL themselves.

## Loopback App Ports

App ports are internal implementation details. Public ingress is 22, 25, 80, and 443; app ports stay behind relayd.

## `rails/apps.yml` Is Canonical

App status, domains, ports, and deploy scripts live in `RAILS/apps.yml`. `OPERATOR/master.json`, relayd, acme, NSD, and docs should agree with it.

## Copy-Tree Deploy

Rails app trees are copied to `/home/<app>/app`; shared code is copied to `/home/<app>/shared`. Do not assume symlinked repo layout on the VPS.

## MASTER Web Assets Must Be Explicit

Falcon does not hot-reload production assets. MASTER web changes require `rails assets:precompile` and `doas rcctl restart master`.

## Falcon Only (No Puma)

Production app servers on vm23 are Falcon (`falcon serve` in `/etc/rc.d/*`). Do not add Puma or run `bin/rails server` with Puma in production.

Solid Queue inline mode uses the env var `SOLID_QUEUE_IN_PUMA=true` — that name comes from Solid Queue/Rails 8 defaults and means "run the supervisor inside the web server process," not "use Puma." Falcon honors it the same way.

## Release history (from RELEASE.md, merged 2026-07-10)

- **OPERATOR gate chain restored** — repointed 10 `require_relative "utf8"` refs to `tools/utf8`
  after the `tools/` reorg; every gate had been crashing with `LoadError`.
- **CLI + probe bugs** — `Master::CommandRegistry.tree_lines` → `Master::Now::CommandRegistry
  .dispatch_tree`; nsaudit eager-loads + skips the kernel spine; smoke-web no longer crashes on a
  refused connection and skips cleanly off-VPS; asset drift regenerated.
- **baibl + blognet removed** — apps, relayd, acme, nsd (zones + DNSSEC keys), litestream,
  rc.d, inventories (`master.json`, `apps.yml`), gates, tests, and their vanity/megablog domains
  (`baibl.no`, `blognet.no`, `foodielicio.us`, `anti{casino,gambling,betting}blog.com`).
- **Web "tap to start" hardening** — added a platform-level guard in `chat/index.html.erb` that
  blocks WebGL context creation until the primer tap, enforcing the deferred-boot contract so a
  stale/eager asset can't wedge the main thread (the recurring dead-tap bug).

## Open decisions (2026-07-10)

Two things surfaced during an incident-response session that are policy
calls, not code fixes — flagging rather than guessing:

- **No staging environment.** Every fix tonight (a stale asset restart, an
  rc.d rewrite, a resource-guard bug fix) was diagnosed and verified
  directly against production, on the only environment that exists. Adding
  a full staging copy on vm23 itself would worsen the existing 1-vCPU/1GB
  resource pressure (see `OPERATOR/openbsd/resource_guard.sh`); a real fix needs
  either a second (smaller) VPS or an explicit decision to keep accepting
  this risk.
- **Auto-commit atomicity.** An unrelated automated process periodically
  commits to `main` (training-themed messages, but also repo-restructuring
  and asset-rebuild commits observed this session) and sometimes bundles
  unrelated changes into one commit, or writes a commit message describing
  something the diff doesn't actually contain. Whoever owns that process
  should scope commits to one concern each — this repo's own tooling can't
  enforce that from the outside.
