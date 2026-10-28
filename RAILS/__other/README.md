# RAILS/\_\_other — ikke-Rails produkter

Standalone produkter som ikke er en del av Rails-stakkmatrisen
(`apps.yml#rails_stack`). De deler maskinen og OPENBSD-treets
driftskonvensjoner (httpd, relayd, acme), men serveres etter egne
kontrakter, beskrevet i hver mappe.

| Mappe       | Produkt             | Stack                     | Domene           | Status  |
|-------------|---------------------|---------------------------|------------------|---------|
| `sommerseth/` | Sommerseth Eiendom | Statisk HTML/CSS/JS | thor.brgen.no  | planned |
| `alfa/`       | Alfa Bergen        | Statisk HTML/CSS/JS | alfa.brgen.no  | planned |

Begge er bygget på **Bergen-snittet v1** og doktrinen i
`MASTER/docs/visual/bergen_brand_systems.md`. Designlovene ligger i
`MASTER/law/brand.rb` (kjør dem med MASTER /fix), palettene og
merkeparametrene i `MASTER/data/tokens.yml#tokens.brand_systems`.

Deploy: `zsh OPENBSD/bin/vps-deploy-static all` installerer trærne til
httpd-loopback (38191/38192) bak relayd-TLS — samme topologi som Rails-appene,
med httpd som backend i stedet for Falcon. Trærne er rene HTML/CSS/JS-trær
uten byggetrinn; det som ligger i git er det som serveres. Første aktivering
(DNS, SAN-sertifikat, konfig): sjekklisten nederst i `OPENBSD/etc/relayd.conf`;
porter og status registreres i `RAILS/apps.yml#static_exports`.
