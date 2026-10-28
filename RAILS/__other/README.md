# RAILS/\_\_other — ikke-Rails produkter

Standalone produkter som ikke er en del av Rails-stakkmatrisen
(`apps.yml#rails_stack`). De deler maskinen og OPENBSD-treets
driftskonvensjoner (httpd, relayd, acme), men bygger og serveres etter egne
kontrakter, beskrevet i hver mappe.

| Mappe       | Produkt             | Stack                     | Domene           | Status  |
|-------------|---------------------|---------------------------|------------------|---------|
| `sommerseth/` | Sommerseth Eiendom | Next.js 16, statisk eksport | thor.brgen.no  | planned |
| `alfa/`       | Alfa Bergen        | Next.js 16, statisk eksport | alfa.brgen.no  | planned |

Begge er bygget på **Bergen-snittet v1** og doktrinen i
`MASTER/docs/visual/bergen_brand_systems.md`. Designlovene ligger i
`MASTER/law/brand.rb` (kjør dem med MASTER /fix), palettene og
merkeparametrene i `MASTER/data/tokens.yml#tokens.brand_systems`.

Deploy: `zsh OPENBSD/bin/vps-deploy-static all` bygger og installerer til
httpd-loopback (38191/38192) bak relayd-TLS — samme topologi som Rails-appene,
med httpd som backend i stedet for Falcon. Første aktivering (DNS, SAN-sertifikat,
konfig): sjekklisten nederst i `OPENBSD/etc/relayd.conf`; porter og status
registreres i `RAILS/apps.yml#static_exports`.
