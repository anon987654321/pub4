# brgen — agent notes

Full Rails 8 app in this directory (`app/views`, `config`, `db`, `test`). **Not** a greenfield scaffold step — `brgen.sh` copy-tree deploys this tree to `/home/brgen/app` on vm23.

- **Domain:** brgen.no (+ vertical subdomains). **Port:** 38182. **Deploy root:** `RAILS/brgen`.
- **Shared engine:** `RAILS/shared` — prefer concerns there over duplicating in brgen.
- **Inventory:** `RAILS/apps.yml` (active); horizon work in `apps.horizon.yml` (ignore).
- **Golden checks:** `OPERATOR/bin/check-rails --profile=contributor`; scan via `cd MASTER && bundle exec ruby bin/cli` → `/scan RAILS/brgen`.
- **VPS:** `bin/pub4 vps deploy brgen --remote` (serial — never parallel with other apps).
- **Do not:** enable `force_ssl` behind relayd; edit `master.json` without updating `apps.yml`.