# RAILS/\_\_other — ikke-Rails produkter

Standalone produkter som ikke er en del av Rails-stakkmatrisen
(`apps.yml#rails_stack`). De deler maskinen og OPENBSD-treets
driftskonvensjoner (httpd, relayd, acme), men bygger og serveres etter egne
kontrakter, beskrevet i hver mappe.

| Mappe       | Produkt             | Stack                     | Status  |
|-------------|---------------------|---------------------------|---------|
| `sommerseth/` | Sommerseth Eiendom | Next.js 16, statisk eksport | planned |
| `alfa/`       | Alfa Bergen        | Next.js 16, statisk eksport | planned |

Begge er bygget på **Bergen-snittet v1** og doktrinen i
`MASTER/docs/visual/bergen_brand_systems.md`. Designlovene ligger i
`MASTER/law/brand.rb` (kjør dem med MASTER /fix), palettene og
merkeparametrene i `MASTER/data/tokens.yml#tokens.brand_systems`.

Deploy: statisk eksport (`bun run build` → `out/`) serveres av httpd bak
relayd-TLS. Sjekklisten ved domenekjøp står i `OPENBSD/etc/relayd.conf`
(nederst) og `OPENBSD/etc/httpd.conf` (nederst); portene og statusene
registreres i `RAILS/apps.yml#static_exports`.
