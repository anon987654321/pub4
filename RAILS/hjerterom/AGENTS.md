# hjerterom — agent notes

Archived app (`RAILS/apps.yml` → `archived_apps.hjerterom`). Feature-complete food-bank coordination app (donation intake, box coordination, volunteer shifts, route optimization, operator dashboard — all `status: done`). Port 38891 reserved but not currently deployed.

- **Decommissioned 2026-07-11**, not a design/feature gap: the VPS is a 1GB box that couldn't reliably keep 5 Rails apps above `resource_guard.sh`'s free-memory threshold, so this app (the least-trafficked of the three optional ones) was stopped to relieve the recurring shed cycle hitting `amber`/`bsdports`/`hjerterom`.
- **Deploy script (dormant):** `hjerterom.sh`, unmodified and still functional — redeploy is a normal `zsh hjerterom.sh` run if VPS capacity increases (more RAM, or fewer concurrent apps).
- On the VPS: rc.d service stopped and disabled (`doas rcctl stop/disable hjerterom`), and its `relayd.conf` table/routing entries were removed. No source code, database, or `/home/hjerterom` data was deleted.
- Do not add `hjerterom` back to `RAILS/apps.yml`'s active `apps:` list, `RAILS/test/deploy_smoke_contract_test.rb`'s `APPS`, or `.github/workflows/rails-tests.yml`'s CI matrix without confirming VPS memory headroom first.