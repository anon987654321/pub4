# bsdports — agent notes

- **Domain:** bsdports.org. **Port:** 47312. **Deploy root:** `DEPLOY/rails/bsdports`.
- **Jobs:** `PortsImportJob` in `config/recurring.yml`; requires `db/queue_schema.rb` + Solid Queue on VPS.
- **Golden checks:** `DEPLOY/bin/check-rails --profile=contributor`.
- **VPS:** `bin/pub4 vps deploy bsdports --remote`.
- **Explore:** `Ports::ExploreAssistant` at `/ports/:id/explore`.