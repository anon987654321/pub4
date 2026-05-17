# brgen domain matrix

This file maps the domains declared in `DEPLOY/openbsd/openbsd.sh` to Rails locale, city identity, marketplace label, and subapp surfaces.

`openbsd.sh` is the DNS source of truth. Rails must mirror this map before production traffic goes live.

## Rule

A request host decides four things:

1. city
2. locale
3. currency
4. active subapp

Do not infer locale from browser headers before checking the host. Host wins.

## Shared subapps

Every brgen city domain should support these surfaces unless explicitly disabled:

- marketplace
- playlist
- dating
- tv
- takeaway
- maps

`brgen.no` also declares `ai`.

## Marketplace aliases

| Label | Language | Domains |
|---|---|---|
| `markedsplass` | Norwegian | `.no` city domains |
| `markadur` | Icelandic | `reykjavk.is` |
| `markedsplads` | Danish | `kbenhvn.dk` |
| `marknadsplats` | Swedish | Swedish city domains |
| `markkinapaikka` | Finnish | `hlsinki.fi` |
| `marktplaats` | Dutch | Dutch city domains |
| `marche` | French | French and Belgian city domains |
| `marktplatz` | German | German, Swiss, Liechtenstein, Polish city domains for now |
| `mercato` | Italian | `mlan.it` |
| `mercado` | Portuguese | `lisbon.pt` |
| `marketplace` | English | UK and US city domains |

## City domains

| Domain | City | Country | Locale | Currency | Marketplace subdomain |
|---|---|---|---|---|---|
| `brgen.no` | Bergen | Norway | `nb` | `NOK` | `markedsplass` |
| `longyearbyn.no` | Longyearbyen | Norway | `nb` | `NOK` | `markedsplass` |
| `oshlo.no` | Oslo | Norway | `nb` | `NOK` | `markedsplass` |
| `stvanger.no` | Stavanger | Norway | `nb` | `NOK` | `markedsplass` |
| `trmso.no` | Tromsø | Norway | `nb` | `NOK` | `markedsplass` |
| `trndheim.no` | Trondheim | Norway | `nb` | `NOK` | `markedsplass` |
| `reykjavk.is` | Reykjavik | Iceland | `is` | `ISK` | `markadur` |
| `kbenhvn.dk` | København | Denmark | `da` | `DKK` | `markedsplads` |
| `gtebrg.se` | Göteborg | Sweden | `sv` | `SEK` | `marknadsplats` |
| `mlmoe.se` | Malmö | Sweden | `sv` | `SEK` | `marknadsplats` |
| `stholm.se` | Stockholm | Sweden | `sv` | `SEK` | `marknadsplats` |
| `hlsinki.fi` | Helsinki | Finland | `fi` | `EUR` | `markkinapaikka` |
| `brmingham.uk` | Birmingham | United Kingdom | `en-GB` | `GBP` | `marketplace` |
| `cardff.uk` | Cardiff | United Kingdom | `en-GB` | `GBP` | `marketplace` |
| `edinbrgh.uk` | Edinburgh | United Kingdom | `en-GB` | `GBP` | `marketplace` |
| `glasgw.uk` | Glasgow | United Kingdom | `en-GB` | `GBP` | `marketplace` |
| `lndon.uk` | London | United Kingdom | `en-GB` | `GBP` | `marketplace` |
| `lverpool.uk` | Liverpool | United Kingdom | `en-GB` | `GBP` | `marketplace` |
| `mnchester.uk` | Manchester | United Kingdom | `en-GB` | `GBP` | `marketplace` |
| `amstrdam.nl` | Amsterdam | Netherlands | `nl` | `EUR` | `marktplaats` |
| `rottrdam.nl` | Rotterdam | Netherlands | `nl` | `EUR` | `marktplaats` |
| `utrcht.nl` | Utrecht | Netherlands | `nl` | `EUR` | `marktplaats` |
| `brssels.be` | Brussels | Belgium | `fr-BE` | `EUR` | `marche` |
| `zrich.ch` | Zürich | Switzerland | `de-CH` | `CHF` | `marktplatz` |
| `lchtenstein.li` | Liechtenstein | Liechtenstein | `de-LI` | `CHF` | `marktplatz` |
| `frankfrt.de` | Frankfurt | Germany | `de` | `EUR` | `marktplatz` |
| `brdeaux.fr` | Bordeaux | France | `fr` | `EUR` | `marche` |
| `mrseille.fr` | Marseille | France | `fr` | `EUR` | `marche` |
| `mlan.it` | Milan | Italy | `it` | `EUR` | `mercato` |
| `lisbon.pt` | Lisbon | Portugal | `pt` | `EUR` | `mercado` |
| `wrsawa.pl` | Warszawa | Poland | `pl` | `PLN` | `marktplatz` |
| `gdnsk.pl` | Gdańsk | Poland | `pl` | `PLN` | `marktplatz` |
| `austn.us` | Austin | United States | `en-US` | `USD` | `marketplace` |
| `chcago.us` | Chicago | United States | `en-US` | `USD` | `marketplace` |
| `denvr.us` | Denver | United States | `en-US` | `USD` | `marketplace` |
| `dllas.us` | Dallas | United States | `en-US` | `USD` | `marketplace` |
| `dnver.us` | Denver | United States | `en-US` | `USD` | `marketplace` |
| `dtroit.us` | Detroit | United States | `en-US` | `USD` | `marketplace` |
| `houstn.us` | Houston | United States | `en-US` | `USD` | `marketplace` |
| `lsangeles.com` | Los Angeles | United States | `en-US` | `USD` | `marketplace` |
| `mnnesota.com` | Minneapolis / Minnesota | United States | `en-US` | `USD` | `marketplace` |
| `newyrk.us` | New York | United States | `en-US` | `USD` | `marketplace` |
| `prtland.com` | Portland | United States | `en-US` | `USD` | `marketplace` |
| `wshingtondc.com` | Washington DC | United States | `en-US` | `USD` | `marketplace` |

