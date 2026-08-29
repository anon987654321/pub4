# bsdports — agent notes

- **Domain:** bsdports.org. **Port:** 47312. **Deploy root:** `RAILS/bsdports`.
- **Jobs:** `PortsImportJob` in `config/recurring.yml`; requires
  `db/queue_schema.rb` + Solid Queue on VPS.
- **Golden checks:** `OPENBSD/bin/check-rails --profile=contributor`.
- **VPS:** `MASTER/bin/pub4 vps deploy bsdports --remote`.
- **Explore:** `Ports::ExploreAssistant` at `/ports/:id/explore`.
