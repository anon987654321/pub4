# mytoonz — agent notes

Archived app (`RAILS/apps.yml` → `archived_apps.mytoonz`). ReplicateService comic-strip generation, `GenerateComicStripJob`. Port 10008 reserved but not currently deployed.

- **Deploy script (dormant):** `mytoonz.sh`. **Recovery source:** `OPERATOR/archive/recovery/installers/mytoonz.sh`.
- Design pass (comic-grid spacing, x.com token parity) landed even while archived — re-run `RAILS/PRODUCTION_READINESS.md`'s checklist (now `RAILS/README.md` § Production readiness) before re-enabling.
- Do not add `mytoonz` back to active deploy inventories without also updating `master.json`.