## Known naming issues

These are intentional domain spellings in DNS, but Rails must map them to readable city names:

- `oshlo.no` -> Oslo
- `trmso.no` -> Tromsø
- `trndheim.no` -> Trondheim
- `reykjavk.is` -> Reykjavik
- `kbenhvn.dk` -> København
- `gtebrg.se` -> Göteborg
- `mlmoe.se` -> Malmö
- `stholm.se` -> Stockholm
- `hlsinki.fi` -> Helsinki
- `lndon.uk` -> London
- `lsangeles.com` -> Los Angeles

`denvr.us` and `dnver.us` both point to Denver. That duplication should be resolved before launch unless it is deliberate.

## Rails implementation target

Add a host resolver before controller actions:

- `Brgen::DomainRegistry.resolve(request.host)`
- set `Current.city`
- set `Current.country`
- set `Current.currency`
- set `I18n.locale`
- set `Current.subapp`

Subdomain detection should happen after base-domain resolution.

Examples:

- `lsangeles.com` sets `I18n.locale = :"en-US"`
- `marketplace.lsangeles.com` sets `Current.subapp = :marketplace`
- `amstrdam.nl` sets `I18n.locale = :nl`
- `marktplaats.amstrdam.nl` sets `Current.subapp = :marketplace`
- `brgen.no` sets `I18n.locale = :nb`
- `markedsplass.brgen.no` sets `Current.subapp = :marketplace`

## Test requirements

Add request tests for every domain in this file.

Each test must assert:

- host resolves
- locale is correct
- city is correct
- currency is correct
- marketplace alias routes to marketplace
- unknown subdomain returns a safe 404 or redirect

## Deployment requirement

Any change to `ALL_DOMAINS` in `DEPLOY/openbsd/openbsd.sh` must update this file and the Rails domain registry in the same commit.